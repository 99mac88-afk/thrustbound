// Rocket simulation: a line-by-line port of Thrustbound/Game/GameWorld.swift.
// Coordinates are points with the origin at the bottom left and y pointing up.

export const Physics = {
  gravity: 160,
  thrust: 400,
  drag: 0.3,
  maxSpeed: 480,
  turnRate: 6.5,
  crashSpeed: 130,
  landMaxTilt: 0.30,
  landMaxSpeed: 30,
  landHoldTime: 0.6,
  restitution: 0.25,
  friction: 5,
  step: 1 / 240,
  canFuel: 10,
  pickupRadius: 26,
  hazardForgiveness: 1.5,
  lowFuelFraction: 0.2,
};

export const RocketShape = {
  hull: [
    { x: 0, y: 12, r: 6 },
    { x: 0, y: 0, r: 8 },
    { x: 0, y: -10, r: 8 },
    { x: -10, y: -17, r: 3 },
    { x: 10, y: -17, r: 3 },
  ],
  feet: [2, 3, 4],
  spawnHeight: 20,
};

export function rotate(p, a) {
  const c = Math.cos(a), s = Math.sin(a);
  return { x: p.x * c - p.y * s, y: p.x * s + p.y * c };
}

export function wrapAngle(a) {
  const tau = 2 * Math.PI;
  let r = a % tau;
  if (r > Math.PI) r -= tau;
  if (r < -Math.PI) r += tau;
  return r;
}

function closestPoint(ax, ay, bx, by, px, py) {
  const abx = bx - ax, aby = by - ay;
  const len2 = abx * abx + aby * aby;
  if (len2 < 1e-9) return { x: ax, y: ay };
  const t = Math.min(1, Math.max(0, ((px - ax) * abx + (py - ay) * aby) / len2));
  return { x: ax + abx * t, y: ay + aby * t };
}

export function distToSegment(p, a, b) {
  const q = closestPoint(a.x, a.y, b.x, b.y, p.x, p.y);
  return Math.hypot(p.x - q.x, p.y - q.y);
}

export function pointInTriangle(p, a, b, c) {
  const sign = (p1, p2, p3) => (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y);
  const d1 = sign(p, a, b), d2 = sign(p, b, c), d3 = sign(p, c, a);
  const neg = d1 < 0 || d2 < 0 || d3 < 0;
  const pos = d1 > 0 || d2 > 0 || d3 > 0;
  return !(neg && pos);
}

function bounds(points) {
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (const p of points) {
    minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x);
    minY = Math.min(minY, p.y); maxY = Math.max(maxY, p.y);
  }
  return { minX, maxX, minY, maxY };
}

function makeSegment(a, b, door = -1) {
  const dx = b.x - a.x, dy = b.y - a.y;
  const len = Math.hypot(dx, dy) || 1;
  return {
    ax: a.x, ay: a.y, bx: b.x, by: b.y,
    nx: dy / len, ny: -dx / len, // solid on the left, free side on the right
    door,
    minX: Math.min(a.x, b.x), maxX: Math.max(a.x, b.x),
    minY: Math.min(a.y, b.y), maxY: Math.max(a.y, b.y),
  };
}

class MineTrack {
  constructor(mine) {
    let pts = mine.path.length ? mine.path.slice() : [{ x: 0, y: 0 }];
    if (mine.loop && pts.length > 1) pts.push(pts[0]);
    const cum = [0];
    for (let i = 1; i < Math.max(1, pts.length); i++) {
      cum.push(cum[i - 1] + Math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y));
    }
    this.points = pts;
    this.cumulative = cum;
    this.total = cum[cum.length - 1] || 0;
    this.loop = mine.loop;
    this.speed = mine.speed;
  }

  position(time) {
    const pts = this.points;
    if (pts.length <= 1 || this.total <= 0 || this.speed <= 0) return pts[0];
    let d = time * this.speed;
    if (this.loop) {
      d = d % this.total;
    } else {
      const period = 2 * this.total;
      d = d % period;
      if (d > this.total) d = period - d;
    }
    for (let k = 1; k < pts.length; k++) {
      if (d <= this.cumulative[k]) {
        const segLen = this.cumulative[k] - this.cumulative[k - 1];
        const u = segLen > 0 ? (d - this.cumulative[k - 1]) / segLen : 0;
        return { x: pts[k - 1].x + (pts[k].x - pts[k - 1].x) * u, y: pts[k - 1].y + (pts[k].y - pts[k - 1].y) * u };
      }
    }
    return pts[pts.length - 1];
  }
}

