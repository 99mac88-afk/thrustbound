"""
All Thrustbound levels. Run tools/build_levels.py to regenerate
Thrustbound/Resources/levels.json.

Coordinates: points, origin bottom-left, y up. Default level width is 420
which matches the visible width in game; the frame border is 20pt thick so
the playable interior of a 420-wide level is x = 20..400.
"""

import random

from leveldsl import Level
from levels2 import RUSSIAN2, WORLDS2, acid_falls, emerald_mines, event_horizon, nebula_gardens

WORLDS = [
    {"name": "Launch Bay", "subtitle": "Learn to fly",
     "nameRu": "Стартовый док", "subtitleRu": "Учимся летать",
     "neon": "#3BE3FF", "rock": "#0E2233", "bgTop": "#03070F", "bgBottom": "#0A1C30"},
    {"name": "Crystal Caverns", "subtitle": "Spikes and wild winds",
     "nameRu": "Хрустальные пещеры", "subtitleRu": "Шипы и буйные ветра",
     "neon": "#B47CFF", "rock": "#1C1030", "bgTop": "#06030D", "bgBottom": "#1A0B2C"},
    {"name": "Reactor Core", "subtitle": "Lasers, blades and locks",
     "nameRu": "Ядро реактора", "subtitleRu": "Лазеры, лезвия и замки",
     "neon": "#FF9A3D", "rock": "#2A1608", "bgTop": "#0C0502", "bgBottom": "#2A1206"},
    {"name": "Deep Void", "subtitle": "Only the best pilots return",
     "nameRu": "Глубокая пустота", "subtitleRu": "Возвращаются только лучшие пилоты",
     "neon": "#4D7CFF", "rock": "#0C1430", "bgTop": "#02030A", "bgBottom": "#0A1238"},
]


# ---------------------------------------------------------------- world 1
def launch_bay():
    L = []

    lv = Level("First Flight", h=800,
               hint="Hold GAS to fire the engine. Point the stick to steer. "
                    "Touch down gently on the green pad.")
    lv.start(100, 20)
    lv.rect(250, 20, 150, 200)
    lv.goal(325, 220)
    lv.star(100, 170).star(190, 300).star(325, 360)
    lv.fuel = 30
    L.append(lv)

    lv = Level("Up and Over", h=1000,
               hint="Fly over the wall. Ease off the gas early so you don't drop too fast.")
    lv.start(90, 20)
    lv.rect(185, 20, 50, 520)
    lv.goal(320, 20)
    lv.star(90, 320).star(210, 660).star(320, 250)
    lv.fuel_margin = 3.0
    L.append(lv)

    lv = Level("Shelves", h=1250,
               hint="Climb through the gaps. Short taps of gas let you hover.")
    lv.start(210, 20)
    lv.rect(20, 280, 250, 26)
    lv.rect(150, 560, 250, 26)
    lv.rect(20, 840, 250, 26)
    lv.goal(115, 866)
    lv.star(335, 293).star(85, 573).star(335, 1010)
    lv.fuel_margin = 3.0
    L.append(lv)

    lv = Level("Going Down", h=1300,
               hint="Gravity does the work here. Feather the gas to slow your fall before landing.")
    lv.rect(20, 1080, 150, 40)
    lv.start(90, 1120)
    lv.rect(220, 760, 180, 40)
    lv.rect(20, 300, 270, 40)
    lv.goal(110, 20)
    lv.star(300, 950).star(110, 560).star(345, 170)
    lv.fuel_margin = 3.0
    L.append(lv)

    lv = Level("Zig Zag", h=1700,
               hint="Zig and zag your way up. Small tilts are all you need.")
    lv.start(100, 20)
    lv.poly([(20, 300), (300, 360), (300, 390), (20, 330)])
    lv.poly([(400, 600), (130, 660), (130, 690), (400, 630)])
    lv.poly([(20, 900), (290, 960), (290, 990), (20, 930)])
    lv.poly([(400, 1200), (130, 1260), (130, 1290), (400, 1230)])
    lv.rect(250, 1460, 150, 30)
    lv.goal(325, 1490)
    lv.star(200, 520).star(220, 1080).star(75, 1400)
    lv.fuel_margin = 2.6
    L.append(lv)

    lv = Level("Fuel Stop", h=2200, fuel=12,
               hint="Fuel is limited! Grab the orange fuel cans on the way up.")
    lv.start(210, 20)
    lv.rect(20, 500, 110, 24)
    lv.can(75, 570)
    lv.rock(300, 800, 60, jag=0)
    lv.rect(290, 1050, 110, 24)
    lv.can(345, 1120)
    lv.rock(130, 1300, 60, jag=0)
    lv.rect(20, 1560, 110, 24)
    lv.can(75, 1630)
    lv.rock(290, 1750, 55, jag=0)
    lv.rect(260, 2000, 140, 30)
    lv.goal(330, 2030)
    lv.star(330, 480).star(220, 1450).star(60, 1900)
    L.append(lv)

    lv = Level("The Chimney", h=1800, base="cave", jag=4,
               hint="A narrow chimney. Gentle corrections work best.")
    lv.carve_rect(20, 20, 380, 200)
    lv.tunnel([(210, 150), (150, 450), (270, 800), (150, 1150), (250, 1450), (210, 1600)], 120)
    lv.carve_rect(60, 1540, 300, 200)
    lv.start(210, 20)
    lv.goal(320, 1540)
    lv.star(150, 450).star(270, 800).star(150, 1150)
    lv.fuel_margin = 2.0
    L.append(lv)

    lv = Level("Side Step", w=1000, h=700,
               hint="Weave over and under the pillars. Tilt only a little to drift sideways.")
    lv.start(80, 20)
    lv.rect(220, 20, 60, 380)
    lv.rect(390, 300, 60, 380)
    lv.rect(560, 20, 60, 380)
    lv.rect(730, 300, 60, 380)
    lv.goal(905, 20)
    lv.star(250, 530).star(420, 160).star(760, 160)
    lv.fuel_margin = 2.0
    L.append(lv)

    lv = Level("Ledge Hopper", h=1300,
               hint="Line up above the pad, then drop straight down onto it.")
    lv.start(70, 20)
    lv.rect(150, 250, 120, 40)
    lv.rect(280, 520, 120, 40)
    lv.rect(20, 760, 140, 40)
    lv.rect(200, 980, 110, 40)
    lv.goal(255, 1020, 56)
    lv.star(340, 480).star(90, 720).star(255, 1170)
    lv.fuel_margin = 2.0
    L.append(lv)

    lv = Level("Graduation", w=840, h=1600, base="cave", jag=5,
               hint="Put it all together. Plan your route and save fuel.")
    lv.carve_rect(20, 20, 260, 220)
    lv.tunnel([(150, 200), (150, 600), (600, 650), (700, 1000), (250, 1150), (300, 1400)], 130)
    lv.carve_rect(180, 1330, 400, 230)
    lv.start(150, 20)
    lv.goal(470, 1330)
    lv.can(650, 820)
    lv.star(400, 630).star(745, 1000).star(260, 1480)
    lv.fuel_margin = 1.9
    L.append(lv)
    return L


