// Draws levels on a canvas (port of LevelRenderer.swift / SceneNodes.swift).
// World space: y up. The caller sets a transform that flips y.
import { Palette, drawGlow, keyColor, keyPath, lighter, minePath, rgba, starPath } from './art.js';

const TAU = Math.PI * 2;
let starShape = null;
let keyShape = null;
const mineShapes = new Map();
const mineShape = (r) => {
  let p = mineShapes.get(r);
  if (!p) { p = minePath(r); mineShapes.set(r, p); }
  return p;
};

/** Terrain as one even-odd path (outer rock with caves cut out). */
export function terrainPath(terrain) {
  const p = new Path2D();
  for (const poly of terrain) {
    for (const ring of poly) {
      if (ring.length < 3) continue;
      p.moveTo(ring[0].x, ring[0].y);
      for (let i = 1; i < ring.length; i++) p.lineTo(ring[i].x, ring[i].y);
      p.closePath();
    }
  }
  return p;
}

export function drawTerrain(ctx, path, theme) {
  ctx.fillStyle = theme.rock;
  ctx.fill(path, 'evenodd');
  ctx.lineJoin = 'round';
  ctx.lineCap = 'round';
  ctx.save();
  ctx.globalCompositeOperation = 'lighter';
  ctx.strokeStyle = rgba(theme.neon, 0.22);
  ctx.lineWidth = 9;
  ctx.stroke(path);
  ctx.restore();
  ctx.strokeStyle = theme.neon;
  ctx.lineWidth = 2.2;
  ctx.stroke(path);
}

function flipText(ctx, text, x, y, size, color, maxWidth) {
  ctx.save();
  ctx.translate(x, y);
  ctx.scale(1, -1);
  ctx.font = `900 ${size}px ui-rounded, "SF Pro Rounded", system-ui, sans-serif`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillStyle = color;
  const w = ctx.measureText(text).width;
  if (maxWidth && w > maxWidth) ctx.scale(maxWidth / w, maxWidth / w);
  ctx.fillText(text, 0, 0);
  ctx.restore();
}

/**
 * dyn: {
 *   t: seconds (animations), minePos(i), spinnerAngle(i), laserState(i),
 *   gone: { stars: Map(i -> time), cans, keys, doors }, landLabel: string
 * }
 */
export function drawLevelBack(ctx, level, theme, dyn) {
  const t = dyn.t;
  // Glow behind the goal so it reads from far away.
  const g = level.goal;
  ctx.save();
  ctx.globalCompositeOperation = 'lighter';
  const pulse = 0.07 + 0.13 * (0.5 + 0.5 * Math.cos((t * Math.PI) / 1.1));
  const grad = ctx.createLinearGradient(0, g.y, 0, g.y + 260);
  grad.addColorStop(0, rgba(Palette.goal, pulse));
  grad.addColorStop(1, rgba(Palette.goal, 0));
  ctx.fillStyle = grad;
  ctx.fillRect(g.x - (g.width * 0.9) / 2, g.y, g.width * 0.9, 260);
  ctx.restore();

  for (const w of level.winds) {
    ctx.fillStyle = rgba(Palette.wind, 0.045);
    ctx.fillRect(w.rect.x, w.rect.y, w.rect.w, w.rect.h);
    ctx.strokeStyle = rgba(Palette.wind, 0.12);
    ctx.lineWidth = 1;
    ctx.strokeRect(w.rect.x, w.rect.y, w.rect.w, w.rect.h);
  }
}