export class GameWorld {
  constructor(level) {
    this.level = level;
    this.mineTracks = level.mines.map((m) => new MineTrack(m));
    this.spikeBoxes = level.spikes.map((t) => bounds(t));
    this.segments = [];
    for (const polygon of level.terrain) {
      for (const ring of polygon) {
        if (ring.length < 3) continue;
        for (let i = 0; i < ring.length; i++) {
          const a = ring[i], b = ring[(i + 1) % ring.length];
          if ((b.x - a.x) ** 2 + (b.y - a.y) ** 2 > 1e-6) this.segments.push(makeSegment(a, b));
        }
      }
    }
    level.doors.forEach((door, index) => {
      const r = door.rect;
      const c = [{ x: r.x, y: r.y }, { x: r.x + r.w, y: r.y }, { x: r.x + r.w, y: r.y + r.h }, { x: r.x, y: r.y + r.h }];
      for (let i = 0; i < 4; i++) this.segments.push(makeSegment(c[i], c[(i + 1) % 4], index));
    });
    this.reset();
  }

  reset() {
    const l = this.level;
    this.status = 'flying';
    this.position = { x: l.start.x, y: l.start.y + RocketShape.spawnHeight };
    this.velocity = { x: 0, y: 0 };
    this.angle = 0;
    this.fuel = l.fuel;
    this.time = 0;
    this.flightTime = 0;
    this.started = false;
    this.thrusting = false;
    this.collectedStars = new Set();
    this.collectedCans = new Set();
    this.collectedKeys = new Set();
    this.openDoors = new Set();
    this.landingTimer = 0;
    this.touchingGoal = false;
    this.tiltedOnGoal = false;
    this.stuckTimer = 0;
    this.lowFuelWarned = false;
    this.events = [];
  }

  get landingProgress() { return Math.min(1, this.landingTimer / Physics.landHoldTime); }
  get fuelFraction() { return this.level.fuel > 0 ? this.fuel / this.level.fuel : 0; }
  get heldKeyColors() { return [...this.collectedKeys].sort((a, b) => a - b).map((i) => this.level.keys[i].color); }

  drainEvents() {
    const e = this.events;
    this.events = [];
    return e;
  }

  minePosition(i) { return this.mineTracks[i].position(this.time); }

  spinnerAngle(i) {
    const s = this.level.spinners[i];
    return s.phase + s.speed * this.time;
  }

  laserState(i) {
    const l = this.level.lasers[i];
    if (l.off <= 0) return 'on';
    if (l.on <= 0) return 'off';
    const cycle = l.on + l.off;
    let local = (this.time + l.phase) % cycle;
    if (local < 0) local += cycle;
    if (local < l.on) return 'on';
    if (local > cycle - 0.5) return 'warning';
    return 'off';
  }

  /** input: { thrust: bool, targetAngle: number|null } */
  step(dt, input) {
    this.time += dt;
    if (this.status !== 'flying') {
      this.thrusting = false;
      return;
    }
    const hasTarget = input.targetAngle !== null && input.targetAngle !== undefined;
    if (!this.started && (input.thrust || hasTarget)) this.started = true;
    if (this.started) this.flightTime += dt;

    if (hasTarget) {
      const diff = wrapAngle(input.targetAngle - this.angle);
      const maxStep = Physics.turnRate * dt;
      this.angle = wrapAngle(this.angle + Math.max(-maxStep, Math.min(maxStep, diff)));
    }

    let ax = 0, ay = -Physics.gravity;
    this.thrusting = !!input.thrust && this.fuel > 0;
    if (this.thrusting) {
      ax += -Math.sin(this.angle) * Physics.thrust;
      ay += Math.cos(this.angle) * Physics.thrust;
      this.fuel = Math.max(0, this.fuel - dt);
    }
    for (const w of this.level.winds) {
      const r = w.rect;
      if (this.position.x >= r.x && this.position.x < r.x + r.w && this.position.y >= r.y && this.position.y < r.y + r.h) {
        ax += w.force.x;
        ay += w.force.y;
      }
    }
    this.velocity.x += ax * dt;
    this.velocity.y += ay * dt;
    const damp = Math.max(0, 1 - Physics.drag * dt);
    this.velocity.x *= damp;
    this.velocity.y *= damp;
    const speed = Math.hypot(this.velocity.x, this.velocity.y);
    if (speed > Physics.maxSpeed) {
      this.velocity.x *= Physics.maxSpeed / speed;
      this.velocity.y *= Physics.maxSpeed / speed;
    }
    this.position.x += this.velocity.x * dt;
    this.position.y += this.velocity.y * dt;

    this.resolveTerrain(dt);
    if (this.status !== 'flying') return;
    this.checkHazards();
    if (this.status !== 'flying') return;
    this.collectItems();
    this.updateLanding(dt);
    if (this.status !== 'flying') return;
    this.updateFuel(dt);

    const p = this.position, l = this.level;
    if (p.x < -40 || p.x > l.width + 40 || p.y < -40 || p.y > l.height + 40) {
      this.crash({ x: p.x, y: p.y }, 'outOfBounds');
    }
  }

