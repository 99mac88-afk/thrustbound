"""
Worlds 5-8 of Thrustbound (levels 41-80). These levels are built to be
tight on fuel: build_levels.py sizes each tank so the autopilot needs
`fuel_ratio` of it (0.78 in world 5 rising to 0.9 in world 8), and fuel
cans on the route are counted, so skipping them can strand you.
"""

import math
import random

from leveldsl import Level

WORLDS2 = [
    {"name": "Emerald Mines", "subtitle": "Tight tunnels, tighter tanks",
     "nameRu": "Изумрудные копи", "subtitleRu": "Узкие туннели, маленькие баки",
     "neon": "#2EF0A0", "rock": "#082A1E", "bgTop": "#010A06", "bgBottom": "#06281C"},
    {"name": "Acid Falls", "subtitle": "Torrents of wind and mines",
     "nameRu": "Кислотные водопады", "subtitleRu": "Потоки ветра и мины",
     "neon": "#B6FF3B", "rock": "#1C2A08", "bgTop": "#060A01", "bgBottom": "#1A2806"},
    {"name": "Nebula Gardens", "subtitle": "Blades, beams and locks",
     "nameRu": "Сады туманности", "subtitleRu": "Лезвия, лучи и замки",
     "neon": "#FF7AD9", "rock": "#2A0C24", "bgTop": "#0C0309", "bgBottom": "#2A0A26"},
    {"name": "Event Horizon", "subtitle": "The final frontier",
     "nameRu": "Горизонт событий", "subtitleRu": "Последний рубеж",
     "neon": "#E8ECFF", "rock": "#141826", "bgTop": "#010104", "bgBottom": "#0E1224"},
]


def tight(lv, ratio):
    lv.fuel_ratio = ratio
    lv.fuel_margin = 1.0
    lv.tight = True
    return lv


def maze(name, hint, cols, rows, cell, seed, width=110, spinners=0, mines=0, cans=2, jag=5):
    """Fixed-seed maze. Stars go in the three furthest dead ends, fuel cans in
    the next ones; hazards sit on junctions away from the start."""
    rng = random.Random(seed)
    goal_cell = (cols - 1, rows - 1)
    links = set()
    seen = {(0, 0)}
    stack = [(0, 0)]
    while stack:
        c, r = stack[-1]
        options = [(c + dc, r + dr) for dc, dr in ((1, 0), (-1, 0), (0, 1), (0, -1))
                   if 0 <= c + dc < cols and 0 <= r + dr < rows
                   and (c + dc, r + dr) not in seen and (c + dc, r + dr) != goal_cell]
        if not options:
            stack.pop()
            continue
        nxt = rng.choice(options)
        links.add(frozenset([(c, r), nxt]))
        seen.add(nxt)
        stack.append(nxt)
    links.add(frozenset([goal_cell, (cols - 2, rows - 1)]))

    def centre(c, r):
        return (cell * c + cell / 2, cell * r + cell / 2)

    adj = {}
    for link in links:
        a, b = tuple(link)
        adj.setdefault(a, []).append(b)
        adj.setdefault(b, []).append(a)
    dist = {(0, 0): 0}
    queue = [(0, 0)]
    while queue:
        cur = queue.pop(0)
        for n in adj.get(cur, []):
            if n not in dist:
                dist[n] = dist[cur] + 1
                queue.append(n)
    dead = sorted([n for n, ns in adj.items() if len(ns) == 1 and n not in ((0, 0), goal_cell)],
                  key=lambda n: -dist[n])

    lv = Level(name, w=cols * cell, h=rows * cell, base="cave", jag=jag, hint=hint)
    for link in sorted(links, key=lambda l: sorted(l)):
        a, b = sorted(link)
        lv.tunnel([centre(*a), centre(*b)], width)
    lv.carve_rect(20, 20, cell - 40, cell - 40)
    lv.start(cell / 2, 20, 56)
    gx, gy = centre(*goal_cell)
    room = cell - 30
    lv.carve_rect(gx - room / 2, gy - room / 2, room, room)
    lv.goal(gx + 12, gy - room / 2, 56)
    for n in dead[:3]:
        lv.star(*centre(*n))
    for n in dead[3:3 + cans]:
        lv.can(*centre(*n))
    spots = [n for n in sorted(adj) if len(adj[n]) >= 3 and n not in ((0, 0), goal_cell) and dist[n] >= 3]
    rng.shuffle(spots)
    for n in spots[:spinners]:
        lv.spinner(*centre(*n), width * 0.36, arms=2, speed=rng.choice([1.3, -1.3, 1.6, -1.6]))
    straight = [link for link in sorted(links, key=lambda l: sorted(l))
                if all(dist.get(n, 0) >= 2 for n in link) and goal_cell not in link]
    rng.shuffle(straight)
    for link in straight[:mines]:
        a, b = sorted(link)
        ax, ay = centre(*a)
        bx, by = centre(*b)
        lv.mine(ax + (bx - ax) * 0.25, ay + (by - ay) * 0.25, r=12,
                path=[(ax + (bx - ax) * 0.75, ay + (by - ay) * 0.75)], speed=70)
    return lv


