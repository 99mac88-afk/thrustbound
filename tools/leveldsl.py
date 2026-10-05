"""
Tiny level-authoring DSL for Thrustbound.

Coordinates are in game points with the origin at the bottom-left of the
level and y pointing up (the same convention SpriteKit uses).

A level is built from:
  * a base: either "open" (empty interior) or "cave" (solid interior),
  * carves: regions removed from the base (rooms, tunnels),
  * solids: regions added on top (rocks, shelves, pillars),
  * pads, collectibles and hazards.

The terrain that ships in levels.json is the boolean union of the border
frame, the carved base and the solids, so the game never has to deal with
overlapping polygons or hidden interior edges.
"""

import math
import random

from shapely.geometry import LineString, Point, Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import unary_union

BORDER = 20          # thickness of the playable frame
EXTEND = 1000        # frame continues this far outside the level (render only)
PAD_H = 10           # landing pad slab thickness
SPIKE_SIZE = 14      # nominal spike width / height


def _jag_ring(coords, amp, step, rng):
    """Subdivide a closed ring and push the new points in/out randomly.
    Original corners are kept exactly so flat floors stay where they were."""
    pts = list(coords)
    if pts[0] == pts[-1]:
        pts = pts[:-1]
    out = []
    n = len(pts)
    for i in range(n):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % n]
        dx, dy = x1 - x0, y1 - y0
        length = math.hypot(dx, dy)
        out.append((x0, y0))
        if length < step * 1.5:
            continue
        k = int(length // step)
        nx, ny = -dy / length, dx / length
        for j in range(1, k):
            t = j / k
            off = rng.uniform(-amp, amp)
            out.append((x0 + dx * t + nx * off, y0 + dy * t + ny * off))
    return out


def jag(geom, amp, step, rng):
    if amp <= 0 or geom.is_empty:
        return geom
    polys = [geom] if geom.geom_type == "Polygon" else list(geom.geoms)
    result = []
    for p in polys:
        shell = _jag_ring(p.exterior.coords, amp, step, rng)
        holes = [_jag_ring(h.coords, amp, step, rng) for h in p.interiors]
        q = Polygon(shell, holes).buffer(0)
        result.append(q)
    return unary_union(result)


class Level:
    def __init__(self, name, w=420, h=1000, hint="", base="open", jag=0.0,
                 jag_step=26, fuel=None, fuel_margin=1.8, par=None):
        self.name = name
        self.w = w
        self.h = h
        self.hint = hint
        self.base = base
        self.default_jag = jag
        self.jag_step = jag_step
        self.fuel = fuel
        self.fuel_margin = fuel_margin
        self.par = par
        self.world = 0
        self.index = 0
        self._carves = []
        self._solids = []
        self.start_pad = None
        self.goal_pad = None
        self.stars = []
        self.cans = []
        self.spike_tris = []
        self.mines = []
        self.spinners = []
        self.lasers = []
        self.winds = []
        self.keys = []
        self.doors = []
        self._gates = []
        self._terrain = None
        self.rng = random.Random(name)

    # ------------------------------------------------------------ geometry
    def _j(self, geom, jag_amp):
        amp = self.default_jag if jag_amp is None else jag_amp
        return jag(geom, amp, self.jag_step, self.rng)

    def rect(self, x, y, w, h, jag=None):
        """Solid rectangle (x, y = bottom-left)."""
        self._solids.append(self._j(box(x, y, x + w, y + h), jag))
        return self

    def poly(self, pts, jag=None):
        """Solid polygon."""
        self._solids.append(self._j(Polygon(pts).buffer(0), jag))
        return self

    def rock(self, x, y, r, n=7, jag=None, squash=1.0):
        """Roughly round floating rock centred at (x, y)."""
        pts = []
        for i in range(n):
            a = 2 * math.pi * i / n + self.rng.uniform(-0.2, 0.2)
            rr = r * self.rng.uniform(0.85, 1.1)
            pts.append((x + math.cos(a) * rr, y + math.sin(a) * rr * squash))
        return self.poly(pts, jag)

    def left(self, profile, jag=None):
        """Solid wall attached to the left border. profile = [(y, x), ...]
        listing how far the wall reaches at each height (bottom to top)."""
        pts = [(0, profile[0][0])] + [(x, y) for (y, x) in profile] + [(0, profile[-1][0])]
        return self.poly(pts, jag)

    def right(self, profile, jag=None):
        """Solid wall attached to the right border. profile = [(y, x), ...]."""
        pts = [(self.w, profile[0][0])] + [(x, y) for (y, x) in profile] + [(self.w, profile[-1][0])]
        return self.poly(pts, jag)

    def floor(self, profile, jag=None):
        """Solid ground attached to the floor. profile = [(x, y), ...]."""
        pts = [(profile[0][0], 0)] + list(profile) + [(profile[-1][0], 0)]
        return self.poly(pts, jag)

    def ceiling(self, profile, jag=None):
        pts = [(profile[0][0], self.h)] + list(profile) + [(profile[-1][0], self.h)]
        return self.poly(pts, jag)

    def carve_rect(self, x, y, w, h, jag=None):
        self._carves.append(self._j(box(x, y, x + w, y + h), jag))
        return self

    def carve_poly(self, pts, jag=None):
        self._carves.append(self._j(Polygon(pts).buffer(0), jag))
        return self

    def tunnel(self, pts, width, jag=None, round_ends=True):
        """Carve a tunnel of the given width along a polyline."""
        cap = 1 if round_ends else 2
        g = LineString(pts).buffer(width / 2.0, cap_style=cap, join_style=1, quad_segs=6)
        self._carves.append(self._j(g, jag))
        return self

    def carve_circle(self, x, y, r, jag=None):
        self._carves.append(self._j(Point(x, y).buffer(r, quad_segs=8), jag))
        return self

    # ------------------------------------------------------------ pads
    def start(self, x, y, w=64):
        """Launch pad. (x, y) = centre of the pad's top surface."""
        self.start_pad = (x, y, w)
        return self

    def goal(self, x, y, w=64):
        """Landing pad. (x, y) = centre of the pad's top surface."""
        self.goal_pad = (x, y, w)
        return self

    # ------------------------------------------------------------ items
    def star(self, x, y):
        self.stars.append((x, y))
        return self

    def can(self, x, y):
        self.cans.append((x, y))
        return self

    def key(self, x, y, color=0):
        self.keys.append({"p": [x, y], "color": color})
        return self

    def door(self, x, y, w, h, color=0):
        self.doors.append({"rect": [x, y, w, h], "color": color})
        return self

    # ------------------------------------------------------------ hazards
    def spikes(self, x, y, length, dir="up", size=SPIKE_SIZE):
        """Row of spikes. For up/down rows (x, y) is the left end of the base;
        for left/right rows it is the bottom end of the base."""
        n = max(1, int(round(length / size)))
        sw = length / n
        for i in range(n):
            if dir == "up":
                tri = [(x + i * sw, y), (x + (i + 1) * sw, y), (x + (i + 0.5) * sw, y + size)]
            elif dir == "down":
                tri = [(x + (i + 1) * sw, y), (x + i * sw, y), (x + (i + 0.5) * sw, y - size)]
            elif dir == "right":
                tri = [(x, y + (i + 1) * sw), (x, y + i * sw), (x + size, y + (i + 0.5) * sw)]
            elif dir == "left":
                tri = [(x, y + i * sw), (x, y + (i + 1) * sw), (x - size, y + (i + 0.5) * sw)]
            else:
                raise ValueError(dir)
            self.spike_tris.append(tri)
        return self

    def mine(self, x, y, r=13, path=None, speed=0.0, loop=False):
        pts = [(x, y)] + (path or [])
        self.mines.append({"r": r, "path": [list(p) for p in pts], "speed": speed, "loop": loop})
        return self

    def orbit_mine(self, cx, cy, radius, r=13, speed=1.0, phase=0.0, n=28):
        """Mine circling (cx, cy). speed in radians/sec (negative = clockwise)."""
        pts = []
        direction = 1 if speed >= 0 else -1
        for i in range(n):
            a = phase + direction * 2 * math.pi * i / n
            pts.append([cx + math.cos(a) * radius, cy + math.sin(a) * radius])
        # path is an n-gon, so convert angular speed to speed along its perimeter
        self.mines.append({"r": r, "path": pts, "speed": abs(speed) * radius *
                           (n * math.sin(math.pi / n) / math.pi), "loop": True})
        return self

    def spinner(self, x, y, length, arms=2, speed=1.2, phase=0.0):
        self.spinners.append({"c": [x, y], "len": length, "arms": arms, "speed": speed, "phase": phase})
        return self

    def laser(self, ax, ay, bx, by, on=1.5, off=1.5, phase=0.0):
        self.lasers.append({"a": [ax, ay], "b": [bx, by], "on": on, "off": off, "phase": phase})
        return self

    def gate(self, y, x, on=1.5, off=1.5, phase=0.0):
        """Horizontal laser spanning the open gap that contains (x, y).
        Endpoints are found from the finished terrain."""
        self._gates.append(("laser", y, x, dict(on=on, off=off, phase=phase)))
        return self

    def door_across(self, y, x, color=0, thickness=24):
        """Door plugging the open gap that contains (x, y)."""
        self._gates.append(("door", y, x, dict(color=color, thickness=thickness)))
        return self

    def wind(self, x, y, w, h, fx, fy):
        self.winds.append({"rect": [x, y, w, h], "force": [fx, fy]})
        return self

    # ------------------------------------------------------------ build
    def interior(self):
        return box(BORDER, BORDER, self.w - BORDER, self.h - BORDER)

    def terrain_geometry(self):
        if self._terrain is None:
            self._terrain = self._build_terrain()
            self._resolve_gates()
        return self._terrain

    def _gap_at(self, y, x):
        line = LineString([(0, y), (self.w, y)])
        free = line.difference(self._terrain)
        parts = [free] if free.geom_type == "LineString" else list(free.geoms)
        for seg in parts:
            xs = [c[0] for c in seg.coords]
            if min(xs) <= x <= max(xs):
                return min(xs), max(xs)
        raise ValueError(f"{self.name}: no open gap at ({x}, {y})")

    def _resolve_gates(self):
        for kind, y, x, opts in self._gates:
            x0, x1 = self._gap_at(y, x)
            if kind == "laser":
                self.lasers.append({"a": [x0 - 4, y], "b": [x1 + 4, y], "on": opts["on"],
                                    "off": opts["off"], "phase": opts["phase"]})
            else:
                t = opts["thickness"]
                self.doors.append({"rect": [x0 - 8, y - t / 2, (x1 - x0) + 16, t],
                                   "color": opts["color"]})
        self._gates = []

    def _build_terrain(self):
        frame = box(-EXTEND, -EXTEND, self.w + EXTEND, self.h + EXTEND).difference(self.interior())
        parts = [frame]
        if self.base == "cave":
            solid = self.interior()
            if self._carves:
                solid = solid.difference(unary_union(self._carves))
            parts.append(solid)
        elif self._carves:
            raise ValueError(f"{self.name}: carves need base='cave'")
        parts.extend(self._solids)
        # Pads sit flush in the ground: give each a flat foundation and shave
        # off any jagged bumps poking up next to it.
        for pad in (self.start_pad, self.goal_pad):
            if pad is None:
                continue
            x, y, w = pad
            parts.append(box(x - w / 2 - 2, y - PAD_H - 8, x + w / 2 + 2, y))
        geom = unary_union(parts).buffer(0)
        for pad in (self.start_pad, self.goal_pad):
            if pad is None:
                continue
            x, y, w = pad
            geom = geom.difference(box(x - w / 2 - 2, y, x + w / 2 + 2, y + 12))
        geom = geom.buffer(0).simplify(0.4, preserve_topology=True)
        return geom

    def pad_geometry(self, pad):
        x, y, w = pad
        return box(x - w / 2, y - PAD_H, x + w / 2, y)

    def door_geometry(self, d):
        x, y, w, h = d["rect"]
        return box(x, y, x + w, y + h)


def _r(v):
    return round(float(v), 1)


def export_polygons(geom):
    polys = [geom] if geom.geom_type == "Polygon" else [g for g in geom.geoms if g.geom_type == "Polygon"]
    out = []
    for p in polys:
        if p.area < 4:
            continue
        p = orient(p, sign=1.0)
        rings = [[[_r(x), _r(y)] for (x, y) in list(p.exterior.coords)[:-1]]]
        for hole in p.interiors:
            if Polygon(hole).area < 4:
                continue
            rings.append([[_r(x), _r(y)] for (x, y) in list(hole.coords)[:-1]])
        out.append(rings)
    return out


def level_to_json(lv, level_id, fuel):
    def pt(p):
        return [_r(p[0]), _r(p[1])]

    def rnd(obj):
        if isinstance(obj, float):
            return _r(obj)
        if isinstance(obj, list):
            return [rnd(o) for o in obj]
        if isinstance(obj, dict):
            return {k: rnd(v) for k, v in obj.items()}
        return obj

    sx, sy, sw = lv.start_pad
    gx, gy, gw = lv.goal_pad
    return {
        "id": level_id,
        "world": lv.world,
        "name": lv.name,
        "hint": lv.hint,
        "size": [lv.w, lv.h],
        "fuel": _r(fuel),
        "par": _r(lv.par),
        "start": [_r(sx), _r(sy), _r(sw)],
        "goal": [_r(gx), _r(gy), _r(gw)],
        "terrain": export_polygons(lv.terrain_geometry()),
        "stars": [pt(s) for s in lv.stars],
        "cans": [pt(c) for c in lv.cans],
        "spikes": [[pt(p) for p in tri] for tri in lv.spike_tris],
        "mines": rnd(lv.mines),
        "spinners": rnd(lv.spinners),
        "lasers": rnd(lv.lasers),
        "winds": rnd(lv.winds),
        "keys": rnd(lv.keys),
        "doors": rnd(lv.doors),
    }