# ---------------------------------------------------------------- world 2
def crystal_caverns():
    L = []

    lv = Level("Sharp Edges", h=900, jag=6,
               hint="Red means danger. Spikes destroy your rocket on contact.")
    lv.start(80, 20)
    lv.spikes(140, 20, 180, "up")
    lv.rect(320, 20, 80, 120, jag=0)
    lv.goal(360, 140, 60)
    lv.star(230, 130).star(80, 400).star(230, 620)
    lv.fuel_margin = 2.4
    L.append(lv)

    lv = Level("Stalactites", w=1000, h=800, jag=6,
               hint="Thread between the crystals. Keep your speed low.")
    lv.start(100, 20)
    lv.rect(240, 470, 200, 310, jag=0)
    lv.spikes(240, 470, 200, "down")
    lv.rect(300, 20, 100, 110, jag=0)
    lv.spikes(300, 130, 100, "up")
    lv.rect(600, 20, 120, 160, jag=0)
    lv.spikes(600, 180, 120, "up")
    lv.rect(700, 430, 160, 350, jag=0)
    lv.spikes(700, 430, 160, "down")
    lv.rock(530, 650, 45)
    lv.goal(910, 20)
    lv.star(350, 300).star(530, 230).star(800, 300)
    lv.fuel_margin = 2.2
    L.append(lv)

    lv = Level("Updraft", h=1800, base="cave", jag=4,
               hint="Blue streams are wind. Ride the updraft up the shaft.")
    lv.carve_rect(20, 20, 380, 220)
    lv.tunnel([(210, 150), (210, 1500)], 150, round_ends=False)
    lv.carve_rect(40, 1450, 340, 300)
    lv.wind(135, 300, 150, 900, 0, 210)
    lv.rect(122, 640, 20, 120, jag=0)
    lv.spikes(142, 640, 120, "right")
    lv.rect(278, 960, 20, 120, jag=0)
    lv.spikes(278, 960, 120, "left")
    lv.start(210, 20)
    lv.goal(330, 1450)
    lv.star(240, 700).star(180, 1020).star(90, 1650)
    lv.fuel_margin = 2.0
    L.append(lv)

    lv = Level("Crosswind", h=1500, jag=6,
               hint="Wind pushes you sideways. Lean into it!")
    lv.start(210, 20)
    lv.wind(20, 300, 380, 160, -220, 0)
    lv.spikes(20, 300, 160, "right")
    lv.wind(20, 700, 380, 160, 220, 0)
    lv.spikes(400, 700, 160, "left")
    lv.wind(20, 1050, 380, 160, -240, 0)
    lv.spikes(20, 1050, 160, "right")
    lv.rect(20, 1300, 160, 30, jag=0)
    lv.goal(100, 1330)
    lv.star(330, 380).star(90, 780).star(300, 1130)
    lv.fuel_margin = 2.0
    L.append(lv)

    lv = Level("Needle's Eye", h=1700,
               hint="Line up below each gap and rise straight through.")
    lv.start(210, 20)
    lv.rect(20, 350, 220, 40).rect(320, 350, 80, 40)
    lv.spikes(20, 390, 220, "up").spikes(320, 390, 80, "up")
    lv.spikes(20, 350, 220, "down").spikes(320, 350, 80, "down")
    lv.rect(20, 750, 90, 40).rect(180, 750, 220, 40)
    lv.spikes(20, 790, 90, "up").spikes(180, 790, 220, "up")
    lv.spikes(20, 750, 90, "down").spikes(180, 750, 220, "down")
    lv.rect(20, 1150, 155, 40).rect(245, 1150, 155, 40)
    lv.spikes(20, 1190, 155, "up").spikes(245, 1190, 155, "up")
    lv.spikes(20, 1150, 155, "down").spikes(245, 1150, 155, "down")
    lv.rect(250, 1450, 150, 30)
    lv.goal(325, 1480)
    lv.star(280, 250).star(145, 650).star(210, 1320)
    lv.fuel_margin = 2.0
    L.append(lv)

    lv = Level("Downpour", h=1700, base="cave", jag=5,
               hint="A downdraft! Keep thrusting to stay in control on the way down.")
    lv.carve_rect(20, 1450, 380, 230)
    lv.tunnel([(300, 1500), (300, 300)], 130, round_ends=False)
    lv.carve_rect(20, 20, 380, 300)
    lv.wind(235, 400, 130, 900, 0, -170)
    lv.rect(222, 900, 18, 100, jag=0)
    lv.spikes(240, 900, 100, "right")
    lv.rect(360, 640, 18, 100, jag=0)
    lv.spikes(360, 640, 100, "left")
    lv.start(110, 1450)
    lv.goal(110, 20)
    lv.star(300, 1150).star(285, 560).star(350, 110)
    lv.fuel_margin = 2.2
    L.append(lv)

    lv = Level("Crystal Maze", w=840, h=1200, base="cave", jag=3,
               hint="Find your way through the maze. Dead ends hide stars.")
    lv.carve_rect(20, 20, 240, 200)
    lv.tunnel([(140, 150), (140, 520)], 110)
    lv.tunnel([(140, 520), (700, 520)], 110)
    lv.tunnel([(420, 520), (420, 250)], 100)
    lv.tunnel([(700, 520), (700, 880)], 110)
    lv.tunnel([(700, 880), (300, 880)], 110)
    lv.tunnel([(700, 880), (770, 1080)], 100)
    lv.tunnel([(300, 880), (300, 1000)], 110)
    lv.carve_rect(80, 960, 360, 210)
    lv.rect(520, 455, 90, 12, jag=0)
    lv.spikes(520, 467, 90, "up")
    lv.rect(745, 650, 12, 90, jag=0)
    lv.spikes(745, 650, 90, "left")
    lv.rect(430, 930, 90, 12, jag=0)
    lv.spikes(430, 930, 90, "down")
    lv.start(140, 20)
    lv.goal(160, 960)
    lv.star(420, 270).star(770, 1070).star(560, 880)
    lv.fuel_margin = 2.0
    L.append(lv)

    lv = Level("Gust Alley", w=1100, h=800, jag=6,
               hint="Updrafts and downdrafts. Time your thrust to cross each gust.")
    lv.start(90, 20)
    lv.wind(200, 20, 160, 760, 0, 230)
    lv.spikes(200, 780, 160, "down")
    lv.wind(460, 20, 160, 760, 0, -150)
    lv.spikes(460, 20, 160, "up")
    lv.wind(720, 20, 160, 760, 0, 230)
    lv.spikes(720, 780, 160, "down")
    lv.goal(1000, 20)
    lv.star(280, 480).star(540, 420).star(800, 420)
    lv.fuel_margin = 2.0
    L.append(lv)

    lv = Level("Spiral", w=840, h=1400, base="cave", jag=5,
               hint="Spiral inward. It's a long trip, so watch your fuel.")
    lv.carve_rect(20, 20, 200, 180)
    lv.tunnel([(120, 110), (720, 110)], 120)
    lv.tunnel([(720, 110), (720, 1280)], 120)
    lv.tunnel([(720, 1280), (120, 1280)], 120)
    lv.tunnel([(120, 1280), (120, 450)], 120)
    lv.tunnel([(120, 450), (520, 450)], 110)
    lv.tunnel([(520, 450), (520, 950)], 110)
    lv.carve_rect(250, 900, 330, 160)
    lv.rect(400, 40, 80, 14, jag=0)
    lv.spikes(400, 54, 80, "up")
    lv.rect(770, 600, 14, 100, jag=0)
    lv.spikes(770, 600, 100, "left")
    lv.rect(380, 1326, 80, 14, jag=0)
    lv.spikes(380, 1326, 80, "down")
    lv.start(120, 20)
    lv.goal(330, 900)
    lv.can(300, 1280)
    lv.star(720, 700).star(120, 800).star(520, 700)
    lv.fuel_margin = 1.8
    L.append(lv)

    lv = Level("Cavern Heart", w=840, h=2000, base="cave", jag=6,
               hint="The heart of the caverns. Everything you've learned, all at once.")
    lv.carve_rect(20, 20, 300, 220)
    lv.tunnel([(170, 180), (250, 600)], 130)
    lv.carve_circle(420, 720, 230)
    lv.tunnel([(300, 900), (150, 1250)], 120)
    lv.tunnel([(150, 1250), (150, 1600)], 130)
    lv.tunnel([(150, 1600), (500, 1750)], 120)
    lv.carve_rect(420, 1650, 380, 300)
    lv.wind(250, 640, 340, 180, 190, 0)
    lv.rect(320, 480, 200, 30, jag=0)
    lv.spikes(320, 510, 200, "up")
    lv.wind(85, 1260, 130, 340, 0, 200)
    lv.start(110, 20)
    lv.goal(700, 1650)
    lv.can(600, 700)
    lv.star(420, 720).star(150, 1450).star(760, 1900)
    lv.fuel_margin = 1.8
    L.append(lv)
    return L