# ---------------------------------------------------------------- world 5
def emerald_mines():
    L = []
    R = 0.78

    lv = tight(Level("Mineshaft", h=2000, base="cave", jag=4,
                     hint="Fuel is tight from here on. Dip into the side pockets for cans."), R)
    lv.carve_rect(20, 20, 380, 180)
    lv.tunnel([(210, 150), (210, 1700)], 110, round_ends=False)
    lv.tunnel([(210, 500), (350, 560)], 84)
    lv.tunnel([(210, 900), (70, 960)], 84)
    lv.tunnel([(210, 1300), (350, 1360)], 84)
    lv.tunnel([(210, 1550), (70, 1600)], 84)
    lv.carve_rect(40, 1650, 340, 300)
    lv.start(210, 20)
    lv.goal(320, 1650)
    lv.can(338, 556).can(82, 1597)
    lv.star(82, 957).star(338, 1356).star(80, 1900)
    L.append(lv)

    lv = tight(Level("Crossroads", w=840, h=1400, base="cave", jag=4,
                     hint="Every branch costs fuel. Plan the route before you go."), R)
    lv.carve_rect(20, 20, 240, 200)
    lv.tunnel([(130, 150), (130, 700)], 100)
    lv.tunnel([(130, 700), (700, 700)], 100)
    lv.tunnel([(420, 700), (420, 1200)], 100)
    lv.tunnel([(700, 700), (700, 270)], 100)
    lv.tunnel([(130, 700), (130, 1130)], 100)
    lv.tunnel([(700, 700), (770, 990)], 90)
    lv.carve_rect(280, 1150, 400, 200)
    lv.start(130, 20)
    lv.goal(600, 1150)
    lv.can(130, 1120)
    lv.star(700, 290).star(770, 975).star(330, 1300)
    L.append(lv)

    lv = tight(Level("Ore Cart", w=1260, h=700, base="cave", jag=4,
                     hint="A long winding tunnel. Keep moving and don't hover."), R)
    lv.carve_rect(20, 20, 200, 220)
    lv.tunnel([(110, 150), (300, 360), (500, 200), (700, 450), (900, 250), (1100, 420), (1180, 200)], 110)
    lv.carve_rect(1040, 20, 200, 200)
    lv.mine(700, 485, r=12)
    lv.mine(500, 165, r=12)
    lv.start(110, 20)
    lv.goal(1120, 20)
    lv.can(600, 330)
    lv.star(300, 360).star(900, 250).star(1100, 420)
    L.append(lv)

    lv = tight(Level("Hollow Rocks", w=840, h=1300, jag=5,
                     hint="A field of loose rocks. Weave through without wasting a drop."), R)
    for i, (x, y, r) in enumerate([(200, 300, 55), (420, 250, 50), (640, 330, 60), (130, 560, 50),
                                   (360, 520, 60), (600, 600, 55), (250, 820, 60), (500, 860, 50),
                                   (720, 860, 45), (150, 1080, 45), (420, 1100, 55)]):
        lv.rock(x, y, r)
    lv.rect(620, 1050, 200, 30, jag=0)
    lv.start(80, 20)
    lv.goal(720, 1080)
    lv.can(470, 420)
    lv.star(280, 430).star(750, 470).star(330, 1000)
    L.append(lv)

    lv = tight(Level("Spike Vein", h=1900, base="cave", jag=3,
                     hint="Spikes guard every bend of the vein."), R)
    lv.carve_rect(20, 20, 380, 180)
    lv.tunnel([(210, 150), (110, 450), (310, 800), (110, 1150), (300, 1450), (210, 1640)], 110)
    lv.carve_rect(50, 1600, 320, 260)
    lv.rect(36, 420, 18, 80, jag=0)
    lv.spikes(54, 420, 80, "right")
    lv.rect(366, 770, 18, 80, jag=0)
    lv.spikes(366, 770, 80, "left")
    lv.rect(36, 1120, 18, 80, jag=0)
    lv.spikes(54, 1120, 80, "right")
    lv.rect(352, 1420, 18, 80, jag=0)
    lv.spikes(352, 1420, 80, "left")
    lv.start(210, 20)
    lv.goal(310, 1600)
    lv.can(210, 975)
    lv.star(110, 450).star(310, 800).star(90, 1800)
    L.append(lv)

    lv = tight(Level("Drop Shaft", h=2400, base="cave", jag=4,
                     hint="A long fall through the rock. Brake early, brake often."), R)
    lv.carve_rect(20, 2180, 380, 200)
    lv.tunnel([(300, 2250), (300, 1900), (130, 1600), (290, 1250), (130, 900), (280, 550), (200, 350)], 118)
    lv.carve_rect(20, 20, 380, 360)
    lv.mine(210, 1425, r=12)
    lv.mine(205, 725, r=12)
    lv.start(100, 2180)
    lv.goal(110, 20)
    lv.star(300, 1900).star(130, 1600).star(340, 120)
    L.append(lv)

    lv = tight(Level("Twin Shafts", w=840, h=1800, base="cave", jag=4,
                     hint="Two shafts, blocked in turns. Cross over to keep climbing."), R)
    lv.carve_rect(20, 20, 800, 200)
    lv.tunnel([(230, 150), (230, 1550)], 120, round_ends=False)
    lv.tunnel([(610, 150), (610, 1550)], 120, round_ends=False)
    for y, (a, b) in zip((450, 850, 1250), (((230, 450), (610, 450)), ((230, 850), (610, 850)),
                                           ((230, 1250), (610, 1250)))):
        lv.tunnel([a, b], 100)
    lv.rect(150, 600, 160, 60, jag=0)
    lv.rect(530, 1000, 160, 60, jag=0)
    lv.rect(150, 1400, 160, 60, jag=0)
    lv.carve_rect(120, 1500, 600, 270)
    lv.start(230, 20)
    lv.goal(420, 1500)
    lv.can(610, 700)
    lv.star(230, 1000).star(610, 1350).star(160, 1700)
    L.append(lv)

    lv = tight(Level("Cups", w=840, h=1300, jag=0,
                     hint="Each star sits in a cup. Drop in gently, climb out carefully."), R)

    def cup(x, y, w=90, h=80):
        lv.rect(x, y, w, 14)
        lv.rect(x, y, 14, h)
        lv.rect(x + w - 14, y, 14, h)
    cup(130, 380)
    cup(560, 520)
    cup(300, 800)
    lv.rect(600, 1000, 220, 30)
    lv.rock(420, 420, 45, jag=4)
    lv.rock(250, 1080, 50, jag=4)
    lv.start(80, 20)
    lv.goal(720, 1030)
    lv.can(700, 250)
    lv.star(175, 420).star(605, 560).star(345, 840)
    L.append(lv)

    lv = tight(maze("Deep Seam", "A tangle of old mine tunnels. Find the exit before your tank runs dry.",
                    5, 6, 168, seed=515, width=104, cans=2, jag=4), R)
    L.append(lv)

    lv = tight(Level("Emerald Heart", w=840, h=2200, base="cave", jag=4,
                     hint="The heart of the mines: long tunnels, sharp spikes, little fuel."), R)
    lv.carve_rect(20, 20, 280, 200)
    lv.tunnel([(160, 150), (160, 600), (680, 700), (680, 1150), (200, 1300), (200, 1750), (560, 1900)], 112)
    lv.tunnel([(420, 650), (420, 420)], 90)
    lv.tunnel([(680, 1150), (790, 1350)], 90)
    lv.tunnel([(200, 1500), (60, 1560)], 84)
    lv.carve_rect(440, 1820, 380, 330)
    lv.rect(500, 600, 90, 30, jag=0)
    lv.spikes(500, 630, 90, "up")
    lv.mine(200, 1420, r=12, path=[(200, 1660)], speed=80)
    lv.start(160, 20)
    lv.goal(740, 1820)
    lv.can(420, 440).can(72, 1557)
    lv.star(780, 1335).star(680, 930).star(480, 2080)
    L.append(lv)
    return L


