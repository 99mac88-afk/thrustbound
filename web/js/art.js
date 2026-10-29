// Colours and vector art shared by the game and the level maker (port of Art.swift).

export const Palette = {
  hazard: '#FF2E4D',
  hazardCore: '#FFD1D8',
  goal: '#44FF88',
  star: '#FFE14D',
  fuel: '#FFB020',
  wind: '#8FD3FF',
  keyColors: ['#FFC23D', '#2EF0E0', '#FF6AD5'],
  hull: '#EEF3FB',
  hullShade: '#9DB0C9',
  rocketRed: '#FF4D5E',
  window: '#6FD8FF',
  metal: '#3B4659',
};

export const keyColor = (i) => Palette.keyColors[((i % 3) + 3) % 3];

export function theme(world) {
  return {
    neon: world?.neon ?? '#3BE3FF',
    rock: world?.rock ?? '#0E2233',
    bgTop: world?.bgTop ?? '#03070F',
    bgBottom: world?.bgBottom ?? '#0A1C30',
  };
}

export function hexRGB(hex) {
  const s = hex.replace('#', '');
  const v = parseInt(s.length === 3 ? s.split('').map((c) => c + c).join('') : s, 16) || 0;
  return [(v >> 16) & 255, (v >> 8) & 255, v & 255];
}

export function rgba(hex, a) {
  const [r, g, b] = hexRGB(hex);
  return `rgba(${r},${g},${b},${a})`;
}

export function lighter(hex, amount) {
  const [r, g, b] = hexRGB(hex);
  const f = (c) => Math.round(c + (255 - c) * amount);
  return `rgb(${f(r)},${f(g)},${f(b)})`;
}

// ---- Rocket (rocket space: nose up, y up, about 40 pt tall)

function rocketPaths() {
  const hull = new Path2D();
  hull.moveTo(0, 20);
  hull.quadraticCurveTo(8, 14, 8, 4);
  hull.lineTo(8, -12);
  hull.lineTo(-8, -12);
  hull.lineTo(-8, 4);
  hull.quadraticCurveTo(-8, 14, 0, 20);
  hull.closePath();

  const nose = new Path2D();
  nose.moveTo(0, 20);
  nose.quadraticCurveTo(6.2, 16, 6.6, 10);
  nose.lineTo(-6.6, 10);
  nose.quadraticCurveTo(-6.2, 16, 0, 20);
  nose.closePath();

  const fins = new Path2D();
  for (const s of [-1, 1]) {
    fins.moveTo(s * 8, -1);
    fins.lineTo(s * 13, -12);
    fins.lineTo(s * 13, -20);
    fins.lineTo(s * 10, -20);
    fins.lineTo(s * 8, -13);
    fins.closePath();
  }

  const stripe = new Path2D();
  stripe.rect(-8, -9, 16, 3);

  const nozzle = new Path2D();
  nozzle.moveTo(-5, -12);
  nozzle.lineTo(5, -12);
  nozzle.lineTo(6.5, -16);
  nozzle.lineTo(-6.5, -16);
  nozzle.closePath();

  const window = new Path2D();
  window.arc(0, 3, 3.6, 0, Math.PI * 2);
  return { hull, nose, fins, stripe, nozzle, window };
}

export function flamePath(length, width) {
  const p = new Path2D();
  p.moveTo(-width / 2, 0);
  p.quadraticCurveTo(-width / 2, -length * 0.55, 0, -length);
  p.quadraticCurveTo(width / 2, -length * 0.55, width / 2, 0);
  p.closePath();
  return p;
}

let rocketCache = null;
export const rocket = () => (rocketCache ??= rocketPaths());

