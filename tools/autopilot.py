#!/usr/bin/env python3
"""
Flies every level with a simple autopilot, using a Python copy of the game's
physics (GameWorld.swift), to check that each level can be completed with the
fuel it provides.

Moving hazards (lasers, spinners, moving mines) are switched off for the
autopilot: they are about timing, not fuel or space, and the validator
already checks their clearance.

  python3 tools/autopilot.py            # all levels
  python3 tools/autopilot.py 7 12       # some levels
"""

import heapq
import json
import math
import os
import sys

import numpy as np
from scipy import ndimage
import shapely
from shapely.geometry import Point, Polygon, box
from shapely.ops import unary_union

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEVELS = os.path.join(ROOT, "Thrustbound", "Resources", "levels.json")

# --- constants mirrored from GameWorld.swift --------------------------------
G = 160.0
THRUST = 400.0
DRAG = 0.3
MAX_SPEED = 480.0
TURN = 6.5
CRASH = 130.0
LAND_TILT = 0.30
LAND_SPEED = 30.0
LAND_HOLD = 0.6
RESTITUTION = 0.25
FRICTION = 5.0
STEP = 1.0 / 240.0
CAN_FUEL = 10.0
PICKUP = 26.0
FORGIVE = 1.5
HULL = [((0, 12), 6), ((0, 0), 8), ((0, -10), 8), ((-10, -17), 3), ((10, -17), 3)]
FEET = [2, 3, 4]
SPAWN = 20.0


def wrap(a):
    a = math.fmod(a, 2 * math.pi)
    if a > math.pi:
        a -= 2 * math.pi
    if a < -math.pi:
        a += 2 * math.pi
    return a


def closest(ax, ay, bx, by, px, py):
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    if l2 < 1e-9:
        return ax, ay
    t = ((px - ax) * dx + (py - ay) * dy) / l2
    t = 0.0 if t < 0 else (1.0 if t > 1 else t)
    return ax + dx * t, ay + dy * t