# ---------------------------------------------------------------- world 6
def acid_falls():
    L = []
    R = 0.82

    lv = tight(Level("Acid Rain", w=840, h=900, jag=6,
                     hint="Downpours push you to the ground. Cross between the columns."), R)
    lv.wind(200, 20, 120, 860, 0, -150)
    lv.wind(400, 20, 120, 860, 0, -170)
    lv.wind(600, 20, 100, 860, 0, -150)
    lv.rect(720, 20, 100, 260, jag=0)
    lv.spikes(200, 20, 120, "up")
    lv.spikes(400, 20, 120, "up")
    lv.start(90, 20)
    lv.goal(770, 280, 56)
    lv.star(360, 520).star(560, 640).star(760, 600)
    L.append(lv)

    lv = tight(Level("Geyser", h=2000, base="cave", jag=5,
                     hint="A geyser blasts you upward. Ride it, then slip past the mines."), R)
    lv.carve_rect(20, 20, 380, 220)
    lv.tunnel([(210, 150), (210, 1550)], 160, round_ends=False)
    lv.wind(130, 300, 160, 800, 0, 230)
    lv.mine(140, 1250, r=13, path=[(280, 1250)], speed=110)
    lv.mine(280, 1420, r=13, path=[(140, 1420)], speed=130)
    lv.carve_rect(40, 1520, 340, 300)
    lv.start(210, 20)
    lv.goal(330, 1520)
    lv.star(210, 900).star(270, 1330).star(80, 1760)
    L.append(lv)

    lv = tight(Level("Side Winds", h=1800, jag=5,
                     hint="Gusts shove you toward the mines. Lean hard into the wind."), R)
    for i, y in enumerate((300, 650, 1000, 1350)):
        d = -1 if i % 2 == 0 else 1
        lv.wind(20, y, 380, 150, 200 * d, 0)
        wall = 40 if d < 0 else 380
        for k in range(3):
            lv.mine(wall, y + 25 + k * 50, r=12)
    lv.rect(220, 1560, 180, 30, jag=0)
    lv.start(210, 20)
    lv.goal(310, 1590)
    lv.star(300, 380).star(120, 730).star(290, 1080)
    L.append(lv)

    lv = tight(Level("Spillway", w=1260, h=700, base="cave", jag=5,
                     hint="The current carries you forward. Watch for mines bobbing in the flow."), R)
    lv.carve_rect(20, 20, 220, 240)
    lv.tunnel([(120, 200), (300, 380), (1000, 380), (1150, 200)], 150)
    lv.carve_rect(1030, 20, 210, 220)
    lv.wind(300, 305, 700, 150, 130, 0)
    lv.mine(480, 320, r=12, path=[(480, 440)], speed=90)
    lv.mine(680, 440, r=12, path=[(680, 320)], speed=110)
    lv.mine(880, 320, r=12, path=[(880, 440)], speed=130)
    lv.start(120, 20)
    lv.goal(1150, 20)
    lv.star(580, 380).star(780, 380).star(980, 380)
    L.append(lv)

    lv = tight(Level("Floodgate", h=1700,
                     hint="Gates open on a timer while updrafts lift you. Time both."), R)
    lv.rect(20, 450, 150, 40).rect(250, 450, 150, 40)
    lv.laser(166, 470, 254, 470, on=1.2, off=1.6)
    lv.wind(20, 500, 380, 300, 0, 180)
    lv.rect(20, 900, 220, 40).rect(320, 900, 80, 40)
    lv.laser(236, 920, 324, 920, on=1.2, off=1.6, phase=0.8)
    lv.wind(20, 950, 380, 300, 0, 180)
    lv.rect(20, 1350, 80, 40).rect(180, 1350, 220, 40)
    lv.laser(96, 1370, 184, 1370, on=1.2, off=1.6, phase=1.6)
    lv.rect(250, 1550, 150, 30)
    lv.start(210, 20)
    lv.goal(325, 1580)
    lv.star(330, 650).star(80, 1100).star(140, 1500)
    L.append(lv)

    lv = tight(Level("Mine Cart", w=840, h=1200,
                     hint="Mines race along the corridors. Wait for your gap."), R)
    lv.rect(20, 300, 640, 30)
    lv.rect(180, 600, 640, 30)
    lv.rect(20, 900, 640, 30)
    lv.mine(60, 160, r=13, path=[(780, 160)], speed=170)
    lv.mine(780, 460, r=13, path=[(60, 460)], speed=190)
    lv.mine(60, 760, r=13, path=[(780, 760)], speed=210)
    lv.mine(780, 1060, r=13, path=[(400, 1060)], speed=120)
    lv.start(100, 20)
    lv.goal(150, 930)
    lv.star(740, 380).star(100, 680).star(740, 980)
    L.append(lv)

    lv = tight(Level("Vortex", w=840, h=1300, jag=6,
                     hint="Mines circle the rocks while the wind spins you around."), R)
    lv.rock(250, 450, 45)
    lv.orbit_mine(250, 450, 110, speed=1.2)
    lv.rock(590, 800, 45)
    lv.orbit_mine(590, 800, 115, speed=-1.1)
    lv.orbit_mine(590, 800, 115, speed=-1.1, phase=3.14159)
    lv.wind(20, 600, 800, 120, -150, 0)
    lv.rect(20, 1050, 220, 30, jag=0)
    lv.start(700, 20)
    lv.goal(130, 1080)
    lv.star(250, 620).star(750, 800).star(420, 1150)
    L.append(lv)

    lv = tight(Level("Undertow", h=2000, base="cave", jag=5,
                     hint="A downdraft drags you into the deep. Fight it all the way."), R)
    lv.carve_rect(20, 1780, 380, 200)
    lv.tunnel([(300, 1850), (300, 300)], 140, round_ends=False)
    lv.tunnel([(300, 1300), (90, 1360)], 90)
    lv.tunnel([(300, 800), (90, 860)], 90)
    lv.carve_rect(20, 20, 380, 330)
    lv.wind(230, 400, 140, 1300, 0, -140)
    lv.start(110, 1780)
    lv.goal(110, 20)
    lv.can(100, 1357)
    lv.star(100, 857).star(300, 1000).star(350, 120)
    L.append(lv)

    lv = tight(Level("Rapids", w=1260, h=900, jag=6,
                     hint="Wild currents in every direction. Read the streams."), R)
    lv.wind(180, 20, 160, 860, 0, 190)
    lv.wind(340, 600, 320, 160, 160, 0)
    lv.wind(660, 20, 160, 860, 0, -150)
    lv.wind(820, 200, 260, 160, -170, 0)
    lv.spikes(660, 20, 160, "up")
    lv.spikes(180, 880, 160, "down")
    lv.mine(500, 300, r=13)
    lv.mine(980, 600, r=13)
    lv.start(90, 20)
    lv.goal(1160, 20)
    lv.star(260, 500).star(740, 600).star(950, 280)
    L.append(lv)

    lv = tight(Level("Acid Peak", h=2800, base="cave", jag=5,
                     hint="The final climb out of the falls. Every gust and mine at once."), R)
    lv.carve_rect(20, 20, 380, 220)
    lv.tunnel([(210, 150), (210, 700)], 150, round_ends=False)
    lv.wind(135, 300, 150, 350, 0, 200)
    lv.carve_circle(210, 860, 170)
    lv.orbit_mine(210, 860, 95, speed=1.3)
    lv.tunnel([(210, 1010), (110, 1400)], 130)
    lv.wind(45, 1050, 140, 350, -140, 0)
    lv.tunnel([(110, 1400), (300, 1800)], 130)
    lv.mine(180, 1650, r=12, path=[(280, 1650)], speed=120)
    lv.tunnel([(300, 1800), (210, 2350)], 140)
    lv.wind(140, 1900, 140, 400, 0, -120)
    lv.carve_rect(40, 2330, 340, 300)
    lv.start(210, 20)
    lv.goal(320, 2330)
    lv.can(210, 860)
    lv.star(110, 1400).star(300, 1800).star(90, 2580)
    L.append(lv)
    return L