  resolveTerrain(dt) {
    let worstImpact = 0;
    let impactPoint = { x: this.position.x, y: this.position.y };
    for (const circle of RocketShape.hull) {
      const off = rotate(circle, this.angle);
      let cx = this.position.x + off.x, cy = this.position.y + off.y;
      const r = circle.r;
      for (const seg of this.segments) {
        if (seg.door >= 0 && this.openDoors.has(seg.door)) continue;
        if (cx + r < seg.minX || cx - r > seg.maxX || cy + r < seg.minY || cy - r > seg.maxY) continue;
        const q = closestPoint(seg.ax, seg.ay, seg.bx, seg.by, cx, cy);
        const dx = cx - q.x, dy = cy - q.y;
        const dist2 = dx * dx + dy * dy;
        if (dist2 >= r * r) continue;
        const dist = Math.sqrt(dist2);
        const nx = dist > 1e-5 ? dx / dist : seg.nx;
        const ny = dist > 1e-5 ? dy / dist : seg.ny;
        const push = r - dist;
        this.position.x += nx * push;
        this.position.y += ny * push;
        cx += nx * push;
        cy += ny * push;
        const vn = this.velocity.x * nx + this.velocity.y * ny;
        if (vn < 0) {
          const impact = -vn;
          if (impact > worstImpact) {
            worstImpact = impact;
            impactPoint = q;
          }
          const bounce = impact > 40 ? Physics.restitution : 0;
          this.velocity.x -= nx * vn * (1 + bounce);
          this.velocity.y -= ny * vn * (1 + bounce);
          const vn2 = this.velocity.x * nx + this.velocity.y * ny;
          const tx = this.velocity.x - nx * vn2, ty = this.velocity.y - ny * vn2;
          const f = Math.min(1, Physics.friction * dt);
          this.velocity.x -= tx * f;
          this.velocity.y -= ty * f;
        }
      }
    }
    if (worstImpact > Physics.crashSpeed) {
      this.crash(impactPoint, 'impact');
    } else if (worstImpact > 45) {
      this.events.push({ type: 'bump', speed: worstImpact });
    }
  }

  checkHazards() {
    const l = this.level;
    for (const circle of RocketShape.hull) {
      const off = rotate(circle, this.angle);
      const c = { x: this.position.x + off.x, y: this.position.y + off.y };
      const r = Math.max(1, circle.r - Physics.hazardForgiveness);

      for (let k = 0; k < l.spikes.length; k++) {
        const tri = l.spikes[k];
        if (tri.length !== 3) continue;
        const box = this.spikeBoxes[k];
        if (c.x + r < box.minX || c.x - r > box.maxX || c.y + r < box.minY || c.y - r > box.maxY) continue;
        if (pointInTriangle(c, tri[0], tri[1], tri[2]) ||
            distToSegment(c, tri[0], tri[1]) < r ||
            distToSegment(c, tri[1], tri[2]) < r ||
            distToSegment(c, tri[2], tri[0]) < r) {
          this.crash(c, 'hazard');
          return;
        }
      }

      for (let i = 0; i < l.mines.length; i++) {
        const p = this.minePosition(i);
        const rr = r + l.mines[i].radius;
        if ((c.x - p.x) ** 2 + (c.y - p.y) ** 2 < rr * rr) {
          this.crash(c, 'hazard');
          return;
        }
      }

      for (let i = 0; i < l.spinners.length; i++) {
        const s = l.spinners[i];
        const toHub = Math.hypot(c.x - s.center.x, c.y - s.center.y);
        if (toHub > s.length + r + 6) continue;
        if (toHub < r + 9) {
          this.crash(c, 'hazard');
          return;
        }
        const base = this.spinnerAngle(i);
        for (let k = 0; k < s.arms; k++) {
          const a = base + (k * 2 * Math.PI) / s.arms;
          const tip = { x: s.center.x + Math.cos(a) * s.length, y: s.center.y + Math.sin(a) * s.length };
          if (distToSegment(c, s.center, tip) < r + 4) {
            this.crash(c, 'hazard');
            return;
          }
        }
      }

      for (let i = 0; i < l.lasers.length; i++) {
        if (this.laserState(i) !== 'on') continue;
        const ls = l.lasers[i];
        if (distToSegment(c, ls.a, ls.b) < r + 1.5) {
          this.crash(c, 'hazard');
          return;
        }
      }
    }
  }

