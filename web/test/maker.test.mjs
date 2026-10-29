// Ports of MakerTests.swift: grid model, compiler and shared JSON format.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { GameWorld, Physics, RocketShape } from '../js/physics.js';
import {
  createLevel, decodeLevel, encodeLevel, contentHash, isCleared, markCleared, padFits, resize,
  sampleLevel, setRock, isRock, MAX_ITEMS, MAX_ROWS, FUEL_MAX,
} from '../js/editor-level.js';
import { compile, problems, rockOutlines } from '../js/compiler.js';

const run = (w, seconds) => { for (let t = 0; t < seconds; t += Physics.step) w.step(Physics.step, { thrust: false, targetAngle: null }); };
function basic(cols = 14, rows = 20) {
  const l = createLevel('Test', cols, rows);
  l.start = { c: 1, r: 1 };
  l.goal = { c: cols - 3, r: 1 };
  return l;
}
const area = (ring) => {
  let a = 0;
  for (let i = 0; i < ring.length; i++) {
    const p = ring[i], q = ring[(i + 1) % ring.length];
    a += p.x * q.y - q.x * p.y;
  }
  return a / 2;
};

test('pads need rock below and room above', () => {
  const l = basic();
  assert.ok(padFits(l, { c: 4, r: 1 }));
  assert.ok(!padFits(l, { c: 4, r: 2 }));
  assert.ok(!padFits(l, { c: 13, r: 1 }));
  setRock(l, 5, 2, true);
  assert.ok(!padFits(l, { c: 4, r: 1 }));
});

test('problems', () => {
  const l = createLevel('x');
  assert.deepEqual(problems(l), ['noStart', 'noGoal']);
  l.start = { c: 1, r: 1 };
  l.goal = { c: 2, r: 1 };
  assert.deepEqual(problems(l), ['padsOverlap']);
  l.goal = { c: 8, r: 5 };
  assert.deepEqual(problems(l), ['goalBlocked']);
  l.goal = { c: 8, r: 1 };
  assert.deepEqual(problems(l), []);
});

test('outlines cover exactly the open cells', () => {
  let seed = 42;
  const rnd = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
  for (let trial = 0; trial < 25; trial++) {
    const l = createLevel('r', trial % 2 === 0 ? 14 : 28, 20);
    for (let r = 0; r < l.rows; r++) for (let c = 0; c < l.cols; c++) if (rnd() < 0.45) setRock(l, c, r, true);
    const open = l.rock.reduce((n, v) => n + (v === 0 ? 1 : 0), 0);
    const rings = rockOutlines(l);
    assert.equal(-rings.reduce((s, ring) => s + area(ring), 0), open * 900, `trial ${trial}`);
    for (const ring of rings) for (let i = 0; i < ring.length; i++) {
      const a = ring[i], b = ring[(i + 1) % ring.length];
      assert.ok(a.x === b.x || a.y === b.y);
    }
  }
});

test('compiled geometry, landing and painted rock', () => {
  const l = basic();
  l.fuel = 33;
  l.clearTime = 20;
  const lv = compile(l);
  assert.equal(lv.width, 420);
  assert.equal(lv.height, 600);
  assert.equal(lv.par, 24);
  assert.deepEqual([lv.start.x, lv.start.y, lv.goal.x], [60, 30, 360]);
  assert.equal(lv.terrain[0].length, 2);
  const w = new GameWorld(lv);
  run(w, 5);
  assert.equal(w.status, 'flying');
  const g = new GameWorld(lv);
  g.place({ x: lv.goal.x, y: lv.goal.y + RocketShape.spawnHeight + 4 });
  run(g, 3);
  assert.equal(g.status, 'landed');
  const shelf = basic();
  for (let c = 4; c <= 9; c++) setRock(shelf, c, 8, true);
  const s = new GameWorld(compile(shelf));
  s.place({ x: 6.5 * 30, y: 9 * 30 + 40 });
  run(s, 3);
  assert.equal(s.status, 'flying');
  assert.ok(s.position.y > 270);
});