export function drawLevelFront(ctx, level, theme, dyn) {
  const t = dyn.t;
  const gone = dyn.gone || {};
  const fade = (map, i) => {
    if (!map || !map.has(i)) return { a: 1, s: 1 };
    const k = Math.min(1, (t - map.get(i)) / 0.22);
    return { a: 1 - k, s: 1 + 0.9 * k };
  };

  // Pads
  for (const [pad, isGoal] of [[level.start, false], [level.goal, true]]) {
    ctx.save();
    ctx.translate(pad.x, pad.y);
    const w = pad.width;
    ctx.beginPath();
    ctx.roundRect(-w / 2, -10, w, 10, 2);
    ctx.fillStyle = isGoal ? '#0E3A22' : Palette.metal;
    ctx.fill();
    ctx.strokeStyle = isGoal ? Palette.goal : '#8C9AB3';
    ctx.lineWidth = 1.5;
    ctx.stroke();
    ctx.fillStyle = isGoal ? Palette.goal : '#C9D3E3';
    ctx.fillRect(-w / 2 + 1, -3, w - 2, 3);
    for (const side of [-1, 1]) {
      const lx = side * (w / 2 - 6);
      if (isGoal) {
        ctx.save();
        ctx.globalCompositeOperation = 'lighter';
        ctx.globalAlpha = 0.15 + 0.75 * (0.5 + 0.5 * Math.cos((t * Math.PI) / 0.45));
        drawGlow(ctx, lx, -6.5, 10, Palette.goal);
        ctx.restore();
      }
      ctx.beginPath();
      ctx.arc(lx, -6.5, 2.5, 0, TAU);
      ctx.fillStyle = isGoal ? Palette.goal : Palette.star;
      ctx.fill();
    }
    if (isGoal && dyn.landLabel) flipText(ctx, dyn.landLabel, 0, -6.5, 8, 'rgba(255,255,255,0.85)', w - 22);
    ctx.restore();
  }

  // Doors
  level.doors.forEach((door, i) => {
    let a = 1, s = 1;
    if (gone.doors && gone.doors.has(i)) {
      const k = Math.min(1, (t - gone.doors.get(i)) / 0.4);
      a = 1 - k;
      s = 1 - 0.8 * k;
      if (a <= 0) return;
    }
    const color = keyColor(door.color);
    const r = door.rect;
    ctx.save();
    ctx.globalAlpha = a;
    ctx.translate(r.x + r.w / 2, r.y + r.h / 2);
    ctx.scale(s, s);
    ctx.fillStyle = rgba(color, 0.3);
    ctx.fillRect(-r.w / 2, -r.h / 2, r.w, r.h);
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.strokeRect(-r.w / 2, -r.h / 2, r.w, r.h);
    ctx.beginPath();
    if (r.w >= r.h) {
      for (let x = -r.w / 2 + 8; x < r.w / 2 - 4; x += 12) {
        ctx.moveTo(x, -r.h / 2 + 3);
        ctx.lineTo(x + 6, r.h / 2 - 3);
      }
    } else {
      for (let y = -r.h / 2 + 8; y < r.h / 2 - 4; y += 12) {
        ctx.moveTo(-r.w / 2 + 3, y);
        ctx.lineTo(r.w / 2 - 3, y + 6);
      }
    }
    ctx.strokeStyle = rgba(color, 0.55);
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(0, 2, 4, 0, Math.PI);
    ctx.strokeStyle = '#FFFFFF';
    ctx.stroke();
    ctx.beginPath();
    ctx.roundRect(-6, -6, 12, 9, 2);
    ctx.fillStyle = color;
    ctx.fill();
    ctx.lineWidth = 1.2;
    ctx.stroke();
    ctx.restore();
  });

  // Stars, fuel cans, keys
  starShape ??= starPath(12, 5.4);
  keyShape ??= keyPath();
  level.stars.forEach((p, i) => {
    const f = fade(gone.stars, i);
    if (f.a <= 0) return;
    const bob = 4 * (0.5 - 0.5 * Math.cos((t * Math.PI) / 0.9));
    ctx.save();
    ctx.globalAlpha = f.a;
    ctx.translate(p.x, p.y + bob);
    ctx.scale(f.s, f.s);
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.globalAlpha = 0.45 * f.a;
    drawGlow(ctx, 0, 0, 24, Palette.star);
    ctx.restore();
    ctx.rotate(0.35 * (0.5 - 0.5 * Math.cos((t * Math.PI) / 0.8)) * 2 - 0.35);
    ctx.fillStyle = Palette.star;
    ctx.fill(starShape);
    ctx.strokeStyle = 'rgba(255,255,255,0.9)';
    ctx.lineWidth = 1.2;
    ctx.stroke(starShape);
    ctx.restore();
  });
  level.cans.forEach((p, i) => {
    const f = fade(gone.cans, i);
    if (f.a <= 0) return;
    const bob = 3 * (0.5 - 0.5 * Math.cos((t * Math.PI) / 0.7));
    ctx.save();
    ctx.globalAlpha = f.a;
    ctx.translate(p.x, p.y + bob);
    ctx.scale(f.s, f.s);
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.globalAlpha = 0.4 * f.a;
    drawGlow(ctx, 0, 0, 22, Palette.fuel);
    ctx.restore();
    ctx.beginPath();
    ctx.roundRect(-8, -10, 16, 20, 4);
    ctx.fillStyle = Palette.fuel;
    ctx.fill();
    ctx.strokeStyle = '#FFFFFF';
    ctx.lineWidth = 1.2;
    ctx.stroke();
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(-3, 10, 6, 3);
    ctx.beginPath();
    ctx.moveTo(0, 6);
    ctx.quadraticCurveTo(7, -4, 0, -6);
    ctx.quadraticCurveTo(-7, -4, 0, 6);
    ctx.fillStyle = '#5A2E00';
    ctx.fill();
    ctx.restore();
  });
  level.keys.forEach((k, i) => {
    const f = fade(gone.keys, i);
    if (f.a <= 0) return;
    const color = keyColor(k.color);
    ctx.save();
    ctx.globalAlpha = f.a;
    ctx.translate(k.position.x, k.position.y);
    ctx.scale(f.s, f.s);
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.globalAlpha = 0.5 * f.a;
    drawGlow(ctx, 0, 0, 24, color);
    ctx.restore();
    ctx.scale(Math.cos((t * Math.PI) / 0.9), 1);
    ctx.fillStyle = color;
    ctx.fill(keyShape);
    ctx.strokeStyle = '#FFFFFF';
    ctx.lineWidth = 1;
    ctx.stroke(keyShape);
    ctx.restore();
  });

  // Spikes
  if (level.spikes.length) {
    const p = new Path2D();
    for (const tri of level.spikes) {
      if (tri.length !== 3) continue;
      p.moveTo(tri[0].x, tri[0].y);
      p.lineTo(tri[1].x, tri[1].y);
      p.lineTo(tri[2].x, tri[2].y);
      p.closePath();
    }
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.strokeStyle = rgba(Palette.hazard, 0.35);
    ctx.lineWidth = 5;
    ctx.lineJoin = 'round';
    ctx.stroke(p);
    ctx.restore();
    ctx.fillStyle = Palette.hazard;
    ctx.fill(p);
    ctx.strokeStyle = Palette.hazardCore;
    ctx.lineWidth = 1;
    ctx.stroke(p);
  }

  // Mines
  level.mines.forEach((mine, i) => {
    if (mine.path.length > 1) {
      ctx.beginPath();
      ctx.moveTo(mine.path[0].x, mine.path[0].y);
      for (const q of mine.path.slice(1)) ctx.lineTo(q.x, q.y);
      if (mine.loop) ctx.closePath();
      ctx.strokeStyle = rgba(Palette.hazard, 0.16);
      ctx.lineWidth = 1.5;
      ctx.stroke();
    }
    const pos = dyn.minePos ? dyn.minePos(i) : mine.path[0];
    ctx.save();
    ctx.translate(pos.x, pos.y);
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.globalAlpha = 0.45;
    drawGlow(ctx, 0, 0, mine.radius * 2.6, Palette.hazard);
    ctx.restore();
    ctx.save();
    ctx.rotate((t * Math.PI) / 2.4);
    ctx.fillStyle = Palette.hazard;
    ctx.fill(mineShape(mine.radius));
    ctx.strokeStyle = Palette.hazardCore;
    ctx.lineWidth = 1;
    ctx.stroke(mineShape(mine.radius));
    ctx.restore();
    ctx.globalAlpha = 0.3 + 0.7 * (0.5 + 0.5 * Math.cos((t * Math.PI) / 0.5));
    ctx.beginPath();
    ctx.arc(0, 0, mine.radius * 0.4, 0, TAU);
    ctx.fillStyle = Palette.hazardCore;
    ctx.fill();
    ctx.restore();
  });

  // Spinners
  level.spinners.forEach((sp, i) => {
    ctx.beginPath();
    ctx.arc(sp.center.x, sp.center.y, sp.length, 0, TAU);
    ctx.fillStyle = rgba(Palette.hazard, 0.04);
    ctx.fill();
    ctx.strokeStyle = rgba(Palette.hazard, 0.14);
    ctx.lineWidth = 1;
    ctx.stroke();
    const base = dyn.spinnerAngle ? dyn.spinnerAngle(i) : sp.phase;
    ctx.save();
    ctx.translate(sp.center.x, sp.center.y);
    for (let k = 0; k < sp.arms; k++) {
      ctx.save();
      ctx.rotate(base + (k * TAU) / sp.arms);
      ctx.save();
      ctx.globalCompositeOperation = 'lighter';
      ctx.strokeStyle = rgba(Palette.hazard, 0.4);
      ctx.lineWidth = 12;
      ctx.lineCap = 'round';
      ctx.beginPath();
      ctx.moveTo(4, 0);
      ctx.lineTo(sp.length - 4, 0);
      ctx.stroke();
      ctx.restore();
      ctx.beginPath();
      ctx.roundRect(0, -4, sp.length, 8, 4);
      ctx.fillStyle = Palette.hazard;
      ctx.fill();
      ctx.strokeStyle = Palette.hazardCore;
      ctx.lineWidth = 1;
      ctx.stroke();
      ctx.restore();
    }
    ctx.beginPath();
    ctx.arc(0, 0, 10, 0, TAU);
    ctx.fillStyle = Palette.metal;
    ctx.fill();
    ctx.strokeStyle = Palette.hazard;
    ctx.lineWidth = 2.5;
    ctx.stroke();
    ctx.restore();
  });

  // Lasers
  level.lasers.forEach((l, i) => {
    const state = dyn.laserState ? dyn.laserState(i) : 'on';
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(l.a.x, l.a.y);
    ctx.lineTo(l.b.x, l.b.y);
    ctx.strokeStyle = rgba(Palette.hazard, 0.2);
    ctx.lineWidth = 1;
    ctx.stroke();
    if (state === 'on') {
      ctx.save();
      ctx.globalCompositeOperation = 'lighter';
      ctx.strokeStyle = rgba(Palette.hazard, 0.45 * (0.75 + 0.25 * Math.sin(t * 38)));
      ctx.lineWidth = 9;
      ctx.stroke();
      ctx.restore();
      ctx.strokeStyle = Palette.hazardCore;
      ctx.lineWidth = 2.4;
      ctx.stroke();
    } else if (state === 'warning') {
      ctx.strokeStyle = rgba(Palette.hazardCore, Math.floor(t * 14) % 2 === 0 ? 0.45 : 0.08);
      ctx.lineWidth = 2.4;
      ctx.stroke();
    }
    const angle = Math.atan2(l.b.y - l.a.y, l.b.x - l.a.x);
    for (const p of [l.a, l.b]) {
      ctx.save();
      ctx.translate(p.x, p.y);
      ctx.rotate(angle);
      ctx.beginPath();
      ctx.roundRect(-6, -6, 12, 12, 2);
      ctx.fillStyle = Palette.metal;
      ctx.fill();
      ctx.strokeStyle = '#8C9AB3';
      ctx.lineWidth = 1;
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(0, 0, 2.5, 0, TAU);
      ctx.fillStyle = Palette.hazard;
      ctx.fill();
      ctx.restore();
    }
  });
}