# ---------------------------------------------------------------- world 3
def reactor_core():
    L = []

    lv = Level("Laser Gate", h=1100,
               hint="Lasers switch on and off. Wait for the beam to drop, then go!")
    lv.start(210, 20)
    lv.rect(20, 450, 150, 40).rect(250, 450, 150, 40)
    lv.laser(166, 470, 254, 470, on=1.5, off=1.5)
    lv.rect(250, 850, 150, 30)
    lv.goal(325, 880)
    lv.star(210, 300).star(90, 700).star(200, 1000)
    lv.fuel_margin = 2.4
    L.append(lv)

    lv = Level("Pulse", h=1700,
               hint="Each gate has its own rhythm. Hover and watch before you commit.")
    lv.start(210, 20)
    lv.rect(20, 400, 140, 40).rect(260, 400, 140, 40)
    lv.laser(156, 420, 264, 420, on=1.2, off=1.6, phase=0.0)
    lv.rect(20, 800, 200, 40).rect(300, 800, 100, 40)
    lv.laser(216, 820, 304, 820, on=1.2, off=1.6, phase=0.9)
    lv.rect(20, 1200, 80, 40).rect(180, 1200, 220, 40)
    lv.laser(96, 1220, 184, 1220, on=1.2, off=1.6, phase=1.8)
    lv.rect(220, 1450, 180, 30)
    lv.goal(310, 1480)
    lv.star(330, 600).star(60, 1000).star(140, 1350)
    lv.fuel_margin = 2.2
    L.append(lv)

    lv = Level("Spin Cycle", h=1300,
               hint="Spinners sweep in a circle. Slip past when the arm swings away.")
    lv.start(90, 20)
    lv.rect(20, 450, 60, 300).rect(340, 450, 60, 300)
    lv.spinner(210, 600, 110, arms=2, speed=1.2)
    lv.rect(260, 1000, 140, 30)
    lv.goal(330, 1030)
    lv.star(210, 410).star(210, 790).star(60, 1200)
    lv.fuel_margin = 2.2
    L.append(lv)

    lv = Level("Mine Field", w=840, h=1000,
               hint="Mines don't move, but they don't forgive either.")
    lv.start(80, 20)
    lv.rect(400, 20, 40, 300)
    for (x, y) in [(200, 200), (300, 420), (190, 640), (420, 560), (520, 380),
                   (640, 220), (650, 600), (560, 780), (320, 820), (740, 420), (100, 840)]:
        lv.mine(x, y, r=14)
    lv.goal(760, 20)
    lv.star(310, 300).star(530, 560).star(700, 820)
    lv.fuel_margin = 2.2
    L.append(lv)

    lv = Level("Patrol", h=1700,
               hint="Patrolling mines! Time your climb between their passes.")
    lv.start(210, 20)
    lv.mine(60, 400, path=[(360, 400)], speed=120)
    lv.mine(360, 700, path=[(60, 700)], speed=150)
    lv.mine(60, 1000, path=[(360, 1000)], speed=180)
    lv.mine(60, 1280, path=[(360, 1280)], speed=140)
    lv.mine(360, 1280, path=[(60, 1280)], speed=140)
    lv.rect(20, 1450, 150, 30)
    lv.goal(95, 1480)
    lv.star(210, 550).star(210, 850).star(330, 1150)
    lv.fuel_margin = 2.2
    L.append(lv)

    lv = Level("Locked Out", w=840, h=1000,
               hint="Grab the key to unlock the door of the same colour.")
    lv.start(100, 20)
    lv.rect(560, 20, 30, 400)
    lv.rect(560, 420, 100, 30).rect(780, 420, 40, 30)
    lv.door(660, 420, 120, 30, color=0)
    lv.rect(20, 600, 260, 30)
    lv.key(100, 690, color=0)
    lv.rect(330, 250, 120, 30)
    lv.goal(720, 20)
    lv.star(390, 200).star(450, 650).star(720, 330)
    lv.fuel_margin = 2.2
    L.append(lv)

    lv = Level("Twin Spinners", h=1600,
               hint="Two spinners turning opposite ways. Patience pays.")
    lv.start(210, 20)
    lv.rect(260, 450, 140, 200)
    lv.spinner(140, 550, 100, arms=2, speed=1.3)
    lv.rect(20, 850, 140, 200)
    lv.spinner(280, 950, 100, arms=2, speed=-1.3, phase=0.8)
    lv.rect(260, 1200, 140, 160)
    lv.spinner(140, 1280, 90, arms=2, speed=1.6, phase=1.6)
    lv.rect(20, 1450, 160, 30)
    lv.goal(100, 1480)
    lv.star(60, 760).star(330, 1130).star(330, 1500)
    lv.fuel_margin = 2.2
    L.append(lv)

    lv = Level("Security Grid", w=840, h=1400,
               hint="Collect the key, dodge the beams and get inside the vault.")
    lv.start(150, 20)
    lv.rect(400, 300, 30, 650)
    lv.laser(20, 520, 400, 520, on=1.5, off=1.5)
    lv.laser(20, 800, 400, 800, on=1.5, off=1.5, phase=1.5)
    lv.rect(600, 120, 220, 24)
    lv.key(710, 200, color=0)
    lv.laser(430, 470, 820, 470, on=1.0, off=1.8, phase=0.5)
    lv.laser(430, 760, 820, 760, on=1.0, off=1.8, phase=1.4)
    lv.rect(540, 1000, 280, 30)
    lv.rect(540, 1150, 30, 230)
    lv.door(540, 1030, 30, 120, color=0)
    lv.goal(700, 1030)
    lv.star(210, 660).star(700, 610).star(250, 1250)
    lv.fuel_margin = 2.0
    L.append(lv)

    lv = Level("Orbitals", h=1600,
               hint="Mines in orbit. Count the beat and slip through.")
    lv.start(210, 20)
    lv.rect(20, 350, 50, 240).rect(350, 350, 50, 240)
    lv.rect(190, 450, 40, 40)
    lv.orbit_mine(210, 470, 110, speed=1.4)
    lv.rect(20, 830, 50, 240).rect(350, 830, 50, 240)
    lv.rect(190, 930, 40, 40)
    lv.orbit_mine(210, 950, 115, speed=-1.2)
    lv.orbit_mine(210, 950, 115, speed=-1.2, phase=3.14159)
    lv.rect(20, 1450, 140, 30)
    lv.goal(90, 1480)
    lv.star(100, 700).star(320, 1180).star(300, 1500)
    lv.fuel_margin = 2.2
    L.append(lv)

    lv = Level("Meltdown", w=840, h=2000,
               hint="The reactor is failing. Find the key and get to the top!")
    lv.start(100, 20)
    lv.rect(20, 450, 600, 30)
    lv.spinner(420, 250, 90, arms=2, speed=1.5)
    lv.laser(620, 465, 820, 465, on=1.4, off=1.4)
    lv.rect(220, 900, 600, 30)
    lv.mine(260, 690, path=[(740, 690)], speed=160)
    lv.can(700, 560)
    lv.rect(20, 1350, 600, 30)
    lv.door(620, 1350, 200, 30, color=0)
    lv.spinner(420, 1140, 110, arms=2, speed=-1.3)
    lv.key(730, 1150, color=0)
    lv.orbit_mine(560, 1680, 120, speed=1.1)
    lv.goal(250, 1380)
    lv.star(420, 120).star(100, 1100).star(720, 1850)
    lv.fuel_margin = 1.9
    L.append(lv)
    return L