  collectItems() {
    const l = this.level;
    const r2 = Physics.pickupRadius * Physics.pickupRadius;
    const near = (p) => (this.position.x - p.x) ** 2 + (this.position.y - p.y) ** 2 < r2;
    l.stars.forEach((p, i) => {
      if (!this.collectedStars.has(i) && near(p)) {
        this.collectedStars.add(i);
        this.events.push({ type: 'star', index: i });
      }
    });
    l.cans.forEach((p, i) => {
      if (!this.collectedCans.has(i) && near(p)) {
        this.collectedCans.add(i);
        this.fuel = Math.min(l.fuel, this.fuel + Physics.canFuel);
        if (this.fuelFraction >= Physics.lowFuelFraction) this.lowFuelWarned = false;
        this.events.push({ type: 'fuelCan', index: i });
      }
    });
    l.keys.forEach((key, i) => {
      if (!this.collectedKeys.has(i) && near(key.position)) {
        this.collectedKeys.add(i);
        this.events.push({ type: 'key', index: i });
        l.doors.forEach((door, d) => {
          if (door.color === key.color && !this.openDoors.has(d)) {
            this.openDoors.add(d);
            this.events.push({ type: 'doorOpened', index: d });
          }
        });
      }
    });
  }

  updateLanding(dt) {
    const g = this.level.goal;
    let touching = false;
    for (const idx of RocketShape.feet) {
      const circle = RocketShape.hull[idx];
      const off = rotate(circle, this.angle);
      const cx = this.position.x + off.x, cy = this.position.y + off.y;
      const r = circle.r;
      if (cx >= g.x - g.width / 2 - r && cx <= g.x + g.width / 2 + r && cy >= g.y - 1 && cy - r <= g.y + 1.5) {
        touching = true;
        break;
      }
    }
    this.touchingGoal = touching;
    const upright = Math.abs(this.angle) < Physics.landMaxTilt;
    this.tiltedOnGoal = touching && !upright;
    const centered = Math.abs(this.position.x - g.x) <= g.width / 2;
    const speed = Math.hypot(this.velocity.x, this.velocity.y);
    if (touching && upright && centered && speed < Physics.landMaxSpeed) {
      this.landingTimer += dt;
      if (this.landingTimer >= Physics.landHoldTime) {
        this.status = 'landed';
        this.thrusting = false;
        this.velocity = { x: 0, y: 0 };
        this.events.push({ type: 'landed' });
      }
    } else {
      this.landingTimer = Math.max(0, this.landingTimer - dt * 2);
    }
  }

  updateFuel(dt) {
    if (this.started && !this.lowFuelWarned && this.level.fuel > 0 && this.fuelFraction < Physics.lowFuelFraction) {
      this.lowFuelWarned = true;
      this.events.push({ type: 'lowFuel' });
    }
    if (this.fuel <= 0 && !this.touchingGoal && Math.hypot(this.velocity.x, this.velocity.y) < 6) {
      this.stuckTimer += dt;
      if (this.stuckTimer > 1.5) {
        this.status = 'outOfFuel';
        this.thrusting = false;
        this.events.push({ type: 'outOfFuel' });
      }
    } else {
      this.stuckTimer = 0;
    }
  }

  crash(point, cause) {
    if (this.status !== 'flying') return;
    this.status = 'crashed';
    this.thrusting = false;
    this.events.push({ type: 'crashed', at: point, cause });
  }

  /** Test hook: teleport the rocket. */
  place(point, velocity = { x: 0, y: 0 }, angle = 0) {
    this.position = { x: point.x, y: point.y };
    this.velocity = { x: velocity.x, y: velocity.y };
    this.angle = angle;
  }
}
