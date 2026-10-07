#!/usr/bin/env bash
# Runs the real Supabase pieces the app talks to (Postgres image, Auth server,
# PostgREST), applies backend/schema.sql and replays every request the app
# makes (api_flow.py). Needs Docker, curl and python3.
#   bash backend/test/run_api_tests.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PG_IMAGE="${PG_IMAGE:-supabase/postgres:17.11.0.004}"
AUTH_IMAGE="${AUTH_IMAGE:-supabase/gotrue:v2.177.0}"
PGRST_VERSION="${PGRST_VERSION:-v12.2.3}"
SECRET="local-test-jwt-secret-that-is-at-least-32-characters"
NET=tb-api-test
WORK="$(mktemp -d)"
PGRST_PID=""

cleanup() {
  [ -n "$PGRST_PID" ] && kill "$PGRST_PID" 2>/dev/null || true
  docker rm -f tb-db tb-auth >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT
cleanup_failed() {
  echo "----- auth log -----"; docker logs tb-auth 2>&1 | tail -n 40 || true
  echo "----- postgrest log -----"; tail -n 40 "$WORK/postgrest.log" 2>/dev/null || true
}
trap 'cleanup_failed' ERR

docker network create "$NET" >/dev/null
docker run -d --name tb-db --network "$NET" -p 127.0.0.1:54329:5432 -e POSTGRES_PASSWORD=postgres "$PG_IMAGE" >/dev/null

psql_db() { docker exec -i tb-db psql -v ON_ERROR_STOP=1 -q -X -h localhost "$@"; }

# The image restarts once after running its init scripts; wait until it is really up.
for i in $(seq 1 90); do
  if psql_db -U supabase_admin -d postgres -tAc "select 1 from pg_roles where rolname = 'supabase_auth_admin'" 2>/dev/null | grep -q 1; then
    break
  fi
  sleep 2
done
sleep 5
psql_db -U supabase_admin -d postgres -tAc "select 1" >/dev/null
psql_db -U supabase_admin -d postgres -c "alter role authenticator with password 'postgres'; alter role supabase_auth_admin with password 'postgres';"

docker run -d --name tb-auth --network "$NET" -p 127.0.0.1:59999:9999 \
  -e GOTRUE_API_HOST=0.0.0.0 -e PORT=9999 -e API_EXTERNAL_URL=http://localhost:59999 \
  -e GOTRUE_DB_DRIVER=postgres -e GOTRUE_DB_DATABASE_URL="postgres://supabase_auth_admin:postgres@tb-db:5432/postgres" \
  -e GOTRUE_SITE_URL=http://localhost -e GOTRUE_JWT_SECRET="$SECRET" -e GOTRUE_JWT_EXP=3600 \
  -e GOTRUE_JWT_AUD=authenticated -e GOTRUE_JWT_DEFAULT_GROUP_NAME=authenticated -e GOTRUE_JWT_ADMIN_ROLES=service_role \
  -e GOTRUE_EXTERNAL_EMAIL_ENABLED=true -e GOTRUE_MAILER_AUTOCONFIRM=true -e GOTRUE_DISABLE_SIGNUP=false \
  "$AUTH_IMAGE" >/dev/null
for i in $(seq 1 60); do
  curl -sf http://127.0.0.1:59999/health >/dev/null 2>&1 && break
  sleep 1
done
curl -sf http://127.0.0.1:59999/health >/dev/null

# Same as pasting schema.sql into the Supabase SQL editor (runs as "postgres"), twice to prove it can be re-run.
for _ in 1 2; do
  psql_db -U postgres -d postgres < "$HERE/../schema.sql" 2>&1 | grep -v NOTICE || true
done
psql_db -U postgres -d postgres -tAc "select count(*) from pg_proc where proname = 'toggle_like'" | grep -q 1

curl -fsSL -o "$WORK/postgrest.tar.xz" \
  "https://github.com/PostgREST/postgrest/releases/download/${PGRST_VERSION}/postgrest-${PGRST_VERSION}-linux-static-x64.tar.xz"
tar -xJf "$WORK/postgrest.tar.xz" -C "$WORK"
cat > "$WORK/postgrest.conf" <<CONF
db-uri = "postgres://authenticator:postgres@127.0.0.1:54329/postgres"
db-schemas = "public"
db-anon-role = "anon"
jwt-secret = "$SECRET"
server-port = 53000
CONF
"$WORK/postgrest" "$WORK/postgrest.conf" > "$WORK/postgrest.log" 2>&1 &
PGRST_PID=$!
for i in $(seq 1 30); do
  curl -sf http://127.0.0.1:53000/levels?limit=1 >/dev/null 2>&1 && break
  sleep 1
done

ANON_KEY="$(SECRET="$SECRET" python3 - <<'PY'
import base64, hashlib, hmac, json, os, time
b64 = lambda d: base64.urlsafe_b64encode(d).rstrip(b"=").decode()
head = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
body = b64(json.dumps({"role": "anon", "iss": "supabase", "iat": int(time.time()), "exp": int(time.time()) + 3600}).encode())
sig = b64(hmac.new(os.environ["SECRET"].encode(), f"{head}.{body}".encode(), hashlib.sha256).digest())
print(f"{head}.{body}.{sig}")
PY
)"

AUTH_URL=http://127.0.0.1:59999 REST_URL=http://127.0.0.1:53000 ANON_KEY="$ANON_KEY" python3 "$HERE/api_flow.py"