# ---------------------------------------------------------------- world 4
def maze_level():
    """Procedural (but fixed-seed) maze for the Labyrinth level."""
    cols, rows, cell = 6, 8, 210
    rng = random.Random(4242)
    goal_cell = (cols - 1, rows - 1)
    links = set()
    seen = {(0, 0)}
    stack = [(0, 0)]
    while stack:
        c, r = stack[-1]
        options = []
        for dc, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nc, nr = c + dc, r + dr
            if 0 <= nc < cols and 0 <= nr < rows and (nc, nr) not in seen and (nc, nr) != goal_cell:
                options.append((nc, nr))
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

    # distances from start for star placement
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
    dead_ends = [n for n, ns in adj.items() if len(ns) == 1 and n not in ((0, 0), goal_cell)]
    dead_ends.sort(key=lambda n: -dist[n])

    lv = Level("Labyrinth", w=cols * cell, h=rows * cell, base="cave", jag=5,
               hint="A labyrinth in the void. Stars and fuel hide in the dead ends.")
    for link in links:
        a, b = tuple(link)
        lv.tunnel([centre(*a), centre(*b)], 110)
    lv.carve_rect(20, 20, 170, 170)
    gx, gy = centre(*goal_cell)
    lv.carve_rect(gx - 85, gy - 85, 170, 170)
    lv.start(105, 20)
    lv.goal(gx + 10, gy - 85, 60)
    for n in dead_ends[:3]:
        lv.star(*centre(*n))
    for n in dead_ends[3:5]:
        lv.can(*centre(*n))
    # hazards on a few long corridors, away from start and goal
    hazard_spots = [n for n in sorted(adj) if len(adj[n]) >= 3 and n not in ((0, 0), goal_cell)
                    and dist[n] >= 3]
    rng.shuffle(hazard_spots)
    for n in hazard_spots[:3]:
        x, y = centre(*n)
        lv.spinner(x, y, 40, arms=2, speed=1.4)
    return lv


