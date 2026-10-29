// Ports of ThrustboundTests.swift so the web game behaves like the iPhone app.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { GameWorld, Physics, RocketShape } from '../js/physics.js';
import { parseLibrary } from '../js/levels.js';

const lib = parseLibrary(JSON.parse(readFileSync(new URL('../../Thrustbound/Resources/levels.json', import.meta.url))));
const levels = lib.levels;
const byName = (n) => {
  const l = levels.find((x) => x.name === n);
  assert.ok(l, `missing level ${n}`);
  return l;
};
const run = (w, seconds, input = { thrust: false, targetAngle: null }, stop = null) => {
  for (let t = 0; t < seconds; t += Physics.step) {
    w.step(Physics.step, input);
    if (stop && stop(w)) return;
  }
};
const close = (a, b, eps, msg) => assert.ok(Math.abs(a - b) <= eps, `${msg ?? ''} ${a} vs ${b}`);

test('all levels load', () => {
  assert.equal(levels.length, 80);
  assert.equal(lib.worlds.length, 8);
  assert.equal(new Set(levels.map((l) => l.id)).size, 80);
  for (const l of levels) {
    assert.equal(l.stars.length, 3, l.name);
    assert.ok(l.terrain.length > 0 && l.fuel > 0 && l.par > 0 && l.width >= 420, l.name);
    for (const d of l.doors) assert.ok(l.keys.some((k) => k.color === d.color), `${l.name}: door without key`);
  }
});

test('rocket rests safely on every launch pad', () => {
  for (const l of levels) {
    const w = new GameWorld(l);
    run(w, 6);
    assert.equal(w.status, 'flying', `${l.name}: did not survive sitting on the pad`);
    close(w.position.y, l.start.y + RocketShape.spawnHeight, 1.5, l.name);
    close(w.position.x, l.start.x, 1.5, l.name);
    close(w.fuel, l.fuel, 1e-4, `${l.name}: fuel used without input`);
    assert.equal(w.started, false);
  }
});

test('thrust lifts off and burns fuel', () => {
  const l = byName('First Flight');
  const w = new GameWorld(l);
  run(w, 1, { thrust: true, targetAngle: null });
  assert.ok(w.position.y > l.start.y + RocketShape.spawnHeight + 20);
  assert.ok(w.fuel < l.fuel);
  assert.ok(w.started);
});

test('steering points the nose', () => {
  const w = new GameWorld(byName('First Flight'));
  run(w, 0.5, { thrust: false, targetAngle: 1.0 });
  close(w.angle, 1.0, 0.01);
});

test('hard impact crashes, gentle touchdown on the goal wins', () => {
  const l = byName('First Flight');
  const w = new GameWorld(l);
  w.place({ x: l.start.x, y: l.start.y + 200 }, { x: 0, y: -300 });
  run(w, 2, undefined, (x) => x.status !== 'flying');
  assert.equal(w.status, 'crashed');
  const g = new GameWorld(l);
  g.place({ x: l.goal.x, y: l.goal.y + RocketShape.spawnHeight + 8 });
  run(g, 3, undefined, (x) => x.status !== 'flying');
  assert.equal(g.status, 'landed');
  const t = new GameWorld(l);
  t.place({ x: l.goal.x, y: l.goal.y + RocketShape.spawnHeight + 4 }, { x: 0, y: 0 }, 0.6);
  run(t, 3);
  assert.notEqual(t.status, 'landed');
});

test('fuel cans refill up to the tank size', () => {
  const l = levels.find((x) => x.cans.length > 0);
  const w = new GameWorld(l);
  w.fuel = 1;
  w.place(l.cans[0]);
  w.step(Physics.step, { thrust: false, targetAngle: null });
  close(w.fuel, Math.min(l.fuel, 1 + Physics.canFuel), 0.01);
});

test('mines, spikes and lasers destroy the rocket', () => {
  const lm = levels.find((x) => x.mines.length > 0);
  const m = new GameWorld(lm);
  m.place(m.minePosition(0));
  m.step(Physics.step, { thrust: false, targetAngle: null });
  assert.equal(m.status, 'crashed');
  const ls = levels.find((x) => x.spikes.length > 0);
  const s = new GameWorld(ls);
  const tri = ls.spikes[0];
  s.place({ x: (tri[0].x + tri[1].x + tri[2].x) / 3, y: (tri[0].y + tri[1].y + tri[2].y) / 3 });
  s.step(Physics.step, { thrust: false, targetAngle: null });
  assert.equal(s.status, 'crashed');
});

test('a key opens its doors, closed doors are solid', () => {
  const l = levels.find((x) => x.doors.length > 0);
  const w = new GameWorld(l);
  const door = l.doors[0];
  const key = l.keys.findIndex((k) => k.color === door.color);
  w.place(l.keys[key].position);
  w.step(Physics.step, { thrust: false, targetAngle: null });
  assert.ok(w.collectedKeys.has(key));
  assert.ok(w.openDoors.has(0));
});

test('lasers cycle on, warning and off', () => {
  const l = levels.find((x) => x.lasers.length > 0 && x.lasers[0].off > 0);
  const w = new GameWorld(l);
  const seen = new Set();
  for (let t = 0; t < 6; t += 0.05) {
    w.time = t;
    seen.add(w.laserState(0));
  }
  assert.deepEqual([...seen].sort(), ['off', 'on', 'warning']);
});

test('running dry while resting is detected', () => {
  const l = byName('First Flight');
  const w = new GameWorld(l);
  w.fuel = 0;
  run(w, 3);
  assert.equal(w.status, 'outOfFuel');
});