// ---- Particles

export class Particles {
  constructor() {
    this.list = [];
    this.winds = [];
  }

  clear() {
    this.list = [];
    this.winds = [];
  }

  add(p) {
    if (this.list.length < 1500) this.list.push(p);
  }

  burst(x, y, { count, speed, speedRange, life, lifeRange, size, sizeSpeed = 0, colors, ay = 0, angle = null, spread = TAU, alpha = 1, alphaSpeed = 0, square = false }) {
    for (let i = 0; i < count; i++) {
      const a = angle === null ? Math.random() * TAU : angle + (Math.random() - 0.5) * spread;
      const v = speed + (Math.random() - 0.5) * 2 * speedRange;
      const l = Math.max(0.05, life + (Math.random() - 0.5) * 2 * lifeRange);
      this.add({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, age: 0, life: l, size: size * (0.7 + Math.random() * 0.6), sizeSpeed, colors, ay, alpha, alphaSpeed, square, spin: Math.random() * TAU });
    }
  }

  /** Wind streaks live in their rectangles and keep flowing. */
  addWind(rect, force) {
    const strength = Math.max(1, Math.hypot(force.x, force.y));
    const angle = Math.atan2(force.y, force.x);
    const along = Math.abs(Math.cos(angle)) * rect.w + Math.abs(Math.sin(angle)) * rect.h;
    const life = Math.max(0.6, along / (strength * 0.9));
    const w = { rect, angle, strength, life, rate: Math.max(6, (rect.w * rect.h) / 2600), acc: 0, streaks: [] };
    // Pre-warm so the wind is already flowing.
    for (let t = 0; t < life; t += 1 / 30) this.stepWind(w, 1 / 30);
    this.winds.push(w);
  }