def deep_void():
    L = []

    lv = Level("The Descent", h=2600, base="cave", jag=5,
               hint="A long way down. Control your speed — the landing is what counts.")
    lv.carve_rect(20, 2350, 380, 230)
    lv.tunnel([(300, 2400), (300, 2000), (120, 1700), (300, 1300), (120, 900), (250, 500)], 130)
    lv.carve_rect(20, 20, 380, 520)
    lv.start(100, 2350)
    lv.gate(2150, 300, on=1.2, off=1.8)
    lv.mine(210, 1500, r=13)
    lv.spinner(120, 900, 52, arms=2, speed=1.5)
    lv.gate(1100, 210, on=1.0, off=2.0, phase=1.0)
    lv.rect(20, 200, 20, 120, jag=0)
    lv.spikes(40, 200, 120, "right")
    lv.goal(110, 20)
    lv.star(335, 1990).star(300, 1300).star(340, 100)
    lv.fuel_margin = 1.9
    L.append(lv)

    lv = Level("Gauntlet", w=1600, h=800,
               hint="A gauntlet of everything. Keep moving!")
    lv.start(80, 20)
    lv.spikes(160, 20, 280, "up")
    lv.laser(300, 20, 300, 780, on=1.2, off=1.6)
    lv.spinner(620, 400, 130, arms=2, speed=1.1)
    lv.wind(850, 20, 250, 760, 0, 200)
    lv.spikes(850, 780, 250, "down")
    lv.mine(1250, 100, path=[(1250, 700)], speed=170)
    lv.mine(1380, 700, path=[(1380, 100)], speed=170)
    lv.goal(1520, 20)
    lv.star(340, 620).star(620, 680).star(1000, 200)
    lv.fuel_margin = 1.9
    L.append(lv)

    lv = Level("Three Keys", w=840, h=1600,
               hint="Three locks, three keys. Each key opens the gate of its colour.")
    lv.start(100, 20)
    lv.rect(20, 400, 560, 30)
    lv.door(580, 400, 240, 30, color=0)
    lv.key(700, 200, color=0)
    lv.spinner(400, 220, 90, arms=2, speed=1.2)
    lv.rect(260, 800, 560, 30)
    lv.door(20, 800, 240, 30, color=1)
    lv.key(120, 620, color=1)
    lv.laser(420, 430, 420, 800, on=1.2, off=1.6)
    lv.rect(20, 1200, 560, 30)
    lv.door(580, 1200, 240, 30, color=2)
    lv.key(720, 1000, color=2)
    lv.mine(120, 1010, path=[(560, 1010)], speed=150)
    lv.orbit_mine(420, 1420, 110, speed=1.2)
    lv.goal(160, 1230)
    lv.star(560, 620).star(300, 1100).star(720, 1500)
    lv.fuel_margin = 1.9
    L.append(lv)

    lv = Level("Windmill", h=1700,
               hint="Wind and blades. Use the gusts — don't fight them.")
    lv.start(80, 20)
    lv.wind(20, 300, 380, 300, 180, 0)
    lv.spinner(210, 450, 100, arms=2, speed=1.2)
    lv.wind(20, 750, 380, 300, -180, 0)
    lv.spinner(210, 900, 100, arms=2, speed=-1.0)
    lv.wind(20, 1150, 380, 250, 0, 220)
    lv.spinner(210, 1275, 90, arms=2, speed=1.5)
    lv.rect(250, 1500, 150, 30)
    lv.goal(325, 1530)
    lv.star(60, 450).star(360, 900).star(60, 1300)
    lv.fuel_margin = 2.0
    L.append(lv)

    lv = Level("Pinball", w=840, h=1400, jag=6,
               hint="Bouncing mines everywhere. Find the rhythm.")
    lv.start(80, 20)
    lv.rock(330, 330, 50)
    lv.rock(600, 480, 60)
    lv.rock(400, 850, 55)
    lv.rock(200, 1050, 45)
    lv.mine(100, 250, path=[(400, 600)], speed=130)
    lv.mine(480, 120, path=[(780, 300)], speed=150)
    lv.mine(150, 720, path=[(700, 760)], speed=170)
    lv.mine(420, 1150, path=[(100, 1300)], speed=120)
    lv.orbit_mine(600, 480, 105, speed=1.3)
    lv.rect(600, 1150, 220, 30, jag=0)
    lv.goal(710, 1180)
    lv.star(420, 660).star(720, 860).star(150, 1250)
    lv.fuel_margin = 2.0
    L.append(lv)

    lv = Level("Lockdown", w=840, h=1600,
               hint="Two vaults, two keys and a lot of lasers. Keep your cool.")
    lv.start(120, 20)
    lv.rect(400, 20, 40, 1150)
    lv.laser(20, 300, 400, 300, on=1.2, off=1.6, phase=0.0)
    lv.laser(20, 550, 400, 550, on=1.2, off=1.6, phase=0.7)
    lv.laser(20, 800, 400, 800, on=1.2, off=1.6, phase=1.4)
    lv.laser(20, 1050, 400, 1050, on=1.2, off=1.6, phase=2.1)
    lv.key(210, 1250, color=0)
    lv.laser(440, 950, 820, 950, on=1.2, off=1.6, phase=0.6)
    lv.rect(440, 700, 230, 30)
    lv.door(670, 700, 150, 30, color=0)
    lv.key(520, 520, color=1)
    lv.laser(440, 420, 820, 420, on=1.0, off=1.8, phase=1.2)
    lv.rect(440, 250, 230, 30)
    lv.door(670, 250, 150, 30, color=1)
    lv.goal(745, 20)
    lv.star(300, 680).star(620, 1400).star(520, 130)
    lv.fuel_margin = 1.9
    L.append(lv)

    lv = Level("Freefall", h=2600,
               hint="Drop through the gates. Brake hard before each one.")
    lv.rect(20, 2350, 160, 30)
    lv.start(100, 2380)
    lv.rect(20, 2000, 250, 30).rect(350, 2000, 50, 30)
    lv.laser(266, 2015, 354, 2015, on=1.0, off=2.0, phase=0.0)
    lv.rect(20, 1600, 60, 30).rect(160, 1600, 240, 30)
    lv.laser(76, 1615, 164, 1615, on=1.0, off=2.0, phase=0.7)
    lv.rect(20, 1200, 170, 30).rect(270, 1200, 130, 30)
    lv.laser(186, 1215, 274, 1215, on=1.0, off=2.0, phase=1.4)
    lv.rect(20, 800, 250, 30).rect(350, 800, 50, 30)
    lv.laser(266, 815, 354, 815, on=1.0, off=2.0, phase=2.1)
    lv.mine(60, 650, path=[(360, 650)], speed=130)
    lv.rect(20, 400, 60, 30).rect(160, 400, 240, 30)
    lv.laser(76, 415, 164, 415, on=1.0, off=2.0, phase=0.3)
    lv.goal(300, 20)
    lv.star(60, 1800).star(340, 1400).star(60, 1000)
    lv.fuel_margin = 2.0
    L.append(lv)

    lv = Level("Tight Squeeze", h=2200, base="cave", jag=3, fuel_margin=1.45, fuel_ratio=0.75,
               hint="Tight tunnels and a small tank. Precision is everything.")
    lv.carve_rect(20, 20, 380, 180)
    lv.tunnel([(210, 150), (120, 400), (300, 700), (120, 1000), (300, 1300),
               (150, 1600), (250, 1850)], 86)
    lv.carve_rect(90, 1800, 300, 200)
    lv.start(210, 20)
    lv.goal(140, 1800)
    lv.star(120, 400).star(300, 1300).star(150, 1600)
    L.append(lv)

    L.append(maze_level())

    lv = Level("Escape Velocity", h=3300, base="cave", jag=5,
               hint="One last climb. Reach escape velocity!")
    lv.carve_rect(20, 20, 380, 220)
    lv.start(210, 20)
    lv.tunnel([(210, 150), (210, 650)], 160, round_ends=False)
    lv.gate(360, 210, on=1.2, off=1.6)
    lv.gate(520, 210, on=1.2, off=1.6, phase=1.4)
    lv.carve_circle(210, 800, 170)
    lv.spinner(210, 800, 105, arms=2, speed=1.3)
    lv.tunnel([(210, 950), (120, 1300)], 130)
    lv.tunnel([(120, 1300), (130, 1800)], 130)
    lv.wind(55, 1320, 130, 360, 0, 200)
    lv.carve_circle(230, 1900, 165)
    lv.orbit_mine(230, 1900, 100, speed=1.3)
    lv.orbit_mine(230, 1900, 100, speed=1.3, phase=3.14159)
    lv.tunnel([(230, 2050), (330, 2400)], 125)
    lv.tunnel([(330, 2400), (100, 2520)], 110)
    lv.key(90, 2525, color=1)
    lv.tunnel([(330, 2400), (260, 2950)], 125)
    lv.door_across(2700, 290, color=1)
    lv.carve_rect(40, 2950, 340, 300)
    lv.can(120, 1500)
    lv.can(330, 2250)
    lv.goal(110, 2950)
    lv.star(210, 600).star(340, 1900).star(330, 3150)
    lv.fuel_margin = 1.8
    L.append(lv)
    return L