test('items compile like the iPhone app', () => {
  const l = basic();
  setRock(l, 2, 10, true);
  setRock(l, 11, 10, true);
  const it = (kind, c, r, extra = {}) => ({ kind, c, r, dir: 0, color: 0, size: 3, ...extra });
  l.items = [it('star', 3, 3), it('star', 4, 3), it('star', 5, 3), it('star', 6, 3), it('fuel', 4, 5), it('spikes', 6, 1),
    it('mine', 7, 6), it('movingMine', 3, 7, { c2: 9, r2: 7 }), it('spinner', 6, 14, { dir: 1, size: 2 }), it('laser', 5, 10),
    it('laser', 8, 12, { dir: 1 }), it('wind', 8, 3, { dir: 1 }), it('key', 9, 9, { color: 1 }), it('door', 9, 15, { color: 1 }), it('star', 0, 0)];
  const lv = compile(l);
  assert.equal(lv.stars.length, 3);
  assert.deepEqual(lv.cans, [{ x: 135, y: 165 }]);
  assert.equal(lv.spikes.length, 2);
  assert.equal(lv.spikes[0][0].y, 30);
  assert.deepEqual(lv.mines[1].path, [{ x: 105, y: 225 }, { x: 285, y: 225 }]);
  assert.ok(lv.spinners[0].speed < 0);
  assert.equal(lv.spinners[0].length, 52);
  assert.equal(lv.lasers[0].a.x, 86);
  assert.equal(lv.lasers[0].b.x, 334);
  assert.equal(lv.lasers[1].a.y, 26);
  assert.equal(lv.lasers[1].b.y, 604);
  assert.deepEqual(lv.winds[0].force, { x: 220, y: 0 });
  assert.deepEqual(lv.doors[0].rect, { x: 270, y: 450, w: 30, h: 30 });
  const w = new GameWorld(lv);
  run(w, 2);
  assert.equal(w.status, 'flying');
});

test('shared JSON format: round trip, tolerance and the iPhone encoding', () => {
  const l = basic();
  l.items = [{ kind: 'wind', c: 4, r: 4, dir: 1, color: 0, size: 3 }];
  l.clearTime = 12.5;
  const back = decodeLevel(JSON.parse(JSON.stringify(encodeLevel(l))));
  assert.deepEqual(encodeLevel(back), encodeLevel(l));
  const m = decodeLevel({ cols: 14, rows: 9999, rock: '10', fuel: 1000, items: [{ kind: 'star', c: 1, r: 2 }, { kind: 'nope', c: 1, r: 1 }] });
  assert.equal(m.rows, MAX_ROWS);
  assert.equal(m.rock.length, 14 * MAX_ROWS);
  assert.ok(!m.rock.includes(1));
  assert.equal(m.fuel, FUEL_MAX);
  assert.equal(m.items.length, 1);
  assert.equal(m.name, 'Untitled');
  const many = Array.from({ length: 500 }, (_, r) => ({ kind: 'star', c: 1, r }));
  assert.equal(decodeLevel({ cols: 28, rows: 20, items: many }).items.length, MAX_ITEMS);
  assert.throws(() => decodeLevel({ cols: 'x' }));
  // Published JSON has exactly the keys the Swift decoder knows, and no local bookkeeping.
  l.clearedHash = 'x'; l.publishedID = 'y'; l.publishedHash = 'z'; l.updatedAt = 1;
  const pub = encodeLevel(l, false);
  assert.deepEqual(Object.keys(pub).sort(), ['clearTime', 'cols', 'fuel', 'goal', 'id', 'items', 'name', 'rock', 'rows', 'start', 'theme', 'version']);
  assert.match(pub.id, /^[0-9A-F-]{36}$/);
  // A level as the iPhone app publishes it.
  const ios = decodeLevel({ id: 'E3A998EF-68D6-488F-AEBB-68729FA06E0F', version: 1, name: 'From iOS', cols: 14, rows: 20,
    rock: '1'.repeat(14) + '0'.repeat(14 * 19), fuel: 25, theme: 3, start: { c: 2, r: 1 }, goal: { c: 10, r: 1 },
    items: [{ kind: 'movingMine', c: 3, r: 5, dir: 0, color: 0, size: 3, c2: 8, r2: 5 }], clearTime: 9.5 });
  assert.equal(ios.id, 'E3A998EF-68D6-488F-AEBB-68729FA06E0F');
  assert.deepEqual(problems(ios), []);
  assert.equal(compile(ios).mines[0].speed, 90);
});

test('clearing only counts for the exact layout', () => {
  const l = basic();
  const h = contentHash(l);
  markCleared(l, h, 20);
  assert.ok(isCleared(l));
  markCleared(l, h, 25);
  assert.equal(l.clearTime, 20);
  l.name = 'renamed';
  l.theme = 4;
  assert.ok(isCleared(l), 'name and look do not matter');
  setRock(l, 6, 6, true);
  assert.ok(!isCleared(l));
});

test('resize keeps what fits; sample level is playable', () => {
  const l = basic(28, 40);
  l.items = [{ kind: 'star', c: 5, r: 5, dir: 0, color: 0, size: 3 }, { kind: 'star', c: 20, r: 35, dir: 0, color: 0, size: 3 }];
  resize(l, 14, 20);
  assert.equal(l.cols, 14);
  assert.equal(l.items.length, 1);
  assert.equal(l.goal, null);
  assert.ok(isRock(l, 3, 0));
  const s = sampleLevel(2);
  assert.deepEqual(problems(s), []);
  const lv = compile(s);
  assert.equal(lv.stars.length, 3);
  const w = new GameWorld(lv);
  run(w, 3);
  assert.equal(w.status, 'flying');
});