  stepWind(w, dt) {
    w.acc += w.rate * dt;
    while (w.acc >= 1) {
      w.acc -= 1;
      const l = w.life * (1 + (Math.random() - 0.5) * 0.6);
      const v = w.strength * 0.9 + (Math.random() - 0.5) * 2 * w.strength * 0.25;
      w.streaks.push({
        x: w.rect.x + Math.random() * w.rect.w, y: w.rect.y + Math.random() * w.rect.h,
        vx: Math.cos(w.angle) * v, vy: Math.sin(w.angle) * v, age: 0, life: l, len: 25 * (0.7 + Math.random() * 0.8),
      });
    }
    for (const s of w.streaks) {
      s.age += dt;
      s.x += s.vx * dt;
      s.y += s.vy * dt;
    }
    w.streaks = w.streaks.filter((s) => s.age < s.life);
  }

  step(dt) {
    for (const w of this.winds) this.stepWind(w, dt);
    for (const p of this.list) {
      p.age += dt;
      p.vy += p.ay * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.spin += 4 * dt;
    }
    this.list = this.list.filter((p) => p.age < p.life);
  }

  draw(ctx) {
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.lineCap = 'round';
    for (const w of this.winds) {
      const dx = Math.cos(w.angle), dy = Math.sin(w.angle);
      ctx.strokeStyle = Palette.wind;
      ctx.lineWidth = 2.6;
      for (const s of w.streaks) {
        const k = s.age / s.life;
        const a = k < 0.2 ? (k / 0.2) * 0.45 : k > 0.8 ? ((1 - k) / 0.2) * 0.45 : 0.45;
        ctx.globalAlpha = a;
        ctx.beginPath();
        ctx.moveTo(s.x - (dx * s.len) / 2, s.y - (dy * s.len) / 2);
        ctx.lineTo(s.x + (dx * s.len) / 2, s.y + (dy * s.len) / 2);
        ctx.stroke();
      }
    }
    for (const p of this.list) {
      const k = p.age / p.life;
      const colors = p.colors;
      const color = colors[Math.min(colors.length - 1, Math.floor(k * colors.length))];
      const alpha = Math.max(0, Math.min(1, p.alpha + p.alphaSpeed * p.age));
      if (alpha <= 0) continue;
      ctx.globalAlpha = alpha;
      const size = Math.max(0.5, p.size + p.sizeSpeed * p.age * 32);
      if (p.square) {
        ctx.save();
        ctx.globalCompositeOperation = 'source-over';
        ctx.translate(p.x, p.y);
        ctx.rotate(p.spin);
        ctx.fillStyle = color;
        ctx.fillRect(-size / 2, -size / 4, size, size / 2);
        ctx.restore();
      } else {
        drawGlow(ctx, p.x, p.y, size / 2, color);
      }
    }
    ctx.restore();
  }
}