# Russian names and hints, keyed by the English level name.
RUSSIAN = {
    "First Flight": ("Первый полёт",
                     "Удерживай ГАЗ, чтобы включить двигатель. Направляй нос джойстиком. "
                     "Мягко сядь на зелёную площадку."),
    "Up and Over": ("Через стену",
                    "Перелети через стену. Сбрось газ заранее, чтобы не падать слишком быстро."),
    "Shelves": ("Полки", "Поднимайся через проёмы. Короткие нажатия на газ позволяют зависать."),
    "Going Down": ("Спуск", "Здесь всё сделает гравитация. Подгазовывай, чтобы замедлить падение перед посадкой."),
    "Zig Zag": ("Зигзаг", "Поднимайся зигзагом. Достаточно небольших наклонов."),
    "Fuel Stop": ("Заправка", "Топливо ограничено! Собирай оранжевые канистры по пути наверх."),
    "The Chimney": ("Дымоход", "Узкий дымоход. Лучше всего работают плавные поправки."),
    "Side Step": ("Шаг в сторону", "Петляй над колоннами и под ними. Чуть наклонись, чтобы сместиться вбок."),
    "Ledge Hopper": ("Прыжки по уступам", "Выровняйся над площадкой и опускайся строго вниз."),
    "Graduation": ("Выпускной", "Собери всё вместе. Продумай маршрут и экономь топливо."),
    "Sharp Edges": ("Острые края", "Красное — опасно. Шипы уничтожают ракету при касании."),
    "Stalactites": ("Сталактиты", "Проскользни между кристаллами. Держи скорость низкой."),
    "Updraft": ("Восходящий поток", "Голубые струи — это ветер. Поднимайся по шахте на восходящем потоке."),
    "Crosswind": ("Боковой ветер", "Ветер сносит в сторону. Наклоняйся ему навстречу!"),
    "Needle's Eye": ("Игольное ушко", "Встань под проёмом и поднимайся строго вверх."),
    "Downpour": ("Нисходящий поток", "Нисходящий поток! Не отпускай газ, чтобы контролировать спуск."),
    "Crystal Maze": ("Хрустальный лабиринт", "Найди путь через лабиринт. В тупиках прячутся звёзды."),
    "Gust Alley": ("Аллея порывов", "Восходящие и нисходящие потоки. Рассчитай газ, чтобы пересечь каждый порыв."),
    "Spiral": ("Спираль", "Двигайся по спирали к центру. Путь долгий — следи за топливом."),
    "Cavern Heart": ("Сердце пещер", "Сердце пещер. Всё, чему ты научился, — сразу."),
    "Laser Gate": ("Лазерные ворота", "Лазеры включаются и выключаются. Дождись, пока луч погаснет, и вперёд!"),
    "Pulse": ("Пульс", "У каждых ворот свой ритм. Зависни и понаблюдай, прежде чем лететь."),
    "Spin Cycle": ("Центрифуга", "Вертушки описывают круг. Проскочи, когда лопасть уйдёт в сторону."),
    "Mine Field": ("Минное поле", "Мины не двигаются, но и ошибок не прощают."),
    "Patrol": ("Патруль", "Патрульные мины! Поднимайся в промежутках между их проходами."),
    "Locked Out": ("Заперто", "Возьми ключ, чтобы открыть дверь того же цвета."),
    "Twin Spinners": ("Двойные вертушки", "Две вертушки вращаются в разные стороны. Терпение окупится."),
    "Security Grid": ("Охранная сетка", "Возьми ключ, уклонись от лучей и проберись в хранилище."),
    "Orbitals": ("Орбиты", "Мины на орбите. Поймай ритм и проскользни."),
    "Meltdown": ("Расплавление", "Реактор выходит из строя. Найди ключ и доберись до верха!"),
    "The Descent": ("Спуск в бездну", "Долгий путь вниз. Контролируй скорость — главное посадка."),
    "Gauntlet": ("Полоса препятствий", "Испытание из всего сразу. Не останавливайся!"),
    "Three Keys": ("Три ключа", "Три замка, три ключа. Каждый ключ открывает ворота своего цвета."),
    "Windmill": ("Ветряк", "Ветер и лопасти. Используй порывы, а не борись с ними."),
    "Pinball": ("Пинбол", "Мины носятся повсюду. Поймай ритм."),
    "Lockdown": ("Изоляция", "Два хранилища, два ключа и куча лазеров. Сохраняй спокойствие."),
    "Freefall": ("Свободное падение", "Падай сквозь ворота. Тормози перед каждыми."),
    "Tight Squeeze": ("Теснота", "Узкие туннели и маленький бак. Точность решает всё."),
    "Labyrinth": ("Лабиринт", "Лабиринт в пустоте. В тупиках спрятаны звёзды и топливо."),
    "Escape Velocity": ("Вторая космическая", "Последний подъём. Набери вторую космическую скорость!"),
}


WORLDS += WORLDS2
RUSSIAN.update(RUSSIAN2)


def build_all():
    levels = []
    makers = (launch_bay, crystal_caverns, reactor_core, deep_void,
              emerald_mines, acid_falls, nebula_gardens, event_horizon)
    for world, maker in enumerate(makers):
        group = maker()
        assert len(group) == 10, (maker.__name__, len(group))
        for lv in group:
            lv.world = world
            lv.name_ru, lv.hint_ru = RUSSIAN.get(lv.name, (None, None))
            levels.append(lv)
    return levels
