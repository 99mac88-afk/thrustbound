#!/usr/bin/env python3
"""
Builds Thrustbound/Resources/levels.json from tools/levels.py and validates
every level:

  * pads rest on solid ground and the rocket spawns in free space,
  * the goal, every star, fuel can and key is reachable by a rocket-sized
    body (grid flood fill over cells with enough clearance), honouring
    doors that only open once their key is collected,
  * nothing collectible is buried in rock or sitting on a hazard,
  * fuel is computed from the shortest route so every level is finishable.

Usage:
  * the autopilot (tools/autopilot.py) can fly the whole level, collecting
    every star, on the fuel the level gives; tanks are sized so the
    autopilot needs at most `fuel_ratio` of them.

Usage:
  python3 tools/build_levels.py            # build + validate
  python3 tools/build_levels.py --render DIR   # also write PNG previews
  python3 tools/build_levels.py --fast         # skip the autopilot flights
"""

import itertools
import json
import math
import os
import sys

import numpy as np
import shapely
from scipy import ndimage
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union

sys.path.insert(0, os.path.dirname(__file__))
import autopilot  # noqa: E402
import leveldsl  # noqa: E402
from levels import WORLDS, build_all  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Thrustbound", "Resources", "levels.json")

CELL = 4.0              # flood-fill grid resolution (points)
ROCKET_CLEAR = 17.0     # min distance from rocket centre to rock to pass
SPAWN_HEIGHT = 20.0     # rocket centre sits this far above a pad's top
CAN_FUEL = 10.0         # seconds of thrust in a fuel can (matches Swift)


class LevelError(Exception):
    pass


def hazard_geometry(lv, include_dynamic=False):
    parts = [Polygon(t) for t in lv.spike_tris]
    for m in lv.mines:
        if len(m["path"]) == 1 or m["speed"] == 0:
            x, y = m["path"][0]
            parts.append(Point(x, y).buffer(m["r"]))
        elif include_dynamic:
            parts.append(LineString(m["path"] + ([m["path"][0]] if m["loop"] else [])).buffer(m["r"]))
    if include_dynamic:
        for s in lv.spinners:
            parts.append(Point(*s["c"]).buffer(s["len"] + 5))
        for la in lv.lasers:
            parts.append(LineString([la["a"], la["b"]]).buffer(3))
    return unary_union(parts) if parts else None


def grid_for(lv, terrain, extra_solids):
    nx = int(math.ceil(lv.w / CELL))
    ny = int(math.ceil(lv.h / CELL))
    xs = (np.arange(nx) + 0.5) * CELL
    ys = (np.arange(ny) + 0.5) * CELL
    gx, gy = np.meshgrid(xs, ys)
    solid_geom = unary_union([terrain] + [g for g in extra_solids if g is not None])
    shapely.prepare(solid_geom)
    solid = shapely.contains_xy(solid_geom, gx, gy)
    dist = ndimage.distance_transform_edt(~solid) * CELL
    return solid, dist, xs, ys