# ---------------------------------------------------------------- world 7
def nebula_gardens():
    L = []
    R = 0.86

    lv = tight(Level("Petal Spin", h=1500,
                     hint="Three spinning petals. Each one turns at its own pace."), R)
    for y, sp in ((420, 1.2), (800, -1.5), (1180, 1.8)):
        lv.rect(20, y - 120, 50, 240).rect(350, y - 120, 50, 240)
        lv.spinner(210, y, 105, arms=2, speed=sp)
    lv.rect(20, 1350, 150, 30)
    lv.start(210, 20)
    lv.goal(95, 1380)
    lv.star(210, 610).star(210, 990).star(320, 1400)
    L.append(lv)

    lv = tight(Level("Laser Lattice", h=1800,
                     hint="A lattice of beams, each on its own beat. Patience saves fuel."), R)
    for i, y in enumerate((320, 560, 800, 1040, 1280)):
        lv.laser(20, y, 400, y, on=1.0, off=1.8, phase=(i * 0.55) % 2.8)
        lv.rect(20 if i % 2 == 0 else 320, y + 40, 80, 20)
    lv.rect(250, 1500, 150, 30)
    lv.start(210, 20)
    lv.goal(325, 1530)
    lv.star(60, 440).star(360, 920).star(60, 1400)
    L.append(lv)

    lv = tight(Level("Garden Gate", w=840, h=1200,
                     hint="The key hides behind the blades. The gate won't open without it."), R)
    lv.rect(400, 20, 40, 700)
    lv.spinner(220, 450, 100, arms=2, speed=1.4)
    lv.spinner(620, 450, 100, arms=2, speed=-1.4)
    lv.key(620, 250, color=1)
    lv.rect(560, 160, 140, 24)
    lv.rect(560, 820, 260, 30)
    lv.rect(560, 980, 30, 200)
    lv.door(560, 850, 30, 130, color=1)
    lv.goal(700, 850)
    lv.start(120, 20)
    lv.star(220, 650).star(760, 600).star(300, 1050)
    L.append(lv)

    lv = tight(Level("Pollen", w=840, h=1300,
                     hint="Pollen mines drift in slow circles. Float between them."), R)
    for (x, y, rr, sp) in ((200, 380, 100, 0.9), (620, 420, 110, -0.8), (420, 760, 120, 1.0), (180, 1050, 90, -1.1)):
        lv.rect(x - 15, y - 15, 30, 30)
        lv.orbit_mine(x, y, rr, speed=sp)
    lv.wind(320, 300, 200, 300, 0, 150)
    lv.rect(600, 1000, 220, 30)
    lv.start(420, 20)
    lv.goal(710, 1030)
    lv.star(420, 470).star(620, 650).star(420, 1150)
    L.append(lv)

    lv = tight(Level("Three Doors", h=2000,
                     hint="Three doors stacked high. Fetch each key from its side room."), R)
    for i, (y, color) in enumerate(((500, 0), (1000, 1), (1500, 2))):
        if i % 2 == 0:
            lv.rect(20, y, 260, 30)
            lv.door(280, y, 120, 30, color=color)
            lv.key(80, y - 200, color=color)
            lv.rect(20, y - 260, 120, 20)
        else:
            lv.rect(140, y, 260, 30)
            lv.door(20, y, 120, 30, color=color)
            lv.key(340, y - 200, color=color)
            lv.rect(280, y - 260, 120, 20)
    lv.laser(20, 760, 400, 760, on=1.2, off=1.6)
    lv.spinner(210, 1250, 80, arms=2, speed=1.3)
    lv.start(210, 20)
    lv.goal(150, 1530)
    lv.star(340, 380).star(80, 880).star(330, 1850)
    L.append(lv)

    lv = tight(Level("Blade Corridor", w=1260, h=640,
                     hint="A corridor of blades. Keep a steady pace and a low altitude."), R)
    lv.rect(20, 440, 1220, 180)
    for i, x in enumerate(range(240, 1101, 215)):
        lv.spinner(x, 230, 105, arms=2, speed=1.2 if i % 2 == 0 else -1.2, phase=i * 0.6)
    lv.start(90, 20)
    lv.goal(1180, 20, 56)
    lv.star(345, 70).star(775, 390).star(990, 70)
    L.append(lv)

    lv = tight(Level("Prism", w=840, h=1400,
                     hint="Beams cross in every direction. Find the dark lanes."), R)
    lv.laser(280, 20, 280, 1380, on=1.0, off=1.6)
    lv.laser(560, 20, 560, 1380, on=1.0, off=1.6, phase=1.3)
    lv.laser(20, 480, 820, 480, on=1.0, off=1.8, phase=0.6)
    lv.laser(20, 900, 820, 900, on=1.0, off=1.8, phase=1.9)
    lv.rect(620, 1150, 200, 30)
    lv.start(140, 20)
    lv.goal(720, 1180)
    lv.star(420, 300).star(140, 700).star(700, 1000)
    L.append(lv)

    lv = tight(maze("Thorn Maze", "A garden maze with spinning thorns. Every turn counts.",
                    5, 7, 180, seed=777, width=112, spinners=2, cans=1, jag=0), R)
    L.append(lv)

    lv = tight(Level("Bloom", w=840, h=1400, base="cave", jag=0,
                     hint="A great flower of blades. Reach the pad at its heart."), R)
    lv.carve_rect(20, 20, 800, 200)
    lv.carve_circle(420, 760, 330)
    lv.tunnel([(130, 150), (230, 520)], 120)
    lv.rect(360, 640, 120, 30)
    for (x, y, sp) in ((250, 760, 1.2), (590, 760, -1.2), (420, 980, 1.5), (420, 520, -1.5)):
        lv.spinner(x, y, 85, arms=2, speed=sp)
    lv.start(130, 20)
    lv.goal(420, 670, 56)
    lv.star(160, 900).star(680, 900).star(420, 1060)
    L.append(lv)

    lv = tight(Level("Nebula Core", w=840, h=2400,
                     hint="The core of the nebula. Blades, beams and locks stand between you and the pad."), R)
    lv.rect(20, 450, 600, 30)
    lv.spinner(420, 260, 95, arms=2, speed=1.4)
    lv.laser(620, 465, 820, 465, on=1.2, off=1.4)
    lv.rect(220, 900, 600, 30)
    lv.mine(260, 690, r=13, path=[(740, 690)], speed=150)
    lv.key(80, 700, color=2)
    lv.rect(20, 1350, 600, 30)
    lv.door(620, 1350, 200, 30, color=2)
    lv.spinner(420, 1140, 110, arms=2, speed=-1.4)
    lv.laser(20, 1650, 820, 1650, on=1.0, off=1.8)
    lv.orbit_mine(420, 1900, 140, speed=1.2)
    lv.rect(20, 2100, 240, 30)
    lv.can(720, 1120)
    lv.start(100, 20)
    lv.goal(140, 2130)
    lv.star(420, 120).star(100, 1150).star(720, 2250)
    L.append(lv)
    return L


