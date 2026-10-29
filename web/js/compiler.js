// Turns a level-maker grid into a playable level (port of LevelCompiler.swift).
import { FUEL_MAX, FUEL_MIN, inBounds, isRock, padCells, padFits } from './editor-level.js';

export const CELL = 30;
export const PAD_WIDTH = CELL * 2 - 4;

/** Reasons the level can't be played yet (empty means playable). */
export function problems(e) {
  const list = [];
  if (e.start) { if (!padFits(e, e.start)) list.push('startBlocked'); } else list.push('noStart');
  if (e.goal) { if (!padFits(e, e.goal)) list.push('goalBlocked'); } else list.push('noGoal');
  if (e.start && e.goal) {
    const a = padCells(e.start).map((p) => `${p.c},${p.r}`);
    if (padCells(e.goal).some((p) => a.includes(`${p.c},${p.r}`))) list.push('padsOverlap');
  }
  return list;
}

export function compile(e, { worldCount = 8, title = null, withTerrain = true } = {}) {
  const s = CELL;
  const width = e.cols * s;
  const height = e.rows * s;
  const center = (c, r) => ({ x: (c + 0.5) * s, y: (r + 0.5) * s });
  const pad = (p) => (p ? { x: (p.c + 1) * s, y: p.r * s, width: PAD_WIDTH } : { x: -9999, y: -9999, width: PAD_WIDTH });
  const free = (c, r) => inBounds(e, c, r) && !isRock(e, c, r);
  const clampColor = (v) => Math.min(Math.max(v, 0), 2);

  const stars = [], cans = [], spikes = [], mines = [], spinners = [], lasers = [], winds = [], keys = [], doors = [];

  for (const item of e.items) {
    if (!free(item.c, item.r)) continue;
    const p = center(item.c, item.r);
    const x0 = item.c * s, y0 = item.r * s;
    switch (item.kind) {
      case 'star':
        if (stars.length < 3) stars.push(p);
        break;
      case 'fuel':
        cans.push(p);
        break;
      case 'key':
        keys.push({ position: p, color: clampColor(item.color) });
        break;
      case 'door':
        doors.push({ rect: { x: x0, y: y0, w: s, h: s }, color: clampColor(item.color) });
        break;
      case 'mine':
        mines.push({ radius: 12, path: [p], speed: 0, loop: false });
        break;
      case 'movingMine':
        if (Number.isInteger(item.c2) && Number.isInteger(item.r2) && free(item.c2, item.r2) && (item.c2 !== item.c || item.r2 !== item.r)) {
          mines.push({ radius: 12, path: [p, center(item.c2, item.r2)], speed: 90, loop: false });
        } else {
          mines.push({ radius: 12, path: [p], speed: 0, loop: false });
        }
        break;
      case 'spinner': {
        const length = Math.min(Math.max(item.size, 2), 4) * s - 8;
        spinners.push({ center: p, length, arms: 2, speed: item.dir === 1 ? -1.3 : 1.3, phase: 0 });
        break;
      }
      case 'laser': {
        const phase = (lasers.length * 0.7) % 2.8;
        if (item.dir === 1) {
          let r0 = item.r, r1 = item.r;
          while (free(item.c, r0 - 1)) r0--;
          while (free(item.c, r1 + 1)) r1++;
          lasers.push({ a: { x: p.x, y: r0 * s - 4 }, b: { x: p.x, y: (r1 + 1) * s + 4 }, on: 1.2, off: 1.6, phase });
        } else {
          let c0 = item.c, c1 = item.c;
          while (free(c0 - 1, item.r)) c0--;
          while (free(c1 + 1, item.r)) c1++;
          lasers.push({ a: { x: c0 * s - 4, y: p.y }, b: { x: (c1 + 1) * s + 4, y: p.y }, on: 1.2, off: 1.6, phase });
        }
        break;
      }
      case 'wind': {
        const force = item.dir === 1 ? { x: 220, y: 0 } : item.dir === 2 ? { x: 0, y: -220 } : item.dir === 3 ? { x: -220, y: 0 } : { x: 0, y: 220 };
        winds.push({ rect: { x: x0, y: y0, w: s, h: s }, force });
        break;
      }
      case 'spikes': {
        const w = s / 2, h = 14;
        for (let k = 0; k < 2; k++) {
          const o = k * w;
          if (item.dir === 2) {
            const y = y0 + s;
            spikes.push([{ x: x0 + o + w, y }, { x: x0 + o, y }, { x: x0 + o + w / 2, y: y - h }]);
          } else if (item.dir === 1) {
            spikes.push([{ x: x0, y: y0 + o + w }, { x: x0, y: y0 + o }, { x: x0 + h, y: y0 + o + w / 2 }]);
          } else if (item.dir === 3) {
            const x = x0 + s;
            spikes.push([{ x, y: y0 + o }, { x, y: y0 + o + w }, { x: x - h, y: y0 + o + w / 2 }]);
          } else {
            spikes.push([{ x: x0 + o, y: y0 }, { x: x0 + o + w, y: y0 }, { x: x0 + o + w / 2, y: y0 + h }]);
          }
        }
        break;
      }
      default:
        break;
    }
  }

  const outer = [{ x: -1000, y: -1000 }, { x: width + 1000, y: -1000 }, { x: width + 1000, y: height + 1000 }, { x: -1000, y: height + 1000 }];
  const terrain = withTerrain ? [[outer, ...rockOutlines(e)]] : [];
  const par = e.clearTime !== null && e.clearTime !== undefined ? Math.max(10, Math.ceil(e.clearTime * 1.2)) : 60;

  return {
    id: 0,
    world: Math.min(Math.max(e.theme, 0), Math.max(0, worldCount - 1)),
    name: title ?? e.name,
    hint: '',
    nameRu: null,
    hintRu: null,
    width, height,
    fuel: Math.min(Math.max(e.fuel, FUEL_MIN), FUEL_MAX),
    par,
    start: pad(e.start),
    goal: pad(e.goal),
    terrain, stars, cans, spikes, mines, spinners, lasers, winds, keys, doors,
  };
}