/** Draws the rocket in rocket space (the caller has set up position and rotation). */
export function drawRocket(ctx, flame = 0) {
  const r = rocket();
  if (flame > 0.01) {
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.globalAlpha = 0.55 * flame;
    drawGlow(ctx, 0, -22, 26, '#FF9A3D');
    ctx.globalAlpha = flame;
    ctx.translate(0, -15);
    ctx.save();
    ctx.scale(0.75 + 0.25 * flame, Math.max(0.001, flame * (0.82 + Math.random() * 0.36)));
    ctx.fillStyle = '#FF7A2E';
    ctx.fill(flamePath(24, 10));
    ctx.restore();
    ctx.scale(1, Math.max(0.001, flame * (0.85 + Math.random() * 0.3)));
    ctx.fillStyle = '#FFF4B0';
    ctx.fill(flamePath(13, 6));
    ctx.restore();
  }
  ctx.lineJoin = 'round';
  ctx.fillStyle = Palette.rocketRed;
  ctx.fill(r.fins);
  ctx.strokeStyle = lighter(Palette.rocketRed, 0.3);
  ctx.lineWidth = 1;
  ctx.stroke(r.fins);
  ctx.fillStyle = Palette.metal;
  ctx.fill(r.nozzle);
  ctx.strokeStyle = '#788499';
  ctx.stroke(r.nozzle);
  ctx.fillStyle = Palette.hull;
  ctx.fill(r.hull);
  ctx.strokeStyle = Palette.hullShade;
  ctx.lineWidth = 1.2;
  ctx.stroke(r.hull);
  ctx.fillStyle = Palette.rocketRed;
  ctx.fill(r.stripe);
  ctx.fill(r.nose);
  ctx.fillStyle = Palette.window;
  ctx.fill(r.window);
  ctx.strokeStyle = '#FFFFFF';
  ctx.stroke(r.window);
}

// ---- Shapes

export function starPath(outer, inner) {
  const p = new Path2D();
  for (let i = 0; i < 10; i++) {
    const r = i % 2 === 0 ? outer : inner;
    const a = Math.PI / 2 + (i * Math.PI) / 5;
    if (i === 0) p.moveTo(Math.cos(a) * r, Math.sin(a) * r);
    else p.lineTo(Math.cos(a) * r, Math.sin(a) * r);
  }
  p.closePath();
  return p;
}

export function keyPath() {
  const p = new Path2D();
  p.ellipse(-6, 0, 5, 5, 0, 0, Math.PI * 2);
  p.rect(-2, -1.5, 13, 3);
  p.rect(6, -6, 2.5, 5);
  p.rect(9.5, -5, 2.5, 4);
  return p;
}

export function minePath(r) {
  const p = new Path2D();
  for (let i = 0; i < 16; i++) {
    const a = (i * Math.PI) / 8;
    const rr = i % 2 === 0 ? r * 1.32 : r * 0.88;
    if (i === 0) p.moveTo(Math.cos(a) * rr, Math.sin(a) * rr);
    else p.lineTo(Math.cos(a) * rr, Math.sin(a) * rr);
  }
  p.closePath();
  return p;
}

// ---- Soft glow sprites (radial gradients, cached per colour)

const glowCache = new Map();
function glowSprite(color) {
  let c = glowCache.get(color);
  if (!c) {
    c = typeof OffscreenCanvas !== 'undefined' ? new OffscreenCanvas(64, 64) : Object.assign(document.createElement('canvas'), { width: 64, height: 64 });
    const g = c.getContext('2d');
    const grad = g.createRadialGradient(32, 32, 0, 32, 32, 32);
    grad.addColorStop(0, rgba(color, 1));
    grad.addColorStop(0.35, rgba(color, 0.45));
    grad.addColorStop(1, rgba(color, 0));
    g.fillStyle = grad;
    g.fillRect(0, 0, 64, 64);
    glowCache.set(color, c);
  }
  return c;
}

/** A soft dot of the given radius centred at (x, y). Use with 'lighter' compositing. */
export function drawGlow(ctx, x, y, radius, color) {
  ctx.drawImage(glowSprite(color), x - radius, y - radius, radius * 2, radius * 2);
}
