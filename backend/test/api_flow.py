"""End-to-end check of the HTTP calls the app makes (Supabase Auth + PostgREST).

Usage:
    AUTH_URL=http://localhost:9999 REST_URL=http://localhost:3000 ANON_KEY=... python3 api_flow.py

Against a real Supabase project the URLs are <project>/auth/v1 and <project>/rest/v1.
It creates throwaway accounts, so only point it at a test project.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

AUTH = os.environ["AUTH_URL"].rstrip("/")
REST = os.environ["REST_URL"].rstrip("/")
ANON = os.environ["ANON_KEY"]
RUN = uuid.uuid4().hex[:6]
FAILURES = []


def call(method, url, body=None, token=None, prefer=None):
    # Same headers as the app: the public key always, the player's token only when signed in.
    headers = {"apikey": ANON, "Accept": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if prefer:
        headers["Prefer"] = prefer
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, raw.decode(errors="replace")


def check(name, cond, detail=""):
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  -> {detail}"))
    if not cond:
        FAILURES.append(name)


def signup(username, email, password="hunter22!"):
    return call("POST", AUTH + "/signup", {"email": email, "password": password, "data": {"username": username}})


def login(email, password="hunter22!"):
    return call("POST", AUTH + "/token?grant_type=password", {"email": email, "password": password})


LIST = "select=id,title,views,likes,created_at,author_id,author:profiles!levels_author_id_fkey(username)"
LEVEL = {"version": 1, "name": "Test", "cols": 14, "rows": 20, "rock": "1" * 14 + "0" * (14 * 19),
         "fuel": 25, "theme": 0, "start": {"c": 2, "r": 1}, "goal": {"c": 10, "r": 1}, "items": []}

# --- accounts
st, body = call("POST", REST + "/rpc/username_available", {"p_name": "alice" + RUN})
check("username_available rpc", st == 200 and body is True, (st, body))

st, a = signup("alice" + RUN, f"alice{RUN}@example.com")
check("sign up returns a session", st == 200 and "access_token" in a, (st, a))
alice = a["access_token"]
alice_id = a["user"]["id"]
alice_refresh = a["refresh_token"]
check("sign up returns expires_in", isinstance(a.get("expires_in"), int), a.get("expires_in"))

st, b = signup("bob" + RUN, f"bob{RUN}@example.com")
check("second sign up", st == 200 and "access_token" in b, (st, b))

st, e = signup(("ALICE" + RUN).upper(), f"other{RUN}@example.com")
print("     duplicate username ->", st, e)
check("duplicate username rejected", st >= 400, (st, e))

st, e = signup("x", f"short{RUN}@example.com")
print("     bad username ->", st, e)
check("bad username rejected", st >= 400, (st, e))

st, e = signup("carol" + RUN, f"alice{RUN}@example.com")
print("     duplicate email ->", st, e)
check("duplicate email rejected", st >= 400, (st, e))

st, e = signup("dave" + RUN, f"dave{RUN}@example.com", password="123")
print("     weak password ->", st, e)
check("weak password rejected", st >= 400, (st, e))

st, e = login(f"bob{RUN}@example.com", "wrong-password")
print("     wrong password ->", st, e)
check("wrong password rejected", st == 400, (st, e))

st, b = login(f"bob{RUN}@example.com")
check("password sign in", st == 200 and "access_token" in b, (st, b))
bob = b["access_token"]
bob_id = b["user"]["id"]

st, prof = call("GET", REST + f"/profiles?id=eq.{alice_id}&select=username,is_admin", token=alice)
print("     alice profile ->", prof)
check("profile fetch", st == 200 and len(prof) == 1 and prof[0]["username"] == "alice" + RUN, (st, prof))
st, prof_b = call("GET", REST + f"/profiles?id=eq.{bob_id}&select=username,is_admin", token=bob)
check("bob is not admin", st == 200 and prof_b[0]["is_admin"] is False, prof_b)

# --- publishing
st, rows = call("POST", REST + "/levels", {"title": "Bob's Cave " + RUN, "data": LEVEL}, token=bob,
                prefer="return=representation")
check("publish", st == 201 and len(rows) == 1, (st, rows))
bob_level = rows[0]["id"]
check("publish author forced", rows[0]["author_id"] == bob_id, rows[0])

st, e = call("POST", REST + "/levels", {"title": "Anon", "data": LEVEL}, prefer="return=representation")
print("     anon publish ->", st, e)
check("anon cannot publish", st in (401, 403) and e.get("code") == "42501", (st, e))

st, rows = call("POST", REST + "/levels", {"title": "Alice Peak " + RUN, "data": LEVEL}, token=alice,
                prefer="return=representation")
alice_level = rows[0]["id"]

# --- browsing
st, lst = call("GET", REST + f"/levels?{LIST}&order=created_at.desc&limit=30&offset=0")
check("list newest with author", st == 200 and any(r["id"] == bob_level and r["author"]["username"] == "bob" + RUN for r in lst), (st, lst))
print("     row ->", lst[0])
st, lst = call("GET", REST + f"/levels?{LIST}&order=likes.desc,created_at.desc&limit=30&offset=0")
check("list top", st == 200, (st, lst))
st, lst = call("GET", REST + f"/levels?{LIST}&order=views.desc,created_at.desc&limit=30&offset=0")
check("list most viewed", st == 200, (st, lst))
st, lst = call("GET", REST + f"/levels?{LIST}&author_id=eq.{bob_id}&order=created_at.desc&limit=30&offset=0", token=bob)
check("list mine", st == 200 and [r["id"] for r in lst] == [bob_level], (st, lst))
st, lst = call("GET", REST + f"/levels?{LIST}&title=ilike.*cave%20{RUN}*&order=created_at.desc&limit=30")
check("search by title", st == 200 and len(lst) == 1, (st, lst))
st, d = call("GET", REST + f"/levels?id=eq.{bob_level}&select=data")
check("fetch level data", st == 200 and d[0]["data"]["cols"] == 14, (st, d))

# --- views and likes
st, v = call("POST", REST + "/rpc/register_view", {"p_level": bob_level})
check("anon view", st == 200 and v == 1, (st, v))
st, v = call("POST", REST + "/rpc/register_view", {"p_level": bob_level}, token=alice)
check("signed-in view", st == 200 and v == 2, (st, v))
st, r = call("POST", REST + "/rpc/toggle_like", {"p_level": bob_level}, token=alice)
check("like", st == 200 and r == {"liked": True, "likes": 1}, (st, r))
st, r = call("POST", REST + "/rpc/toggle_like", {"p_level": bob_level})
print("     anon like ->", st, r)
check("anon cannot like", st in (401, 403), (st, r))
st, mine = call("GET", REST + f"/level_likes?select=level_id&level_id=in.({bob_level},{alice_level})", token=alice)
check("my likes", st == 200 and mine == [{"level_id": bob_level}], (st, mine))
st, lst = call("GET", REST + f"/levels?{LIST}&id=eq.{bob_level}")
check("counters visible", lst[0]["views"] == 2 and lst[0]["likes"] == 1, lst)
st, r = call("PATCH", REST + f"/levels?id=eq.{bob_level}", {"likes": 999}, token=bob, prefer="return=representation")
print("     patch counters ->", st, r)
check("cannot edit counters", st >= 400, (st, r))

# --- deleting
st, rows = call("DELETE", REST + f"/levels?id=eq.{alice_level}", token=bob, prefer="return=representation")
check("bob cannot delete alice's level", st == 200 and rows == [], (st, rows))
if prof[0]["is_admin"]:
    st, rows = call("DELETE", REST + f"/levels?id=eq.{bob_level}", token=alice, prefer="return=representation")
    check("admin deletes any level", st == 200 and len(rows) == 1, (st, rows))
else:
    print("skip admin delete (alice is not the first account on this database)")
    st, rows = call("DELETE", REST + f"/levels?id=eq.{bob_level}", token=bob, prefer="return=representation")
    check("author deletes own level (bob)", st == 200 and len(rows) == 1, (st, rows))
st, rows = call("DELETE", REST + f"/levels?id=eq.{alice_level}", token=alice, prefer="return=representation")
check("author deletes own level", st == 200 and len(rows) == 1, (st, rows))

# --- tokens
st, t = call("POST", AUTH + "/token?grant_type=refresh_token", {"refresh_token": alice_refresh})
check("refresh token", st == 200 and "access_token" in t, (st, t))
st, t2 = call("POST", AUTH + "/token?grant_type=refresh_token", {"refresh_token": "nonsense"})
print("     bad refresh ->", st, t2)
check("bad refresh rejected", st >= 400, (st, t2))
st, _ = call("POST", AUTH + "/logout", {}, token=t["access_token"])
check("logout", st == 204, st)
st, _ = call("GET", REST + "/levels?select=id&limit=1", token="not-a-jwt")
check("garbage token rejected", st == 401, st)

print()
print("FAILED: " + ", ".join(FAILURES) if FAILURES else "ALL PASSED")
sys.exit(1 if FAILURES else 0)