/** Outlines between rock and open cells, traced with rock on the left of every edge. */
export function rockOutlines(e) {
  const outgoing = new Map();
  const order = [];
  const key = (x, y) => x * 100000 + y;
  const add = (ax, ay, bx, by) => {
    const k = key(ax, ay);
    if (!outgoing.has(k)) {
      outgoing.set(k, []);
      order.push([ax, ay]);
    }
    outgoing.get(k).push([bx, by]);
  };
  for (let r = 0; r < e.rows; r++) {
    for (let c = 0; c < e.cols; c++) {
      if (isRock(e, c, r)) continue;
      if (isRock(e, c, r - 1)) add(c + 1, r, c, r);
      if (isRock(e, c, r + 1)) add(c, r + 1, c + 1, r + 1);
      if (isRock(e, c - 1, r)) add(c, r, c, r + 1);
      if (isRock(e, c + 1, r)) add(c + 1, r + 1, c + 1, r);
    }
  }
  const rings = [];
  const limit = e.cols * e.rows * 4 + 16;
  let cursor = 0;
  while (cursor < order.length) {
    const first = order[cursor];
    const outs = outgoing.get(key(first[0], first[1]));
    if (!outs || outs.length === 0) {
      cursor++;
      continue;
    }
    const loop = [first];
    let current = first;
    let steps = 0;
    while (steps < limit) {
      steps++;
      const options = outgoing.get(key(current[0], current[1]));
      if (!options || options.length === 0) break;
      const next = options.pop();
      if (next[0] === first[0] && next[1] === first[1]) break;
      loop.push(next);
      current = next;
    }
    const simplified = dropStraight(loop);
    if (simplified.length >= 3) rings.push(simplified.map(([x, y]) => ({ x: x * CELL, y: y * CELL })));
  }
  return rings;
}

function dropStraight(loop) {
  if (loop.length < 3) return loop;
  const out = [];
  const n = loop.length;
  for (let i = 0; i < n; i++) {
    const a = loop[(i + n - 1) % n], b = loop[i], c = loop[(i + 1) % n];
    const straight = (a[0] === b[0] && b[0] === c[0]) || (a[1] === b[1] && b[1] === c[1]);
    if (!straight) out.push(b);
  }
  return out;
}