# ---------------------------------------------------------------- world 8
def event_horizon():
    L = []
    R = 0.9

    lv = tight(Level("Gravity Well", h=2600, base="cave", jag=4,
                     hint="Falling into the well. Orbiting mines guard the way down."), R)
    lv.carve_rect(20, 2380, 380, 200)
    lv.tunnel([(300, 2430), (300, 2150)], 130)
    lv.carve_circle(220, 1950, 190)
    lv.orbit_mine(220, 1950, 110, speed=1.2)
    lv.tunnel([(160, 1780), (160, 1250)], 130)
    lv.carve_circle(230, 1060, 180)
    lv.orbit_mine(230, 1060, 105, speed=-1.3)
    lv.orbit_mine(230, 1060, 105, speed=-1.3, phase=3.14159)
    lv.tunnel([(280, 900), (220, 420)], 130)
    lv.carve_rect(20, 20, 380, 420)
    lv.start(100, 2380)
    lv.goal(320, 20)
    lv.star(380, 1950).star(80, 1060).star(60, 120)
    L.append(lv)

    lv = tight(Level("Singularity", w=840, h=1400,
                     hint="Blades orbit a dead star. Thread the ring to reach the far side."), R)
    lv.rect(380, 640, 80, 80)
    for k in range(6):
        a = k * math.pi / 3
        lv.spinner(420 + math.cos(a) * 230, 680 + math.sin(a) * 230, 70, arms=2,
                   speed=1.3 if k % 2 == 0 else -1.3, phase=k * 0.5)
    lv.rect(620, 1180, 200, 30)
    lv.start(120, 20)
    lv.goal(720, 1210)
    lv.star(420, 780).star(80, 680).star(770, 680)
    L.append(lv)

    lv = tight(Level("Accretion", w=840, h=1400, base="cave", jag=4,
                     hint="Matter spirals inward on the wind. Follow it to the centre."), R)
    lv.carve_rect(20, 20, 200, 180)
    lv.tunnel([(120, 110), (720, 110)], 120)
    lv.tunnel([(720, 110), (720, 1280)], 120)
    lv.tunnel([(720, 1280), (120, 1280)], 120)
    lv.tunnel([(120, 1280), (120, 450)], 120)
    lv.tunnel([(120, 450), (520, 450)], 110)
    lv.tunnel([(520, 450), (520, 950)], 110)
    lv.carve_rect(250, 900, 330, 160)
    lv.wind(240, 55, 400, 110, 140, 0)
    lv.wind(665, 300, 110, 800, 0, 140)
    lv.wind(240, 1225, 400, 110, -140, 0)
    lv.wind(65, 550, 110, 600, 0, -110)
    lv.mine(400, 420, r=11)
    lv.start(120, 20)
    lv.goal(330, 900)
    lv.star(720, 700).star(120, 800).star(520, 700)
    L.append(lv)

    lv = tight(Level("Redshift", w=1680, h=800,
                     hint="A long sprint to the edge of everything. Don't slow down."), R)
    lv.spikes(160, 20, 240, "up")
    lv.laser(300, 20, 300, 780, on=1.1, off=1.7)
    lv.spinner(560, 400, 120, arms=2, speed=1.2)
    lv.wind(760, 20, 220, 760, 0, 190)
    lv.spikes(760, 780, 220, "down")
    lv.mine(1120, 100, path=[(1120, 700)], speed=180)
    lv.mine(1260, 700, path=[(1260, 100)], speed=180)
    lv.orbit_mine(1450, 400, 120, speed=1.4)
    lv.start(80, 20)
    lv.goal(1600, 20, 56)
    lv.star(420, 680).star(870, 220).star(1450, 400)
    L.append(lv)

    lv = tight(maze("Dark Matter", "Invisible walls of dark matter. Mines drift through the tunnels.",
                    6, 6, 175, seed=4040, width=106, mines=3, spinners=1, cans=2, jag=4), R)
    L.append(lv)

    lv = tight(Level("Pulsar", h=2300,
                     hint="Beams pulse up the shaft like a heartbeat. Climb between the beats."), R)
    for i, y in enumerate(range(300, 1901, 200)):
        lv.laser(20, y, 400, y, on=0.8, off=1.6, phase=(i * 0.4) % 2.4)
        if i % 3 == 1:
            lv.rect(20 if i % 2 else 300, y + 60, 100, 20)
    lv.rect(250, 2100, 150, 30)
    lv.start(210, 20)
    lv.goal(325, 2130)
    lv.star(80, 800).star(350, 1400).star(80, 2000)
    L.append(lv)

    lv = tight(Level("Wormhole", w=840, h=1600, base="cave", jag=5,
                     hint="Tunnels with roaring winds fling you across space. Hold on."), R)
    lv.carve_rect(20, 20, 260, 200)
    lv.tunnel([(150, 150), (150, 650)], 130)
    lv.wind(85, 250, 130, 380, 0, 210)
    lv.tunnel([(150, 650), (700, 750)], 130)
    lv.wind(220, 640, 420, 120, 170, 0)
    lv.tunnel([(700, 750), (700, 1250)], 130)
    lv.tunnel([(700, 1250), (250, 1350)], 130)
    lv.wind(280, 1260, 380, 120, -160, 0)
    lv.carve_rect(60, 1300, 330, 260)
    lv.mine(420, 705, r=12)
    lv.mine(470, 1300, r=12)
    lv.start(150, 20)
    lv.goal(120, 1300, 56)
    lv.star(150, 450).star(700, 1000).star(110, 1500)
    L.append(lv)

    lv = tight(Level("Quasar", w=1260, h=1260,
                     hint="A blazing quasar of hazards. Find your own path through."), R)
    lv.rock(320, 360, 60, jag=5)
    lv.rock(900, 380, 70, jag=5)
    lv.rock(620, 720, 65, jag=5)
    lv.orbit_mine(620, 720, 150, speed=1.0)
    lv.spinner(320, 820, 100, arms=2, speed=1.3)
    lv.spinner(950, 860, 100, arms=2, speed=-1.3)
    lv.laser(20, 560, 1240, 560, on=1.0, off=2.0)
    lv.wind(450, 250, 330, 200, 0, 150)
    lv.rect(1000, 1060, 240, 30, jag=0)
    lv.can(620, 300)
    lv.start(100, 20)
    lv.goal(1120, 1090)
    lv.star(120, 640).star(1180, 600).star(620, 1100)
    L.append(lv)

    lv = tight(Level("Supernova", w=840, h=2400,
                     hint="Everything explodes at once. Stay calm, stay low on throttle."), R)
    lv.rect(20, 500, 600, 30)
    lv.door(620, 500, 200, 30, color=0)
    lv.key(720, 300, color=0)
    lv.spinner(400, 260, 100, arms=2, speed=1.5)
    lv.rect(220, 1000, 600, 30)
    lv.laser(20, 1015, 220, 1015, on=1.0, off=1.6)
    lv.wind(20, 600, 800, 200, 150, 0)
    lv.mine(260, 850, r=13, path=[(760, 850)], speed=170)
    lv.rect(20, 1500, 600, 30)
    lv.door(620, 1500, 200, 30, color=1)
    lv.key(100, 1350, color=1)
    lv.orbit_mine(420, 1250, 120, speed=1.3)
    lv.spinner(420, 1850, 120, arms=2, speed=-1.3)
    lv.rect(600, 2150, 220, 30)
    lv.can(80, 800)
    lv.start(100, 20)
    lv.goal(710, 2180)
    lv.star(420, 100).star(760, 1250).star(100, 2250)
    L.append(lv)

    lv = tight(Level("Event Horizon", h=3600, base="cave", jag=5,
                     hint="The last climb in the universe. No fuel to spare."), R)
    lv.carve_rect(20, 20, 380, 220)
    lv.tunnel([(210, 150), (210, 700)], 150, round_ends=False)
    lv.gate(380, 210, on=1.0, off=1.6)
    lv.gate(540, 210, on=1.0, off=1.6, phase=1.3)
    lv.carve_circle(210, 820, 170)
    lv.spinner(210, 820, 100, arms=2, speed=1.4)
    lv.tunnel([(210, 970), (110, 1350)], 130)
    lv.tunnel([(110, 1350), (130, 1900)], 130)
    lv.wind(50, 1400, 130, 380, 0, 190)
    lv.carve_circle(230, 2000, 165)
    lv.orbit_mine(230, 2000, 100, speed=1.4)
    lv.orbit_mine(230, 2000, 100, speed=1.4, phase=3.14159)
    lv.tunnel([(230, 2150), (320, 2550)], 125)
    lv.tunnel([(320, 2550), (90, 2660)], 110)
    lv.key(85, 2665, color=2)
    lv.tunnel([(320, 2550), (250, 3150)], 125)
    lv.door_across(2850, 285, color=2)
    lv.mine(255, 3050, r=12, path=[(275, 2950)], speed=60)
    lv.carve_rect(40, 3150, 340, 300)
    lv.can(285, 2380)
    lv.start(210, 20)
    lv.goal(110, 3150)
    lv.star(210, 600).star(370, 2000).star(330, 3360)
    L.append(lv)
    return L


