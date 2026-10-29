// Reads levels.json (the same file the iPhone app ships) into plain objects.

const P = (a) => ({ x: a && a.length > 0 ? a[0] : 0, y: a && a.length > 1 ? a[1] : 0 });
const rect = (a) => (a && a.length >= 4 ? { x: a[0], y: a[1], w: a[2], h: a[3] } : { x: 0, y: 0, w: 0, h: 0 });
const pad = (a) => ({ x: a.length > 0 ? a[0] : 0, y: a.length > 1 ? a[1] : 0, width: a.length > 2 ? a[2] : 64 });

export function parseLevel(raw) {
  return {
    id: raw.id,
    world: raw.world,
    name: raw.name,
    hint: raw.hint,
    nameRu: raw.nameRu ?? null,
    hintRu: raw.hintRu ?? null,
    width: raw.size && raw.size.length > 0 ? raw.size[0] : 420,
    height: raw.size && raw.size.length > 1 ? raw.size[1] : 1000,
    fuel: raw.fuel,
    par: raw.par,
    start: pad(raw.start),
    goal: pad(raw.goal),
    terrain: raw.terrain.map((poly) => poly.map((ring) => ring.map(P))),
    stars: raw.stars.map(P),
    cans: raw.cans.map(P),
    spikes: raw.spikes.map((tri) => tri.map(P)),
    mines: raw.mines.map((m) => ({ radius: m.r, path: m.path.map(P), speed: m.speed, loop: m.loop })),
    spinners: raw.spinners.map((s) => ({ center: P(s.c), length: s.len, arms: Math.max(1, s.arms), speed: s.speed, phase: s.phase })),
    lasers: raw.lasers.map((l) => ({ a: P(l.a), b: P(l.b), on: l.on, off: l.off, phase: l.phase })),
    winds: raw.winds.map((w) => ({ rect: rect(w.rect), force: P(w.force) })),
    keys: raw.keys.map((k) => ({ position: P(k.p), color: k.color })),
    doors: raw.doors.map((d) => ({ rect: rect(d.rect), color: d.color })),
  };
}

export function parseLibrary(json) {
  return { worlds: json.worlds, levels: json.levels.map(parseLevel) };
}
