"""Read-only health check of the community server (a Supabase project).

    python3 tools/check_server.py Thrustbound/Resources/backend.json

It never signs up, publishes, likes or counts views: the first account on the
server becomes the admin, so this must not create one. It checks that
backend/schema.sql was run, that the public key works for browsing, and how
sign-up is configured.
"""
import json
import sys
import urllib.error
import urllib.request

cfg = json.load(open(sys.argv[1]))
BASE = cfg["url"].rstrip("/")
KEY = cfg["anonKey"].strip()
problems = []


def get(path, method="GET", body=None, headers=None):
    h = {"apikey": KEY, "Accept": "application/json"}
    h.update(headers or {})
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            raw = r.read()
            return r.status, dict(r.headers), (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, dict(e.headers), json.loads(raw)
        except ValueError:
            return e.code, dict(e.headers), raw.decode(errors="replace")


print("Server:", BASE)
print("Key type:", "publishable" if KEY.startswith("sb_publishable_") else "anon JWT" if KEY.startswith("eyJ") else "unknown")

st, _, body = get("/rest/v1/levels?select=id,views,likes&limit=1000")
if st == 200:
    print(f"ok   levels table is installed ({len(body)} published level(s))")
else:
    problems.append("levels table missing: run backend/schema.sql in the Supabase SQL Editor")
    print(f"FAIL levels -> {st} {body}")

st, _, body = get("/rest/v1/profiles?select=is_admin")
if st == 200:
    admins = sum(1 for p in body if p.get("is_admin"))
    print(f"ok   profiles table is installed ({len(body)} account(s), {admins} admin(s))")
    if not body:
        print("     no accounts yet: the first account created becomes the admin")
else:
    problems.append("profiles table missing: run backend/schema.sql")
    print(f"FAIL profiles -> {st} {body}")

st, _, body = get("/rest/v1/rpc/username_available", "POST", {"p_name": "zz_health_check"})
if st == 200 and isinstance(body, bool):
    print("ok   username_available() works for signed-out players")
else:
    problems.append("username_available() is missing or not allowed: run backend/schema.sql")
    print(f"FAIL username_available -> {st} {body}")

st, _, body = get("/rest/v1/level_likes?select=level_id&limit=1")
if st in (401, 403) or (st == 200 and body == []):
    print("ok   likes are private to their owner")
else:
    print(f"warn level_likes -> {st} {body}")

st, _, body = get("/auth/v1/settings")
if st == 200:
    autoconfirm = body.get("mailer_autoconfirm")
    print(f"ok   auth settings: email sign-up {'on' if body.get('external', {}).get('email') else 'OFF'}, "
          f"confirm email {'off' if autoconfirm else 'ON (good)'}, sign-ups {'disabled' if body.get('disable_signup') else 'allowed'}")
    if not body.get("external", {}).get("email"):
        problems.append("Email sign-in is turned off in Authentication -> Sign In / Providers")
    if body.get("disable_signup"):
        problems.append("Sign-ups are disabled in Authentication settings")
    if autoconfirm:
        print("     new accounts work right away; turn on \"Confirm email\" so players must enter the code emailed to them")
    else:
        print("     new players enter the code from their confirmation email (the template needs {{ .Token }})")
else:
    problems.append("auth settings not readable")
    print(f"FAIL auth settings -> {st} {body}")

# Browsers (the website and the Android app) need CORS.
st, headers, _ = get("/rest/v1/levels?select=id&limit=1", "OPTIONS", None, {
    "Origin": "https://99mac88-afk.github.io",
    "Access-Control-Request-Method": "GET",
    "Access-Control-Request-Headers": "apikey,authorization,content-type,prefer"})
allow = {k.lower(): v for k, v in headers.items()}.get("access-control-allow-origin")
if allow in ("*", "https://99mac88-afk.github.io"):
    print(f"ok   browsers may call the API (CORS {allow})")
else:
    problems.append("CORS preflight did not allow the website")
    print(f"FAIL CORS preflight -> {st} {headers}")

print()
if problems:
    print("PROBLEMS:")
    for p in problems:
        print(" -", p)
    sys.exit(1)
print("Server looks ready.")
