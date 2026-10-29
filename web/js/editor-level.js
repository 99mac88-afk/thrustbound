// Level-maker levels. The JSON format is shared with the iPhone app
// (Thrustbound/Maker/EditorLevel.swift), so levels published from either play on both.

export const NARROW_COLS = 14;
export const WIDE_COLS = 28;
export const MIN_ROWS = 20;
export const MAX_ROWS = 120;
export const MAX_ITEMS = 160;
export const FUEL_MIN = 5;
export const FUEL_MAX = 90;
export const ITEM_KINDS = ['star', 'fuel', 'spikes', 'mine', 'movingMine', 'spinner', 'laser', 'wind', 'key', 'door'];

const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);
const isInt = (v) => Number.isInteger(v);

export function newUUID() {
  if (globalThis.crypto && typeof globalThis.crypto.randomUUID === 'function') return globalThis.crypto.randomUUID().toUpperCase();
  const b = new Uint8Array(16);
  if (globalThis.crypto && globalThis.crypto.getRandomValues) globalThis.crypto.getRandomValues(b);
  else for (let i = 0; i < 16; i++) b[i] = Math.floor(Math.random() * 256);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`.toUpperCase();
}

const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

export function createLevel(name, cols = NARROW_COLS, rows = 40, theme = 0) {
  const l = {
    id: newUUID(), version: 1, name, cols, rows,
    rock: new Uint8Array(cols * rows), fuel: 25, theme,
    start: null, goal: null, items: [], clearTime: null,
    updatedAt: null, clearedHash: null, publishedID: null, publishedHash: null,
  };
  for (let c = 0; c < cols; c++) l.rock[c] = 1; // a floor to land on
  return l;
}

export function cloneLevel(l) {
  return {
    ...l,
    rock: new Uint8Array(l.rock),
    start: l.start ? { ...l.start } : null,
    goal: l.goal ? { ...l.goal } : null,
    items: l.items.map((i) => ({ ...i })),
  };
}

function decodeItem(o) {
  if (!o || typeof o !== 'object' || !ITEM_KINDS.includes(o.kind) || !isInt(o.c) || !isInt(o.r)) return null;
  const item = {
    kind: o.kind, c: o.c, r: o.r,
    dir: isInt(o.dir) ? o.dir : 0,
    color: isInt(o.color) ? o.color : 0,
    size: isInt(o.size) ? o.size : 3,
  };
  if (isInt(o.c2)) item.c2 = o.c2;
  if (isInt(o.r2)) item.r2 = o.r2;
  return item;
}

function decodeCell(o) {
  return o && isInt(o.c) && isInt(o.r) ? { c: o.c, r: o.r } : null;
}

/** Tolerant decoding, mirroring EditorLevel.init(from:) in Swift. Throws on unusable data. */
export function decodeLevel(o) {
  if (!o || typeof o !== 'object' || !isInt(o.cols) || !isInt(o.rows)) throw new Error('bad level');
  const cols = o.cols === WIDE_COLS ? WIDE_COLS : NARROW_COLS;
  const rows = clamp(o.rows, MIN_ROWS, MAX_ROWS);
  const rock = new Uint8Array(cols * rows);
  const text = typeof o.rock === 'string' ? o.rock : '';
  if (o.cols === cols && o.rows === rows && text.length === cols * rows) {
    for (let i = 0; i < text.length; i++) if (text.charCodeAt(i) === 49) rock[i] = 1;
  }
  const fuel = typeof o.fuel === 'number' && isFinite(o.fuel) ? o.fuel : 25;
  const items = Array.isArray(o.items) ? o.items.map(decodeItem).filter(Boolean).slice(0, MAX_ITEMS) : [];
  return {
    id: typeof o.id === 'string' && UUID_RE.test(o.id) ? o.id.toUpperCase() : newUUID(),
    version: isInt(o.version) ? o.version : 1,
    name: typeof o.name === 'string' ? o.name : 'Untitled',
    cols, rows, rock,
    fuel: clamp(fuel, FUEL_MIN, FUEL_MAX),
    theme: isInt(o.theme) ? o.theme : 0,
    start: decodeCell(o.start),
    goal: decodeCell(o.goal),
    items,
    clearTime: typeof o.clearTime === 'number' && isFinite(o.clearTime) ? o.clearTime : null,
    updatedAt: typeof o.updatedAt === 'number' ? o.updatedAt : null,
    clearedHash: typeof o.clearedHash === 'string' ? o.clearedHash : null,
    publishedID: typeof o.publishedID === 'string' ? o.publishedID : null,
    publishedHash: typeof o.publishedHash === 'string' ? o.publishedHash : null,
  };
}

function rockString(l) {
  let s = '';
  for (let i = 0; i < l.rock.length; i++) s += l.rock[i] === 1 ? '1' : '0';
  return s;
}

/** JSON object. With local=false it is the published form (no local bookkeeping). */
export function encodeLevel(l, local = true) {
  const o = {
    id: l.id, version: l.version, name: l.name, cols: l.cols, rows: l.rows,
    rock: rockString(l), fuel: l.fuel, theme: l.theme,
  };
  if (l.start) o.start = { c: l.start.c, r: l.start.r };
  if (l.goal) o.goal = { c: l.goal.c, r: l.goal.r };
  o.items = l.items.map((i) => {
    const it = { kind: i.kind, c: i.c, r: i.r, dir: i.dir, color: i.color, size: i.size };
    if (isInt(i.c2)) it.c2 = i.c2;
    if (isInt(i.r2)) it.r2 = i.r2;
    return it;
  });
  if (l.clearTime !== null && l.clearTime !== undefined) o.clearTime = l.clearTime;
  if (local) {
    if (l.updatedAt !== null) o.updatedAt = l.updatedAt;
    if (l.clearedHash !== null) o.clearedHash = l.clearedHash;
    if (l.publishedID !== null) o.publishedID = l.publishedID;
    if (l.publishedHash !== null) o.publishedHash = l.publishedHash;
  }
  return o;
}

// ---- grid access

export const inBounds = (l, c, r) => c >= 0 && c < l.cols && r >= 0 && r < l.rows;
/** Outside the grid counts as rock. */
export const isRock = (l, c, r) => !inBounds(l, c, r) || l.rock[r * l.cols + c] === 1;
export function setRock(l, c, r, value) {
  if (inBounds(l, c, r)) l.rock[r * l.cols + c] = value ? 1 : 0;
}
export const itemIndexAt = (l, c, r) => l.items.findIndex((i) => i.c === c && i.r === r);

export const padCells = (cell) => [cell, { c: cell.c + 1, r: cell.r }, { c: cell.c, r: cell.r + 1 }, { c: cell.c + 1, r: cell.r + 1 }];

/** Pads sit on two cells of rock and need two clear cells above. */
export function padFits(l, cell) {
  if (!inBounds(l, cell.c, cell.r) || !inBounds(l, cell.c + 1, cell.r + 1)) return false;
  if (!isRock(l, cell.c, cell.r - 1) || !isRock(l, cell.c + 1, cell.r - 1) || cell.r < 1) return false;
  return padCells(cell).every((p) => !isRock(l, p.c, p.r));
}

export function isPadCell(l, cell) {
  for (const pad of [l.start, l.goal]) {
    if (pad && padCells(pad).some((p) => p.c === cell.c && p.r === cell.r)) return true;
  }
  return false;
}

/** Resize keeping everything that still fits (anchored at the bottom left). */
export function resize(l, newCols, newRows) {
  const nc = newCols === WIDE_COLS ? WIDE_COLS : NARROW_COLS;
  const nr = clamp(newRows, MIN_ROWS, MAX_ROWS);
  const cells = new Uint8Array(nc * nr);
  for (let r = 0; r < Math.min(l.rows, nr); r++) {
    for (let c = 0; c < Math.min(l.cols, nc); c++) cells[r * nc + c] = l.rock[r * l.cols + c];
  }
  l.cols = nc;
  l.rows = nr;
  l.rock = cells;
  const fits = (c, r) => c >= 0 && c < nc && r >= 0 && r < nr;
  l.items = l.items.filter((i) => fits(i.c, i.r) && (!isInt(i.c2) || fits(i.c2, i.r2 ?? 0)));
  if (l.start && !fits(l.start.c + 1, l.start.r + 1)) l.start = null;
  if (l.goal && !fits(l.goal.c + 1, l.goal.r + 1)) l.goal = null;
}

/** Changes whenever anything that affects play changes (local bookkeeping only). */
export function contentHash(l) {
  let text = `v${l.version};${l.cols}x${l.rows};fuel=${Math.trunc(l.fuel * 10)};` + rockString(l);
  text += `;s=${l.start ? `${l.start.c},${l.start.r}` : '-'};g=${l.goal ? `${l.goal.c},${l.goal.r}` : '-'};`;
  for (const i of l.items) text += `${i.kind}:${i.c},${i.r},${i.dir},${i.color},${i.size},${i.c2 ?? -1},${i.r2 ?? -1};`;
  // 53-bit FNV-style hash, twice with different seeds.
  const h = (seed) => {
    let h1 = 0xdeadbeef ^ seed, h2 = 0x41c6ce57 ^ seed;
    for (let i = 0; i < text.length; i++) {
      const ch = text.charCodeAt(i);
      h1 = Math.imul(h1 ^ ch, 2654435761);
      h2 = Math.imul(h2 ^ ch, 1597334677);
    }
    h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
    h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
    return (4294967296 * (2097151 & h2) + (h1 >>> 0)).toString(16).padStart(14, '0');
  };
  return h(1) + h(2);
}

export const isCleared = (l) => l.clearedHash !== null && l.clearedHash === contentHash(l);
export const isPublishedAsIs = (l) => l.publishedID !== null && l.publishedHash === contentHash(l);

export function markCleared(l, hash, time) {
  if (contentHash(l) !== hash) return;
  if (l.clearedHash === hash && l.clearTime !== null) l.clearTime = Math.min(l.clearTime, time);
  else l.clearTime = time;
  l.clearedHash = hash;
}

export const SAMPLE_NAME = 'Example Cave';

/** A small finished level that shows off most tools (same as LevelStore.sample in Swift). */
export function sampleLevel(theme, name = SAMPLE_NAME) {
  const l = createLevel(name, NARROW_COLS, 30, theme);
  const rock = (c0, c1, r) => { for (let c = c0; c <= c1; c++) setRock(l, c, r, true); };
  rock(0, 8, 8); rock(0, 8, 9); rock(5, 13, 16); rock(5, 13, 17); rock(8, 13, 25); rock(0, 1, 20); rock(12, 13, 20);
  l.start = { c: 1, r: 1 };
  l.goal = { c: 10, r: 26 };
  l.fuel = 30;
  const it = (kind, c, r, extra = {}) => ({ kind, c, r, dir: 0, color: 0, size: 3, ...extra });
  l.items = [
    it('spikes', 5, 1), it('spikes', 6, 1), it('spikes', 7, 1), it('star', 11, 4), it('fuel', 2, 12),
    it('movingMine', 6, 12, { c2: 12, r2: 12 }), it('wind', 11, 10), it('wind', 12, 10), it('star', 2, 18),
    it('laser', 6, 21), it('spinner', 4, 24, { size: 2 }), it('star', 1, 27),
  ];
  return l;
}