// ---- Parallax star field (screen space)

export class Starfield {
  layout(w, h, tint) {
    this.w = Math.max(1, w);
    this.h = Math.max(1, h);
    let seed = 7;
    const rnd = () => {
      seed = (seed * 16807) % 2147483647;
      return seed / 2147483647;
    };
    const count = Math.floor((this.w * this.h) / 2600);
    const sizes = [2.2, 3.4, 5.0], alphas = [0.35, 0.55, 0.8], factors = [0.04, 0.1, 0.2];
    this.stars = [];
    for (let i = 0; i < count; i++) {
      const layer = i % 3;
      this.stars.push({
        x: rnd() * this.w, y: rnd() * this.h,
        size: sizes[layer] * (0.7 + rnd() * 0.6),
        alpha: alphas[layer] * (0.6 + rnd() * 0.4),
        factor: factors[layer],
        color: rnd() < 0.25 ? lighter(tint, 0.5) : '#FFFFFF',
        twinkle: rnd() < 0.2 ? 0.8 + rnd() * 1.4 : 0,
      });
    }
  }

  draw(ctx, camX, camY, scale, t) {
    if (!this.stars) return;
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    const inv = 1 / Math.max(scale, 0.01);
    for (const s of this.stars) {
      let x = (s.x - camX * s.factor * inv) % this.w;
      let y = (s.y + camY * s.factor * inv) % this.h;
      if (x < 0) x += this.w;
      if (y < 0) y += this.h;
      let a = s.alpha;
      if (s.twinkle) a *= 0.65 + 0.35 * Math.cos((t * Math.PI) / s.twinkle);
      ctx.globalAlpha = a;
      drawGlow(ctx, x, y, s.size / 2, s.color);
    }
    ctx.restore();
  }
}