class Sim:
    CELL = 32.0

    def __init__(self, lv):
        self.lv = lv
        self.segs = []
        for poly in lv["terrain"]:
            for ring in poly:
                n = len(ring)
                for i in range(n):
                    a, b = ring[i], ring[(i + 1) % n]
                    if (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 > 1e-6:
                        self.segs.append((a[0], a[1], b[0], b[1], -1))
        for di, d in enumerate(lv["doors"]):
            x, y, w, h = d["rect"]
            c = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
            for i in range(4):
                a, b = c[i], c[(i + 1) % 4]
                self.segs.append((a[0], a[1], b[0], b[1], di))
        self.grid = {}
        for si, (ax, ay, bx, by, _) in enumerate(self.segs):
            x0 = int(math.floor((min(ax, bx) - 12) / self.CELL))
            x1 = int(math.floor((max(ax, bx) + 12) / self.CELL))
            y0 = int(math.floor((min(ay, by) - 12) / self.CELL))
            y1 = int(math.floor((max(ay, by) + 12) / self.CELL))
            if (x1 - x0) * (y1 - y0) > 4000:
                # huge outer frame edges: clip to the level area
                x0, x1 = max(x0, -2), min(x1, int(lv["size"][0] / self.CELL) + 2)
                y0, y1 = max(y0, -2), min(y1, int(lv["size"][1] / self.CELL) + 2)
            for gx in range(x0, x1 + 1):
                for gy in range(y0, y1 + 1):
                    self.grid.setdefault((gx, gy), []).append(si)
        self.static_mines = [m for m in lv["mines"] if len(m["path"]) == 1 or m["speed"] == 0]
        self.reset()

    def reset(self):
        sx, sy, _ = self.lv["start"]
        self.x, self.y = sx, sy + SPAWN
        self.vx = self.vy = 0.0
        self.angle = 0.0
        self.fuel = self.lv["fuel"]
        self.unlimited = False
        self.status = "flying"
        self.stars, self.cans, self.keys, self.doors = set(), set(), set(), set()
        self.land_t = 0.0
        self.time = 0.0
        self.fuel_used = 0.0
        self.why = ""

    def circles(self):
        c, s = math.cos(self.angle), math.sin(self.angle)
        for (ox, oy), r in HULL:
            yield self.x + ox * c - oy * s, self.y + ox * s + oy * c, r

    def step(self, thrust, target):
        dt = STEP
        self.time += dt
        if self.status != "flying":
            return
        if target is not None:
            diff = wrap(target - self.angle)
            m = TURN * dt
            self.angle = wrap(self.angle + max(-m, min(m, diff)))
        ax, ay = 0.0, -G
        on = thrust and self.fuel > 0
        if on:
            ax += -math.sin(self.angle) * THRUST
            ay += math.cos(self.angle) * THRUST
            self.fuel = max(0.0, self.fuel - dt)
            self.fuel_used += dt
        for w in self.lv["winds"]:
            x, y, ww, hh = w["rect"]
            if x <= self.x <= x + ww and y <= self.y <= y + hh:
                ax += w["force"][0]
                ay += w["force"][1]
        self.vx += ax * dt
        self.vy += ay * dt
        k = max(0.0, 1 - DRAG * dt)
        self.vx *= k
        self.vy *= k
        sp = math.hypot(self.vx, self.vy)
        if sp > MAX_SPEED:
            self.vx *= MAX_SPEED / sp
            self.vy *= MAX_SPEED / sp
        self.x += self.vx * dt
        self.y += self.vy * dt
        self.collide(dt)
        if self.status != "flying":
            return
        self.hazards()
        if self.status != "flying":
            return
        self.pickups()
        self.landing(dt)

    def collide(self, dt):
        worst = 0.0
        c, s = math.cos(self.angle), math.sin(self.angle)
        for (ox, oy), r in HULL:
            cx = self.x + ox * c - oy * s
            cy = self.y + ox * s + oy * c
            cell = (int(math.floor(cx / self.CELL)), int(math.floor(cy / self.CELL)))
            for si in self.grid.get(cell, ()):
                ax_, ay_, bx_, by_, door = self.segs[si]
                if door >= 0 and door in self.doors:
                    continue
                qx, qy = closest(ax_, ay_, bx_, by_, cx, cy)
                dx, dy = cx - qx, cy - qy
                d2 = dx * dx + dy * dy
                if d2 >= r * r:
                    continue
                d = math.sqrt(d2)
                if d > 1e-5:
                    nx, ny = dx / d, dy / d
                else:
                    ex, ey = bx_ - ax_, by_ - ay_
                    l = math.hypot(ex, ey)
                    nx, ny = ey / l, -ex / l
                push = r - d
                self.x += nx * push
                self.y += ny * push
                cx += nx * push
                cy += ny * push
                vn = self.vx * nx + self.vy * ny
                if vn < 0:
                    worst = max(worst, -vn)
                    bounce = RESTITUTION if -vn > 40 else 0.0
                    self.vx -= nx * vn * (1 + bounce)
                    self.vy -= ny * vn * (1 + bounce)
                    vn2 = self.vx * nx + self.vy * ny
                    tx, ty = self.vx - nx * vn2, self.vy - ny * vn2
                    f = min(1.0, FRICTION * dt)
                    self.vx -= tx * f
                    self.vy -= ty * f
        if worst > CRASH:
            self.status = "crashed"
            self.why = f"impact {worst:.0f} at ({self.x:.0f},{self.y:.0f})"

    def hazards(self):
        for cx, cy, r in self.circles():
            r = max(1.0, r - FORGIVE)
            for tri in self.lv["spikes"]:
                for i in range(3):
                    a, b = tri[i], tri[(i + 1) % 3]
                    qx, qy = closest(a[0], a[1], b[0], b[1], cx, cy)
                    if (cx - qx) ** 2 + (cy - qy) ** 2 < r * r:
                        self.status = "crashed"
                        self.why = f"spikes at ({cx:.0f},{cy:.0f})"
                        return
            for m in self.static_mines:
                mx, my = m["path"][0]
                if (cx - mx) ** 2 + (cy - my) ** 2 < (r + m["r"]) ** 2:
                    self.status = "crashed"
                    self.why = f"mine at ({mx:.0f},{my:.0f})"
                    return

    def pickups(self):
        r2 = PICKUP * PICKUP
        for i, (x, y) in enumerate(self.lv["stars"]):
            if i not in self.stars and (self.x - x) ** 2 + (self.y - y) ** 2 < r2:
                self.stars.add(i)
        for i, (x, y) in enumerate(self.lv["cans"]):
            if i not in self.cans and (self.x - x) ** 2 + (self.y - y) ** 2 < r2:
                self.cans.add(i)
                if not self.unlimited:
                    self.fuel = min(self.lv["fuel"], self.fuel + CAN_FUEL)
        for i, k in enumerate(self.lv["keys"]):
            x, y = k["p"]
            if i not in self.keys and (self.x - x) ** 2 + (self.y - y) ** 2 < r2:
                self.keys.add(i)
                for di, d in enumerate(self.lv["doors"]):
                    if d["color"] == k["color"]:
                        self.doors.add(di)

    def landing(self, dt):
        gx, gy, gw = self.lv["goal"]
        touching = False
        c, s = math.cos(self.angle), math.sin(self.angle)
        for idx in FEET:
            (ox, oy), r = HULL[idx]
            cx = self.x + ox * c - oy * s
            cy = self.y + ox * s + oy * c
            if gx - gw / 2 - r <= cx <= gx + gw / 2 + r and cy >= gy - 1 and cy - r <= gy + 1.5:
                touching = True
        if touching and abs(self.angle) < LAND_TILT and abs(self.x - gx) <= gw / 2 \
                and math.hypot(self.vx, self.vy) < LAND_SPEED:
            self.land_t += dt
            if self.land_t >= LAND_HOLD:
                self.status = "landed"
        else:
            self.land_t = max(0.0, self.land_t - dt * 2)


# --- path planning ----------------------------------------------------------
CELLP = 6.0


def plan(lv, sim):
    W, H = lv["size"]
    terrain = unary_union([Polygon(p[0], p[1:]) for p in lv["terrain"]]).buffer(0)
    nx, ny = int(math.ceil(W / CELLP)), int(math.ceil(H / CELLP))
    xs = (np.arange(nx) + 0.5) * CELLP
    ys = (np.arange(ny) + 0.5) * CELLP
    gx, gy = np.meshgrid(xs, ys)
    parts = [terrain] + [Polygon(t) for t in lv["spikes"]]
    parts += [Point(*m["path"][0]).buffer(m["r"]) for m in sim.static_mines]
    shapely.prepare(solid_geom := unary_union(parts))
    solid = shapely.contains_xy(solid_geom, gx, gy)
    door_masks = []
    for d in lv["doors"]:
        x, y, w, h = d["rect"]
        door_masks.append((gx >= x) & (gx <= x + w) & (gy >= y) & (gy <= y + h))
    return solid, door_masks, xs, ys


def route(solid, open_mask, start, goal, clear=19.0):
    dist = ndimage.distance_transform_edt(~(solid | open_mask)) * CELLP
    ok = dist >= clear
    h, w = ok.shape

    def cell(p):
        return min(h - 1, max(0, int(p[1] // CELLP))), min(w - 1, max(0, int(p[0] // CELLP)))

    def snap(rc):
        r0, c0 = rc
        best = None
        for dr in range(-6, 7):
            for dc in range(-6, 7):
                r, c = r0 + dr, c0 + dc
                if 0 <= r < h and 0 <= c < w and ok[r, c]:
                    v = dr * dr + dc * dc
                    if best is None or v < best[0]:
                        best = (v, (r, c))
        return best[1] if best else None

    s, g = snap(cell(start)), snap(cell(goal))
    if s is None or g is None:
        return None
    # prefer the middle of corridors: cost grows near walls
    pen = 1.0 + 60.0 / np.maximum(dist, 1.0)
    D = {s: 0.0}
    prev = {}
    pq = [(0.0, s)]
    steps = [(-1, 0, 1), (1, 0, 1), (0, -1, 1), (0, 1, 1), (-1, -1, 1.414), (-1, 1, 1.414), (1, -1, 1.414), (1, 1, 1.414)]
    while pq:
        d, u = heapq.heappop(pq)
        if u == g:
            break
        if d > D.get(u, 1e18):
            continue
        for dr, dc, cost in steps:
            v = (u[0] + dr, u[1] + dc)
            if 0 <= v[0] < h and 0 <= v[1] < w and ok[v]:
                nd = d + cost * pen[v]
                if nd < D.get(v, 1e18):
                    D[v] = nd
                    prev[v] = u
                    heapq.heappush(pq, (nd, v))
    if g not in D:
        return None
    path = [g]
    while path[-1] != s:
        path.append(prev[path[-1]])
    path.reverse()
    pts = [((c + 0.5) * CELLP, (r + 0.5) * CELLP) for r, c in path]
    return pts[::3] + [pts[-1]]


# --- controller -------------------------------------------------------------
def fly(lv, unlimited_fuel=False):
    sim = Sim(lv)
    if unlimited_fuel:
        sim.fuel = 1e9
        sim.unlimited = True
    solid, door_masks, _, _ = plan(lv, sim)
    sx, sy, _ = lv["start"]
    gx, gy, gw = lv["goal"]
    # keys first (in order), then stars and fuel cans nearest-first, then the goal
    targets = [("key", tuple(k["p"]), i) for i, k in enumerate(lv["keys"])]
    pending = [("star", tuple(s), i) for i, s in enumerate(lv["stars"])]
    pending += [("can", tuple(c), i) for i, c in enumerate(lv["cans"])]
    here = tuple(lv["keys"][-1]["p"]) if lv["keys"] else (sx, sy)
    while pending:
        nxt = min(pending, key=lambda t: math.hypot(t[1][0] - here[0], t[1][1] - here[1]))
        pending.remove(nxt)
        targets.append(nxt)
        here = nxt[1]
    targets += [("goal", (gx, gy + 60), -1)]
    pos = (sx, sy + SPAWN + 30)
    waypoints = [(sx, sy + 70)]
    skipped = []
    opened = set()
    for kind, p, idx in targets:
        closed = np.zeros_like(solid)
        for di, m in enumerate(door_masks):
            if di not in opened:
                closed |= m
        r = route(solid, closed, pos, p)
        if r is None:
            if kind == "goal":
                return {"ok": False, "why": "no route to goal"}
            skipped.append(kind)
            continue
        waypoints += r
        pos = p
        if kind == "key":
            color = lv["keys"][idx]["color"]
            opened |= {di for di, d in enumerate(lv["doors"]) if d["color"] == color}
    wp = 0
    t = 0.0
    duty_acc = 0.0
    landing_phase = False
    max_time = 400.0
    while t < max_time and sim.status == "flying":
        if not landing_phase:
            tx, ty = waypoints[wp]
            dx, dy = tx - sim.x, ty - sim.y
            dist = math.hypot(dx, dy)
            if dist < 22 and wp < len(waypoints) - 1:
                wp += 1
                continue
            if wp == len(waypoints) - 1 and dist < 14:
                landing_phase = True
                continue
            vmax = 110.0
            # slow down for upcoming turns
            if wp + 1 < len(waypoints):
                nx_, ny_ = waypoints[wp + 1]
                v1 = (tx - sim.x, ty - sim.y)
                v2 = (nx_ - tx, ny_ - ty)
                l1, l2 = math.hypot(*v1) or 1, math.hypot(*v2) or 1
                cosang = (v1[0] * v2[0] + v1[1] * v2[1]) / (l1 * l2)
                if cosang < 0.7:
                    vmax = 70.0
            speed = min(vmax, 2.0 * dist + 25)
            vdx, vdy = dx / (dist or 1) * speed, dy / (dist or 1) * speed
            vdy = max(vdy, -90.0)
        else:
            # hover above the pad centre and sink slowly
            dx = gx - sim.x
            vdx = max(-40, min(40, dx * 2.0))
            vdy = -28.0 if abs(dx) < 6 else 0.0
            if sim.y - (gy + SPAWN) > 60:
                vdy = -55.0
        axd = (vdx - sim.vx) * 3.0
        ayd = (vdy - sim.vy) * 3.0 + G
        for w in lv["winds"]:
            x, y, ww, hh = w["rect"]
            if x <= sim.x <= x + ww and y <= sim.y <= y + hh:
                axd -= w["force"][0]
                ayd -= w["force"][1]
        if ayd < -40:
            # an updraft is stronger than gravity: point the nose down and push
            mag = math.hypot(axd, ayd)
            target = math.atan2(-axd, ayd)
        else:
            if ayd < 20:
                ayd = 20  # otherwise never point down
            mag = math.hypot(axd, ayd)
            target = math.atan2(-axd, ayd)
            target = max(-1.1, min(1.1, target))
        if landing_phase and abs(dx) < 10:
            target = 0.0
        err = abs(wrap(target - sim.angle))
        duty = min(1.0, mag / THRUST) if err < 0.6 else 0.0
        duty_acc += duty
        thrust = duty_acc >= 1.0
        if thrust:
            duty_acc -= 1.0
        sim.step(thrust, target)
        t += STEP
    used = sim.fuel_used
    sim.fuel = min(sim.fuel, lv["fuel"])
    return {"ok": sim.status == "landed", "status": sim.status, "why": sim.why, "time": t,
            "used": used, "fuel": lv["fuel"], "stars": len(sim.stars), "skipped": skipped,
            "cans": len(sim.cans), "wp": f"{wp}/{len(waypoints)}", "pos": (round(sim.x), round(sim.y))}


def main():
    data = json.load(open(LEVELS))
    want = {int(a) for a in sys.argv[1:]} or None
    bad = 0
    for lv in data["levels"]:
        if want and lv["id"] not in want:
            continue
        r = fly(lv)
        mark = "OK " if r["ok"] else "FAIL"
        if r["ok"]:
            print(f"{mark} {lv['id']:2d} {lv['name']:<20} time {r['time']:6.1f}s fuel used {r['used']:5.1f}/{r['fuel']:4.0f}s "
                  f"stars {r['stars']}/3 cans {r['cans']}")
        else:
            bad += 1
            print(f"{mark} {lv['id']:2d} {lv['name']:<20} {r.get('status')} {r.get('why')} wp {r.get('wp')} "
                  f"pos {r.get('pos')} fuel used {r.get('used', 0):.1f}/{r.get('fuel', 0):.0f}")
    print(f"{bad} level(s) not completed by the autopilot")


if __name__ == "__main__":
    main()
