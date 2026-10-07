#!/usr/bin/env bash
# Runs backend/schema.sql against a throwaway PostgreSQL and checks every
# security rule. Needs PostgreSQL server binaries (initdb, pg_ctl, psql).
#   bash backend/test/run_tests.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PGBIN="${PGBIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -n 1)}"
export PATH="$PGBIN:$PATH"
WORK="$(mktemp -d)"
cleanup() { pg_ctl -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

initdb -D "$WORK/data" -U postgres --auth=trust >/dev/null
pg_ctl -D "$WORK/data" -o "-k $WORK -c listen_addresses=''" -l "$WORK/log" -w start >/dev/null
PSQL=(psql -h "$WORK" -U postgres -d postgres -v ON_ERROR_STOP=1 -q -X)

"${PSQL[@]}" -f "$HERE/supabase_stubs.sql"
# Apply the schema twice to prove it can be re-run safely.
for _ in 1 2; do
  "${PSQL[@]}" -c "set role owner;" -f "$HERE/../schema.sql"
done
"${PSQL[@]}" -f "$HERE/tests.sql"
echo "backend schema: all tests passed"