def cell_of(x, y, lv):
    return int(y // CELL), int(x // CELL)


def flood(dist, start_rc, clear):
    ok = dist >= clear
    if not ok[start_rc]:
        return None
    labels, _ = ndimage.label(ok)
    return labels == labels[start_rc]


def geodesic(dist, start_rc, clear):
    """BFS distances (in points) from start over passable cells (8-connected)."""
    ok = dist >= clear
    h, w = ok.shape
    INF = 1e18
    d = np.full(ok.shape, INF)
    if not ok[start_rc]:
        return d
    import heapq
    d[start_rc] = 0
    pq = [(0.0, start_rc)]
    steps = [(-1, 0, 1), (1, 0, 1), (0, -1, 1), (0, 1, 1),
             (-1, -1, 1.4142), (-1, 1, 1.4142), (1, -1, 1.4142), (1, 1, 1.4142)]
    while pq:
        cd, (r, c) = heapq.heappop(pq)
        if cd > d[r, c]:
            continue
        for dr, dc, cost in steps:
            rr, cc = r + dr, c + dc
            if 0 <= rr < h and 0 <= cc < w and ok[rr, cc]:
                nd = cd + cost * CELL
                if nd < d[rr, cc]:
                    d[rr, cc] = nd
                    heapq.heappush(pq, (nd, (rr, cc)))
    return d


def nearest_ok(dist, rc, clear, radius_cells=4):
    """Items float in open space but may sit a little close to rock; snap to
    the nearest passable cell within a small radius."""
    r0, c0 = rc
    best = None
    for dr in range(-radius_cells, radius_cells + 1):
        for dc in range(-radius_cells, radius_cells + 1):
            r, c = r0 + dr, c0 + dc
            if 0 <= r < dist.shape[0] and 0 <= c < dist.shape[1] and dist[r, c] >= clear:
                dd = dr * dr + dc * dc
                if best is None or dd < best[0]:
                    best = (dd, (r, c))
    return None if best is None else best[1]


def validate(lv):
    errors = []
    info = {}
    terrain = lv.terrain_geometry()
    if lv.start_pad is None or lv.goal_pad is None:
        raise LevelError("missing start or goal pad")
    pads = [lv.pad_geometry(lv.start_pad), lv.pad_geometry(lv.goal_pad)]
    hazards = hazard_geometry(lv)
    dyn_hazards = hazard_geometry(lv, include_dynamic=True)
    doors = [lv.door_geometry(d) for d in lv.doors]

    # pads must sit on rock and must not be buried
    for name, pad in (("start", lv.start_pad), ("goal", lv.goal_pad)):
        x, y, w = pad
        for fx in (-0.35, 0.0, 0.35):
            if not terrain.contains(Point(x + fx * w, y - leveldsl.PAD_H - 3)):
                errors.append(f"{name} pad at ({x},{y}) is not resting on rock")
                break
        above = box(x - w / 2 + 2, y + 1, x + w / 2 - 2, y + 44)
        if terrain.intersects(above):
            errors.append(f"{name} pad at ({x},{y}) has rock right above it")
        if dyn_hazards is not None and dyn_hazards.intersects(box(x - w / 2 - 8, y, x + w / 2 + 8, y + 50)):
            errors.append(f"{name} pad at ({x},{y}) is too close to a hazard")

    # grid with every door closed
    solid_all, dist_all, xs, ys = grid_for(lv, terrain, pads + doors + [hazards])
    start_xy = (lv.start_pad[0], lv.start_pad[1] + SPAWN_HEIGHT)
    goal_xy = (lv.goal_pad[0], lv.goal_pad[1] + SPAWN_HEIGHT)
    start_rc = cell_of(*start_xy, lv)
    if dist_all[start_rc] < 16:
        errors.append(f"spawn point is cramped (clearance {dist_all[start_rc]:.0f})")

    # progressive door opening
    open_doors = set()
    have_keys = set()
    while True:
        solids = [terrain] + pads + [hazards] + [doors[i] for i in range(len(doors)) if i not in open_doors]
        _, dist, _, _ = grid_for(lv, terrain, solids[1:])
        reach = flood(dist, nearest_ok(dist, start_rc, ROCKET_CLEAR) or start_rc, ROCKET_CLEAR)
        if reach is None:
            errors.append("rocket cannot leave the launch pad")
            break
        new_keys = set()
        for i, k in enumerate(lv.keys):
            rc = nearest_ok(dist, cell_of(*k["p"], lv), ROCKET_CLEAR)
            if rc is not None and reach[rc] and i not in have_keys:
                new_keys.add(i)
        if not new_keys:
            break
        have_keys |= new_keys
        colors = {lv.keys[i]["color"] for i in have_keys}
        open_doors = {i for i, d in enumerate(lv.doors) if d["color"] in colors}

    final_dist = dist
    def reachable(xy, what):
        rc = nearest_ok(final_dist, cell_of(*xy, lv), ROCKET_CLEAR)
        if rc is None or reach is None or not reach[rc]:
            errors.append(f"{what} at ({xy[0]:.0f},{xy[1]:.0f}) is unreachable")
            return None
        return rc

    goal_rc = reachable(goal_xy, "goal")
    star_rcs = [reachable(s, "star") for s in lv.stars]
    can_rcs = [reachable(c, "fuel can") for c in lv.cans]
    key_rcs = [reachable(k["p"], "key") for k in lv.keys]
    if len(have_keys) != len(lv.keys):
        errors.append("some keys can never be collected")

    # items must float in open air, away from hazards
    for kind, pts in (("star", lv.stars), ("fuel can", lv.cans), ("key", [k["p"] for k in lv.keys])):
        for p in pts:
            if terrain.distance(Point(p)) < 14:
                errors.append(f"{kind} at {p} overlaps rock")
            if hazards is not None and hazards.distance(Point(p)) < 16:
                errors.append(f"{kind} at {p} sits on a hazard")
    if len(lv.stars) != 3:
        errors.append(f"expected 3 stars, found {len(lv.stars)}")

    # doors must actually be needed somewhere sensible: just make sure they
    # touch rock on both ends so they read as gates
    for d in lv.doors:
        g = lv.door_geometry(d).buffer(2)
        if not g.intersects(terrain):
            errors.append(f"door {d['rect']} floats in the air")

    # minimum clearance along the critical route, measured between points
    # just above the pads (the pads themselves are always a little cramped)
    route_clear = None
    route_a = nearest_ok(final_dist, cell_of(start_xy[0], start_xy[1] + 24, lv), ROCKET_CLEAR)
    route_b = nearest_ok(final_dist, cell_of(goal_xy[0], goal_xy[1] + 24, lv), ROCKET_CLEAR)
    if goal_rc is not None and route_a is not None and route_b is not None:
        start_rc, goal_rc = route_a, route_b
        lo, hi = 8.0, 200.0
        for _ in range(16):
            mid = (lo + hi) / 2
            r = flood(final_dist, start_rc, mid) if final_dist[start_rc] >= mid else None
            if r is not None and r[goal_rc]:
                lo = mid
            else:
                hi = mid
        route_clear = lo
        if route_clear < 22:
            errors.append(f"critical route too narrow (gap ~{2 * route_clear:.0f}pt)")

    # fuel estimate over the full tour start -> keys/stars -> goal
    fuel_needed = None
    if goal_rc is not None and all(rc is not None for rc in star_rcs + key_rcs):
        nodes = [start_rc] + star_rcs + key_rcs + [goal_rc]
        dmaps = [geodesic(final_dist, n, ROCKET_CLEAR) for n in nodes[:-1]]
        middle = list(range(1, len(nodes) - 1))
        best = None
        for perm in itertools.permutations(middle):
            order = [0] + list(perm) + [len(nodes) - 1]
            total = 0.0
            for a, b in zip(order, order[1:]):
                total += dmaps[a][nodes[b]]
            if best is None or total < best:
                best = total
        info["route_len"] = best
        # cost model: ~110pt/s average speed, ~55% throttle duty to fight gravity
        climb = max(0.0, goal_xy[1] - start_xy[1])
        fuel_needed = 0.55 * (best / 110.0 + 2.0) + climb / 400.0
        info["fuel_needed"] = fuel_needed
    info["route_clear"] = route_clear
    return errors, info


def compute_fuel(lv, info):
    if lv.fuel is not None:
        return float(lv.fuel)
    need = info.get("fuel_needed") or 20.0
    return float(max(18, int(math.ceil(need * lv.fuel_margin))))


def render(lv, data, path, scale=0.5):
    from PIL import Image, ImageDraw

    pad = 40
    W = int(lv.w * scale) + 2 * pad
    H = int(lv.h * scale) + 2 * pad + 30
    img = Image.new("RGB", (W, H), (8, 10, 24))
    d = ImageDraw.Draw(img)

    def tp(x, y):
        return (pad + x * scale, pad + 30 + (lv.h - y) * scale)

    world = WORLDS[lv.world]
    neon = tuple(int(world["neon"][i:i + 2], 16) for i in (1, 3, 5))
    rock = tuple(int(world["rock"][i:i + 2], 16) for i in (1, 3, 5))

    for poly in data["terrain"]:
        shell = [tp(*p) for p in poly[0]]
        d.polygon(shell, fill=rock, outline=neon)
        for hole in poly[1:]:
            d.polygon([tp(*p) for p in hole], fill=(8, 10, 24), outline=neon)
    for w in data["winds"]:
        x, y, ww, hh = w["rect"]
        d.rectangle([tp(x, y + hh), tp(x + ww, y)], outline=(90, 160, 255))
        cx, cy = x + ww / 2, y + hh / 2
        fx, fy = w["force"]
        m = math.hypot(fx, fy) or 1
        d.line([tp(cx, cy), tp(cx + fx / m * 40, cy + fy / m * 40)], fill=(90, 160, 255), width=2)
    for door in data["doors"]:
        x, y, ww, hh = door["rect"]
        col = [(255, 194, 61), (46, 240, 224), (255, 106, 213)][door["color"]]
        d.rectangle([tp(x, y + hh), tp(x + ww, y)], fill=col)
    for k in data["keys"]:
        col = [(255, 194, 61), (46, 240, 224), (255, 106, 213)][k["color"]]
        x, y = k["p"]
        d.ellipse([tp(x - 9, y + 9), tp(x + 9, y - 9)], outline=col, width=3)
    for tri in data["spikes"]:
        d.polygon([tp(*p) for p in tri], fill=(255, 46, 77))
    for m in data["mines"]:
        x, y = m["path"][0]
        r = m["r"]
        if len(m["path"]) > 1:
            d.line([tp(*p) for p in m["path"]] + ([tp(*m["path"][0])] if m["loop"] else []), fill=(120, 40, 50))
        d.ellipse([tp(x - r, y + r), tp(x + r, y - r)], fill=(255, 46, 77))
    for s in data["spinners"]:
        x, y = s["c"]
        L = s["len"]
        d.ellipse([tp(x - L, y + L), tp(x + L, y - L)], outline=(120, 40, 50))
        for i in range(s["arms"]):
            a = s["phase"] + 2 * math.pi * i / s["arms"]
            d.line([tp(x, y), tp(x + math.cos(a) * L, y + math.sin(a) * L)], fill=(255, 46, 77), width=4)
    for la in data["lasers"]:
        d.line([tp(*la["a"]), tp(*la["b"])], fill=(255, 60, 60), width=2)
    for c in data["cans"]:
        x, y = c
        d.rectangle([tp(x - 7, y + 9), tp(x + 7, y - 9)], fill=(255, 176, 32))
    for s in data["stars"]:
        x, y = s
        pts = []
        for i in range(10):
            r = 12 if i % 2 == 0 else 5
            a = math.pi / 2 + i * math.pi / 5
            pts.append(tp(x + math.cos(a) * r, y + math.sin(a) * r))
        d.polygon(pts, fill=(255, 225, 77))
    for name, pd, col in (("S", data["start"], (170, 180, 200)), ("G", data["goal"], (68, 255, 136))):
        x, y, w = pd
        d.rectangle([tp(x - w / 2, y), tp(x + w / 2, y - leveldsl.PAD_H)], fill=col)
    sx, sy, _ = data["start"]
    d.rectangle([tp(sx - 8, sy + 40), tp(sx + 8, sy)], outline=(255, 255, 255))
    d.text((8, 8), f"{data['id']}. {data['name']}  fuel {data['fuel']:.0f}s", fill=(255, 255, 255))
    img.save(path)


def main():
    render_dir = None
    if "--render" in sys.argv:
        render_dir = sys.argv[sys.argv.index("--render") + 1]
        os.makedirs(render_dir, exist_ok=True)
    only = None
    if "--only" in sys.argv:
        only = int(sys.argv[sys.argv.index("--only") + 1])

    levels = build_all()
    out_levels = []
    failed = False
    for idx, lv in enumerate(levels):
        level_id = idx + 1
        if only is not None and level_id != only:
            continue
        try:
            errors, info = validate(lv)
        except LevelError as e:
            errors, info = [str(e)], {}
        fuel = compute_fuel(lv, info)
        data = level_to_json_with_par(lv, level_id, fuel, info)
        flown = ""
        if not errors and "--fast" not in sys.argv:
            errors += fly_and_tune(lv, data, info)
            flown = (f" auto {info.get('auto_used', 0):4.1f}s fuel in {info.get('auto_time', 0):5.1f}s")
        out_levels.append(data)
        status = "OK " if not errors else "ERR"
        rc = info.get("route_clear")
        print(f"{status} {level_id:2d} {lv.name:<22} w{lv.world} fuel {data['fuel']:5.1f}s "
              f"route {info.get('route_len') or 0:6.0f}pt gap {2 * rc if rc else 0:4.0f}pt "
              f"par {data['par']:.0f}s{flown}")
        for e in errors:
            print(f"      - {e}")
        if errors:
            failed = True
        if render_dir:
            render(lv, data, os.path.join(render_dir, f"level_{level_id:02d}.png"))

    if only is None:
        doc = {"version": 1, "worlds": WORLDS, "levels": out_levels}
        with open(OUT, "w") as f:
            json.dump(doc, f, separators=(",", ":"))
        print(f"wrote {OUT} ({os.path.getsize(OUT) // 1024} KB, {len(out_levels)} levels)")
    if failed:
        print("VALIDATION FAILED")
        sys.exit(1)


def fly_and_tune(lv, data, info):
    """Fly the level with unlimited fuel to measure what a clean run needs,
    size the tank from that, then fly again on the real tank."""
    errors = []
    measure = autopilot.fly(data, unlimited_fuel=True)
    if not measure["ok"]:
        return [f"autopilot could not finish: {measure.get('status')} {measure.get('why')}"]
    info["auto_used"] = measure["used"]
    info["auto_time"] = measure["time"]
    if lv.fuel is None:
        needed = math.ceil(measure["used"] / lv.fuel_ratio)
        data["fuel"] = float(max(data["fuel"], needed))
    if lv.par_explicit is None:
        data["par"] = float(max(10, int(math.ceil(measure["time"] * 0.85 / 5.0) * 5)))
    check = autopilot.fly(data)
    if not check["ok"]:
        errors.append(f"autopilot ran out of fuel or crashed on the real tank: {check.get('status')} {check.get('why')}")
    elif check["stars"] < len(data["stars"]):
        errors.append("autopilot could not collect every star")
    return errors


def level_to_json_with_par(lv, level_id, fuel, info):
    lv.par_explicit = getattr(lv, "par_explicit", lv.par)
    if lv.par is None:
        route = info.get("route_len") or 800
        lv.par = max(10, int(math.ceil((route / 90.0 + 5) / 5.0) * 5))
    return leveldsl.level_to_json(lv, level_id, fuel)


if __name__ == "__main__":
    main()