RUSSIAN2 = {
    "Mineshaft": ("Шахта", "Отсюда топлива в обрез. Заглядывай в боковые карманы за канистрами."),
    "Crossroads": ("Перекрёсток", "Каждое ответвление стоит топлива. Продумай маршрут заранее."),
    "Ore Cart": ("Вагонетка", "Длинный извилистый туннель. Не зависай — двигайся вперёд."),
    "Hollow Rocks": ("Пустые камни", "Поле парящих камней. Петляй между ними, не тратя ни капли."),
    "Spike Vein": ("Шипастая жила", "Шипы охраняют каждый изгиб жилы."),
    "Drop Shaft": ("Ствол вниз", "Долгое падение сквозь скалу. Тормози рано и часто."),
    "Twin Shafts": ("Две шахты", "Две шахты, перекрытые по очереди. Переходи из одной в другую."),
    "Cups": ("Чаши", "Каждая звезда лежит в чаше. Опустись мягко, выберись осторожно."),
    "Deep Seam": ("Глубокий пласт", "Клубок старых штолен. Найди выход, пока бак не опустел."),
    "Emerald Heart": ("Изумрудное сердце", "Сердце копей: длинные туннели, острые шипы и мало топлива."),
    "Acid Rain": ("Кислотный дождь", "Ливни прижимают к земле. Пролетай между потоками."),
    "Geyser": ("Гейзер", "Гейзер подбрасывает вверх. Оседлай его и проскользни мимо мин."),
    "Side Winds": ("Боковые порывы", "Порывы толкают на мины. Сильнее наклоняйся навстречу ветру."),
    "Spillway": ("Водосброс", "Течение несёт вперёд. Следи за минами, качающимися в потоке."),
    "Floodgate": ("Шлюз", "Ворота открываются по таймеру, а восходящий поток поднимает тебя. Рассчитай и то и другое."),
    "Mine Cart": ("Минная вагонетка", "Мины мчатся по коридорам. Дождись своего окна."),
    "Vortex": ("Вихрь", "Мины кружат вокруг камней, а ветер крутит тебя."),
    "Undertow": ("Подводное течение", "Нисходящий поток тянет в глубину. Борись с ним всю дорогу."),
    "Rapids": ("Пороги", "Бурные потоки во все стороны. Читай течения."),
    "Acid Peak": ("Кислотная вершина", "Последний подъём из водопадов. Все порывы и мины сразу."),
    "Petal Spin": ("Кружение лепестков", "Три вращающихся лепестка. У каждого свой темп."),
    "Laser Lattice": ("Лазерная решётка", "Решётка лучей, у каждого свой ритм. Терпение экономит топливо."),
    "Garden Gate": ("Садовые ворота", "Ключ спрятан за лезвиями. Без него ворота не откроются."),
    "Pollen": ("Пыльца", "Мины-пыльца медленно кружат. Проплывай между ними."),
    "Three Doors": ("Три двери", "Три двери одна над другой. Принеси каждый ключ из боковой комнаты."),
    "Blade Corridor": ("Коридор лезвий", "Коридор из лезвий. Держи ровный темп и малую высоту."),
    "Prism": ("Призма", "Лучи пересекаются во всех направлениях. Найди тёмные коридоры."),
    "Thorn Maze": ("Терновый лабиринт", "Садовый лабиринт с вращающимися шипами. Важен каждый поворот."),
    "Bloom": ("Цветение", "Огромный цветок из лезвий. Доберись до площадки в его сердце."),
    "Nebula Core": ("Ядро туманности", "Ядро туманности. Между тобой и площадкой — лезвия, лучи и замки."),
    "Gravity Well": ("Гравитационный колодец", "Падение в колодец. Мины на орбитах охраняют путь вниз."),
    "Singularity": ("Сингулярность", "Лезвия кружат вокруг мёртвой звезды. Проскочи сквозь кольцо."),
    "Accretion": ("Аккреция", "Вещество закручивается внутрь вместе с ветром. Следуй к центру."),
    "Redshift": ("Красное смещение", "Долгий рывок к краю всего. Не сбавляй ход."),
    "Dark Matter": ("Тёмная материя", "Невидимые стены тёмной материи. По туннелям дрейфуют мины."),
    "Pulsar": ("Пульсар", "Лучи пульсируют в шахте, как сердце. Поднимайся между ударами."),
    "Wormhole": ("Червоточина", "Туннели с ревущим ветром швыряют тебя через пространство. Держись."),
    "Quasar": ("Квазар", "Пылающий квазар опасностей. Найди собственный путь."),
    "Supernova": ("Сверхновая", "Всё взрывается одновременно. Сохраняй спокойствие и не жми газ зря."),
    "Event Horizon": ("Горизонт событий", "Последний подъём во вселенной. Топлива ни капли лишнего."),
}
