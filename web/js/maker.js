// Level maker: saved levels, the editor and its canvas (port of LevelStore / EditorSession / EditorScene / EditorView).
import {
  cloneLevel, contentHash, createLevel, decodeLevel, encodeLevel, inBounds, isCleared, isPadCell, isPublishedAsIs,
  isRock, itemIndexAt, markCleared, newUUID, padCells, padFits, resize, sampleLevel, setRock,
  NARROW_COLS, WIDE_COLS, MIN_ROWS, MAX_ROWS, MAX_ITEMS, FUEL_MIN, FUEL_MAX,
} from './editor-level.js';
import { CELL, compile, problems, rockOutlines } from './compiler.js';
import { Palette, drawRocket, keyColor, theme as makeTheme } from './art.js';
import { drawLevelBack, drawLevelFront, drawTerrain, terrainPath } from './render.js';
import { RocketShape } from './physics.js';
import { storage } from './store.js';
import { dialog, html, onAction, raw, setHTML, sheet } from './dom.js';
import { icon } from './icons.js';
import { haptics, sound } from './audio.js';
import { openAccount } from './community.js';

const LEVELS_KEY = 'tb.levels.v1';

export const TOOLS = ['rock', 'erase', 'hand', 'start', 'goal', 'star', 'fuel', 'spikes', 'mine', 'movingMine', 'spinner', 'laser', 'wind', 'key', 'door'];
const TOOL_ICONS = { rock: 'square', erase: 'eraser', hand: 'hand', start: 'departure', goal: 'checkered', star: 'star', fuel: 'fuel', spikes: 'triangle', mine: 'mine', movingMine: 'patrol', spinner: 'blade', laser: 'laser', wind: 'wind', key: 'key', door: 'door' };
const ITEM_TOOLS = ['star', 'fuel', 'spikes', 'mine', 'movingMine', 'spinner', 'laser', 'wind', 'key', 'door'];
const paints = (tool) => tool === 'rock' || tool === 'erase';

// ---------------------------------------------------------------- store

export class LevelStore {
  constructor() {
    const raw = storage.get(LEVELS_KEY, []);
    this.levels = [];
    for (const o of Array.isArray(raw) ? raw : []) {
      try { this.levels.push(decodeLevel(o)); } catch { /* skip damaged entries */ }
    }
    this.sort();
    this.session = null;
  }

  sort() { this.levels.sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0)); }
  persist() { storage.set(LEVELS_KEY, this.levels.map((l) => encodeLevel(l, true))); }
  level(id) { return this.levels.find((l) => l.id === id) || null; }

  save(level) {
    const copy = cloneLevel(level);
    copy.updatedAt = Date.now();
    const i = this.levels.findIndex((l) => l.id === copy.id);
    if (i >= 0) this.levels[i] = copy; else this.levels.push(copy);
    this.sort();
    this.persist();
  }

  create(name, theme) {
    const l = createLevel(name, NARROW_COLS, 40, theme);
    l.start = { c: 2, r: 1 };
    l.goal = { c: l.cols - 4, r: 1 };
    this.save(l);
    return this.level(l.id);
  }

  addSample(theme, name) {
    const l = sampleLevel(theme, name);
    this.save(l);
    return this.level(l.id);
  }

  duplicate(id, suffix) {
    const src = this.level(id);
    if (!src) return null;
    const copy = cloneLevel(src);
    copy.id = newUUID();
    copy.name = (copy.name + suffix).slice(0, 40);
    copy.publishedID = null;
    copy.publishedHash = null;
    this.save(copy);
    return this.level(copy.id);
  }

  remove(id) {
    this.levels = this.levels.filter((l) => l.id !== id);
    if (this.session && this.session.level.id === id) this.session = null;
    this.persist();
  }

  recordClear(id, hash, time) {
    if (this.session && this.session.level.id === id) {
      markCleared(this.session.level, hash, time);
      this.save(this.session.level);
      return;
    }
    const l = this.level(id);
    if (!l) return;
    markCleared(l, hash, time);
    this.save(l);
  }

  markPublished(id, remoteID, hash) {
    const target = this.session && this.session.level.id === id ? this.session.level : this.level(id);
    if (!target) return;
    target.publishedID = remoteID;
    target.publishedHash = hash;
    this.save(target);
  }

  openSession(id, worlds) {
    if (this.session && this.session.level.id === id) return this.session;
    const l = this.level(id);
    if (!l) return null;
    this.session = new EditorSession(cloneLevel(l), this, worlds);
    return this.session;
  }

  closeSession() {
    if (this.session) this.save(this.session.level);
    this.session = null;
  }
}

// ---------------------------------------------------------------- editing

export class EditorSession {
  constructor(level, store, worlds) {
    this.level = level;
    this.store = store;
    this.worlds = worlds;
    this.tool = 'rock';
    this.windDir = 0;
    this.color = 0;
    this.laserDir = 0;
    this.spinnerSize = 3;
    this.spinnerDir = 0;
    this.pendingMine = null;
    this.notice = null;
    this.undoStack = [];
    this.redoStack = [];
    this.strokeStart = null;
    this.lastPainted = null;
    this.version = 0;
    this.camera = null;
  }

  get canUndo() { return this.undoStack.length > 0; }
  get canRedo() { return this.redoStack.length > 0; }
  changed() { this.version++; }

  setTool(t) {
    this.tool = t;
    if (t !== 'movingMine') this.pendingMine = null;
    this.changed();
  }

  beginStroke() {
    this.strokeStart = cloneLevel(this.level);
    this.lastPainted = null;
  }

  paint(cell) {
    if (!paints(this.tool) || !inBounds(this.level, cell.c, cell.r)) return;
    if (this.lastPainted && this.lastPainted.c === cell.c && this.lastPainted.r === cell.r) return;
    this.lastPainted = cell;
    const l = this.level;
    if (this.tool === 'rock' && isPadCell(l, cell)) return;
    const before = l.items.length;
    const wasRock = isRock(l, cell.c, cell.r);
    l.items = l.items.filter((i) => !(i.c === cell.c && i.r === cell.r));
    setRock(l, cell.c, cell.r, this.tool === 'rock');
    if (before !== l.items.length || wasRock !== (this.tool === 'rock')) this.changed();
  }

  place(cell) {
    if (!inBounds(this.level, cell.c, cell.r)) return;
    if (this.tool === 'start' || this.tool === 'goal') this.placePad(cell, this.tool === 'goal');
    else if (ITEM_TOOLS.includes(this.tool)) this.placeItem(cell);
  }

  endStroke() {
    const before = this.strokeStart;
    this.strokeStart = null;
    this.lastPainted = null;
    if (!before || JSON.stringify(encodeLevel(before)) === JSON.stringify(encodeLevel(this.level))) return;
    this.pushUndo(before);
    this.save();
  }

  cancelStroke() {
    if (this.strokeStart) {
      this.level = this.strokeStart;
      this.changed();
    }
    this.strokeStart = null;
    this.lastPainted = null;
  }

  pushUndo(snapshot) {
    this.undoStack.push(snapshot);
    if (this.undoStack.length > 80) this.undoStack.shift();
    this.redoStack = [];
  }

  keepBookkeeping(snapshot) {
    const l = cloneLevel(snapshot);
    for (const k of ['clearedHash', 'clearTime', 'publishedID', 'publishedHash', 'name']) l[k] = this.level[k];
    return l;
  }

  undo() {
    const prev = this.undoStack.pop();
    if (!prev) return;
    this.redoStack.push(cloneLevel(this.level));
    this.level = this.keepBookkeeping(prev);
    this.pendingMine = null;
    this.changed();
    this.save();
  }

  redo() {
    const next = this.redoStack.pop();
    if (!next) return;
    this.undoStack.push(cloneLevel(this.level));
    this.level = this.keepBookkeeping(next);
    this.pendingMine = null;
    this.changed();
    this.save();
  }

  /** Settings changes (size, fuel, look) are undoable as one step. */
  edit(change) {
    const before = cloneLevel(this.level);
    change(this.level);
    if (JSON.stringify(encodeLevel(before)) === JSON.stringify(encodeLevel(this.level))) return;
    this.pushUndo(before);
    this.pendingMine = null;
    this.changed();
    this.save();
  }

  rename(name) {
    const trimmed = name.trim().slice(0, 40);
    if (!trimmed || trimmed === this.level.name) return;
    this.level.name = trimmed;
    this.changed();
    this.save();
  }

  save() { this.store.save(this.level); }

  say(notice) {
    this.notice = notice;
    this.changed();
  }

  placePad(cell, goal) {
    const l = this.level;
    const other = goal ? l.start : l.goal;
    const candidates = [cell, { c: cell.c, r: cell.r + 1 }, { c: cell.c - 1, r: cell.r }, { c: cell.c - 1, r: cell.r + 1 }, { c: cell.c, r: cell.r - 1 }, { c: cell.c - 1, r: cell.r - 1 }];
    const overlaps = (p) => {
      if (!other) return false;
      const keys = padCells(other).map((q) => `${q.c},${q.r}`);
      return padCells(p).some((q) => keys.includes(`${q.c},${q.r}`));
    };
    const spot = candidates.find((p) => padFits(l, p) && !overlaps(p));
    if (!spot) {
      this.say('padNeedsFloor');
      haptics.failure();
      return;
    }
    const cells = padCells(spot).map((q) => `${q.c},${q.r}`);
    l.items = l.items.filter((i) => !cells.includes(`${i.c},${i.r}`));
    if (goal) l.goal = spot; else l.start = spot;
    this.pendingMine = null;
    this.changed();
    haptics.light();
  }

  placeItem(cell) {
    const kind = this.tool;
    const l = this.level;
    if (isRock(l, cell.c, cell.r) || isPadCell(l, cell)) {
      this.say('cellTaken');
      haptics.failure();
      return;
    }
    if (kind === 'movingMine' && this.pendingMine !== null && l.items[this.pendingMine] && l.items[this.pendingMine].kind === 'movingMine') {
      const m = l.items[this.pendingMine];
      if (m.c !== cell.c || m.r !== cell.r) {
        m.c2 = cell.c;
        m.r2 = cell.r;
      }
      this.pendingMine = null;
      this.changed();
      haptics.light();
      return;
    }
    const existing = itemIndexAt(l, cell.c, cell.r);
    if (existing >= 0) {
      const it = l.items[existing];
      if (it.kind === kind) {
        // Tapping a thing of the same kind turns or recolours it.
        if (kind === 'spikes' || kind === 'wind') {
          it.dir = (it.dir + 1) % 4;
          if (kind === 'wind') this.windDir = it.dir;
        } else if (kind === 'laser') {
          it.dir = it.dir === 1 ? 0 : 1;
          this.laserDir = it.dir;
        } else if (kind === 'spinner') {
          it.dir = it.dir === 1 ? 0 : 1;
          it.size = this.spinnerSize;
          this.spinnerDir = it.dir;
        } else if (kind === 'key' || kind === 'door') {
          it.color = (it.color + 1) % 3;
          this.color = it.color;
        } else if (kind === 'movingMine') {
          this.pendingMine = existing;
          this.say('mineTrack');
          return;
        }
        this.changed();
        haptics.light();
        return;
      }
      l.items.splice(existing, 1);
    }
    if (kind === 'star' && l.items.filter((i) => i.kind === 'star').length >= 3) {
      this.say('starLimit');
      haptics.failure();
      return;
    }
    if (l.items.length >= MAX_ITEMS) {
      this.say('itemLimit');
      haptics.failure();
      return;
    }
    const item = { kind, c: cell.c, r: cell.r, dir: 0, color: 0, size: 3 };
    if (kind === 'spikes') item.dir = this.spikeDirection(cell);
    else if (kind === 'wind') item.dir = this.windDir;
    else if (kind === 'laser') item.dir = this.laserDir;
    else if (kind === 'spinner') { item.dir = this.spinnerDir; item.size = this.spinnerSize; }
    else if (kind === 'key' || kind === 'door') item.color = this.color;
    l.items.push(item);
    if (kind === 'movingMine') {
      this.pendingMine = l.items.length - 1;
      this.say('mineTrack');
    } else {
      this.pendingMine = null;
    }
    this.changed();
    haptics.light();
  }

  /** Spikes stick to the nearest rock: floor first, then ceiling, then walls. */
  spikeDirection(cell) {
    const l = this.level;
    if (isRock(l, cell.c, cell.r - 1)) return 0;
    if (isRock(l, cell.c, cell.r + 1)) return 2;
    if (isRock(l, cell.c - 1, cell.r)) return 1;
    if (isRock(l, cell.c + 1, cell.r)) return 3;
    return 0;
  }
}

// ---------------------------------------------------------------- maker home

export class MakerScreen {
  constructor(app) { this.app = app; }

  mount(root) {
    this.root = root;
    root.className = 'screen';
    this.render();
    this.off = onAction(root, (act, el) => this.action(act, el));
    this.closeMenus = (e) => { if (!e.target.closest('[data-act="more"]') && !e.target.closest('.menu-pop')) root.querySelectorAll('.menu-pop').forEach((m) => m.remove()); };
    document.addEventListener('click', this.closeMenus, true);
  }

  unmount() {
    this.off();
    document.removeEventListener('click', this.closeMenus, true);
  }

  render() {
    const { app } = this;
    const s = app.s;
    const levels = app.maker.levels;
    setHTML(this.root, html`
      <div class="header narrow"><button class="icon-btn" data-act="back">${raw(icon('back', 18))}</button><h1>${s.makerTitle}</h1></div>
      <div class="scroll"><div class="narrow stack" style="gap:0">
        <button class="btn primary" data-act="new" style="margin-bottom:12px">${raw(icon('plus', 17))}<span>${s.newLevel}</span></button>
        ${levels.length === 0 ? html`<div class="empty" style="margin:0 0 12px">${raw(icon('hammer', 34, 'cyan'))}
          <div style="font-size:16px;font-weight:600;color:rgba(255,255,255,.8)">${s.makerIntro}</div>
          <button class="btn" data-act="example">${raw(icon('sparkles', 17))}<span>${s.openExample}</span></button></div>` : ''}
        ${levels.map((l) => this.card(l))}
        <button class="btn" data-act="community" style="margin-top:8px">${raw(icon('people', 18))}<span>${s.communityButton}</span></button>
      </div></div>`);
  }

  card(l) {
    const { app } = this;
    const s = app.s;
    const world = app.library.worlds[l.theme] || null;
    const th = makeTheme(world);
    let status = [s.statusDraft, 'rgba(255,255,255,.5)', 'dashed'];
    if (isPublishedAsIs(l)) status = [s.statusPublished, 'var(--cyan)', 'cloudCheck'];
    else if (isCleared(l)) status = [s.statusTested, 'var(--green)', 'seal'];
    else if (l.publishedID) status = [s.statusChanged, 'var(--gold)', 'hammer'];
    return html`<div class="maker-card" style="position:relative">
      <button class="open" data-act="open" data-id="${l.id}">
        <span class="thumb" style="background:linear-gradient(${raw(th.bgTop)},${raw(th.bgBottom)});border:1px solid ${raw(th.neon)};color:${raw(th.neon)}">${raw(icon('hammer', 20))}</span>
        <span style="min-width:0;flex:1">
          <div class="name">${l.name}</div>
          <div style="font-size:12px;font-weight:800;color:${raw(status[1])};display:flex;gap:5px;align-items:center">${raw(icon(status[2], 13))}${status[0]}</div>
          <div class="muted" style="font-size:11px;display:flex;gap:10px">${raw(icon('grid', 11))}${s.gridSize(l.cols, l.rows)} ${raw(icon('fuel', 11))}${Math.trunc(l.fuel)}${l.updatedAt ? ` · ${s.ago(new Date(l.updatedAt))}` : ''}</div>
        </span>
      </button>
      <button class="icon-btn" data-act="more" data-id="${l.id}" style="width:40px;height:40px">${raw(icon('ellipsis', 18))}</button>
    </div>`;
  }

  action(act, el) {
    const { app } = this;
    const s = app.s;
    sound.play('click', 0.6);
    switch (act) {
      case 'back': app.go('menu'); break;
      case 'community': app.go('community'); break;
      case 'new': {
        const names = new Set(app.maker.levels.map((l) => l.name));
        let n = app.maker.levels.length + 1;
        while (names.has(s.defaultLevelName(n))) n++;
        const l = app.maker.create(s.defaultLevelName(n), 0);
        app.go('editor', { id: l.id });
        break;
      }
      case 'example': {
        const l = app.maker.addSample(0, s.exampleName);
        app.go('editor', { id: l.id });
        break;
      }
      case 'open': app.go('editor', { id: el.dataset.id }); break;
      case 'more': {
        this.root.querySelectorAll('.menu-pop').forEach((m) => m.remove());
        const pop = document.createElement('div');
        pop.className = 'menu-pop';
        setHTML(pop, html`<button data-act="dup" data-id="${el.dataset.id}">${raw(icon('copy', 16))}${s.duplicate}</button>
          <button data-act="del" data-id="${el.dataset.id}" style="color:var(--red)">${raw(icon('trash', 16))}${s.delete}</button>`);
        el.parentElement.appendChild(pop);
        break;
      }
      case 'dup': {
        const copy = app.maker.duplicate(el.dataset.id, s.copySuffix);
        if (copy) app.go('editor', { id: copy.id });
        break;
      }
      case 'del':
        dialog(s.deleteLevelTitle, s.deleteLevelMessage, [
          { label: s.cancel, role: 'cancel' },
          { label: s.delete, role: 'destructive', action: () => { app.maker.remove(el.dataset.id); this.render(); } },
        ]);
        break;
      default: break;
    }
  }
}

// ---------------------------------------------------------------- editor

export class EditorScreen {
  constructor(app, { id }) {
    this.app = app;
    this.id = id;
  }

  mount(root) {
    const { app } = this;
    this.session = app.maker.openSession(this.id, app.library.worlds);
    if (!this.session) {
      app.go('maker');
      return;
    }
    this.root = root;
    root.className = 'screen editor';
    root.style.padding = '0';
    setHTML(root, html`
      <div class="ed-top" style="padding-top:calc(8px + var(--safe-top))"></div>
      <div class="ed-canvas"><canvas></canvas></div>
      <div class="ed-options"></div>
      <div class="ed-tools"></div>
      <div class="ed-actions"></div>`);
    this.canvas = new EditorCanvas(root.querySelector('canvas'), this.session, app);
    this.shownVersion = -1;
    this.shownNotice = null;
    this.renderChrome();
    this.off = onAction(root, (act, el) => this.action(act, el));
    const tick = () => {
      if (!this.root) return;
      if (this.session.version !== this.shownVersion) {
        this.shownVersion = this.session.version;
        this.renderChrome();
      }
      this.raf = requestAnimationFrame(tick);
    };
    this.raf = requestAnimationFrame(tick);
    const sel = root.querySelector('.ed-tool.on');
    if (sel) sel.scrollIntoView({ inline: 'center', block: 'nearest' });
  }

  unmount() {
    if (!this.root) return;
    cancelAnimationFrame(this.raf);
    this.canvas.destroy();
    this.off();
    this.root.style.padding = '';
    this.root = null;
  }

  get accent() { return makeTheme(this.app.library.worlds[this.session.level.theme]).neon; }

  renderChrome() {
    const { app, session } = this;
    const s = app.s;
    const l = session.level;
    const accent = this.accent;
    const [r, g, b] = [1, 3, 5].map((i) => parseInt(accent.slice(i, i + 2), 16));
    this.root.style.setProperty('--accent', accent);
    this.root.style.setProperty('--accent-rgb', `${r}, ${g}, ${b}`);

    let status = [s.statusDraft, 'rgba(255,255,255,.5)'];
    if (isPublishedAsIs(l)) status = [s.statusPublished, 'var(--cyan)'];
    else if (isCleared(l)) status = [s.statusTested, 'var(--green)'];
    else if (l.publishedID) status = [s.statusChanged, 'var(--gold)'];
    setHTML(this.root.querySelector('.ed-top'), html`
      <button class="icon-btn" data-act="back">${raw(icon('back', 17))}</button>
      <button class="ed-title" data-act="settings"><div class="name">${l.name}</div>
        <div class="status" style="color:${raw(status[1])}">${raw(icon(isCleared(l) ? 'seal' : 'dashed', 13))}${status[0]}
          <span style="color:rgba(255,255,255,.4)">· ${s.gridSize(l.cols, l.rows)} ${raw(icon('fuel', 11))} ${Math.trunc(l.fuel)}</span></div></button>
      <button class="icon-btn" data-act="undo" ${session.canUndo ? '' : 'disabled'} aria-label="${s.undo}">${raw(icon('undo', 17))}</button>
      <button class="icon-btn" data-act="redo" ${session.canRedo ? '' : 'disabled'} aria-label="${s.redo}">${raw(icon('redo', 17))}</button>
      <button class="icon-btn" data-act="settings" aria-label="${s.levelSettings}">${raw(icon('sliders', 17))}</button>`);

    const chip = (act, value, on, ic, label, tint) => html`<button class="ed-chip ${on ? 'on' : ''}" data-act="${act}" data-v="${value}">
      ${ic ? html`<span style="color:${raw(tint && !on ? tint : 'inherit')}">${raw(icon(ic, 15))}</span>` : ''}${label || ''}</button>`;
    let chips = '';
    const t = session.tool;
    if (t === 'wind') chips = ['arrowUp', 'arrowRight', 'arrowDown', 'arrowLeft'].map((ic, d) => chip('windDir', d, session.windDir === d, ic));
    else if (t === 'key' || t === 'door') chips = [0, 1, 2].map((c) => chip('color', c, session.color === c, t === 'key' ? 'key' : 'door', s.colorName(c), keyColor(c)));
    else if (t === 'laser') chips = [chip('laserDir', 0, session.laserDir === 0, 'leftRight', s.across), chip('laserDir', 1, session.laserDir === 1, 'upDown', s.upDown)];
    else if (t === 'spinner') chips = [...[2, 3, 4].map((n) => chip('bladeSize', n, session.spinnerSize === n, null, s.bladeSize(n))), chip('bladeDir', 0, session.spinnerDir === 0, 'ccw'), chip('bladeDir', 1, session.spinnerDir === 1, 'cw')];
    setHTML(this.root.querySelector('.ed-options'), html`<div class="ed-hint">${session.pendingMine !== null ? s.notice('mineTrack') : s.toolHint(t)}</div>
      ${chips ? html`<div class="ed-chips">${chips}</div>` : ''}`);

    const toolColor = (tool) => {
      if (tool === 'rock') return accent;
      if (['erase', 'spikes', 'mine', 'movingMine', 'spinner', 'laser'].includes(tool)) return 'var(--red)';
      return { start: '#C9D3E3', goal: 'var(--green)', star: 'var(--gold)', fuel: 'var(--orange)', wind: Palette.wind, key: keyColor(0), door: keyColor(0), hand: '#fff' }[tool];
    };
    const toolsEl = this.root.querySelector('.ed-tools');
    const scroll = toolsEl.scrollLeft;
    setHTML(toolsEl, html`${TOOLS.map((tool) => html`<button class="ed-tool ${tool === t ? 'on' : ''}" data-act="tool" data-v="${tool}">
      <span style="color:${raw(tool === t ? '#000' : toolColor(tool))}">${raw(icon(TOOL_ICONS[tool], 20))}</span><span>${s.toolName(tool)}</span></button>`)}`);
    toolsEl.scrollLeft = scroll;

    const published = isPublishedAsIs(l);
    setHTML(this.root.querySelector('.ed-actions'), html`
      <button class="btn primary" data-act="test">${raw(icon('play', 17))}<span>${s.test}</span></button>
      <button class="btn ${published || this.publishing ? 'disabled' : ''}" data-act="publish">${this.publishing ? html`<span class="spinner" style="width:20px;height:20px;margin:0"></span>` : raw(icon(published ? 'cloudCheck' : 'upload', 18))}<span>${published ? s.published : s.publish}</span></button>`);

    if (session.notice && session.notice !== this.shownNotice) {
      this.showNotice(s.notice(session.notice));
      session.notice = null;
    }
    this.shownNotice = session.notice;
  }

  showNotice(text) {
    const host = this.root.querySelector('.ed-canvas');
    host.querySelectorAll('.ed-notice').forEach((n) => n.remove());
    const n = document.createElement('div');
    n.className = 'ed-notice';
    n.textContent = text;
    host.appendChild(n);
    clearTimeout(this.noticeTimer);
    this.noticeTimer = setTimeout(() => n.remove(), 2400);
  }

  action(act, el) {
    const { app, session } = this;
    sound.play('click', 0.4);
    haptics.light();
    const v = el.dataset.v;
    switch (act) {
      case 'back':
        session.save();
        app.go('maker');
        break;
      case 'undo': session.undo(); break;
      case 'redo': session.redo(); break;
      case 'tool': session.setTool(v); break;
      case 'windDir': session.windDir = Number(v); session.changed(); break;
      case 'color': session.color = Number(v); session.changed(); break;
      case 'laserDir': session.laserDir = Number(v); session.changed(); break;
      case 'bladeSize': session.spinnerSize = Number(v); session.changed(); break;
      case 'bladeDir': session.spinnerDir = Number(v); session.changed(); break;
      case 'settings': this.openSettings(); break;
      case 'test': this.test(); break;
      case 'publish': this.publishTapped(); break;
      default: break;
    }
  }

  test() {
    const { app, session } = this;
    const s = app.s;
    const list = problems(session.level);
    if (list.length) {
      dialog(s.notReadyTitle, list.map((p) => `• ${s.problem(p)}`).join('\n'), [{ label: s.ok, role: 'cancel' }]);
      return;
    }
    session.save();
    const l = session.level;
    const compiled = compile(l, { worldCount: app.library.worlds.length });
    app.go('custom', { custom: { level: compiled, origin: { type: 'editor', levelID: l.id, hash: contentHash(l) } } });
  }

  publishTapped() {
    const { app, session } = this;
    const s = app.s;
    const a = app.account;
    if (!a.isConfigured) {
      dialog(s.notConfiguredTitle, s.notConfiguredBody, [{ label: s.ok, role: 'cancel' }]);
      return;
    }
    if (!a.isSignedIn) {
      openAccount(app);
      return;
    }
    const list = problems(session.level);
    if (list.length) {
      dialog(s.notReadyTitle, list.map((p) => `• ${s.problem(p)}`).join('\n'), [{ label: s.ok, role: 'cancel' }]);
      return;
    }
    if (!isCleared(session.level)) {
      dialog(s.publishNeedsTestTitle, s.publishNeedsTest, [{ label: s.cancel, role: 'cancel' }, { label: s.test, action: () => this.test() }]);
      return;
    }
    dialog(s.publishConfirmTitle(session.level.name), session.level.publishedID ? s.publishAgainMessage : s.publishConfirmMessage, [
      { label: s.cancel, role: 'cancel' },
      { label: s.publish, action: () => this.publish() },
    ]);
  }

  async publish() {
    const { app, session } = this;
    const s = app.s;
    if (this.publishing) return;
    this.publishing = true;
    session.changed();
    const level = cloneLevel(session.level);
    try {
      const remoteID = await app.community.publish(level);
      app.maker.markPublished(level.id, remoteID, contentHash(level));
      haptics.success();
      dialog(s.publishedTitle, s.publishedMessage, [{ label: s.ok, role: 'cancel' }]);
    } catch (err) {
      dialog(s.publish, s.onlineError(err), [{ label: s.ok, role: 'cancel' }]);
    }
    this.publishing = false;
    session.changed();
  }

  openSettings() {
    const { app, session } = this;
    const s = app.s;
    sheet((el, close) => {
      let fuel = session.level.fuel;
      const render = () => {
        const l = session.level;
        const worlds = app.library.worlds;
        setHTML(el, html`
          <div class="sheet-head"><h2>${s.levelSettings}</h2><button class="link-btn" data-act="done">${s.done}</button></div>
          <div class="stack" style="gap:18px">
            <div class="field"><label>${s.nameLabel}</label><input name="name" maxlength="40" value="${l.name}" autocomplete="off" spellcheck="false"></div>
            <div><div class="section-title">${s.themeLabel}</div><div class="theme-grid">${worlds.map((w, i) => {
              const th = makeTheme(w);
              return html`<button class="theme-chip ${l.theme === i ? 'on' : ''}" data-act="theme" data-v="${i}" style="${raw(l.theme === i ? `border-color:${th.neon}` : '')}">
                <div class="preview" style="background:linear-gradient(${raw(th.bgTop)},${raw(th.bgBottom)})"><i style="background:${raw(th.rock)};border-color:${raw(th.neon)}"></i></div>${s.worldName(w, i)}</button>`;
            })}</div></div>
            <div><div class="section-title">${s.widthLabel}</div><div class="choices" style="margin:0">
              <button class="choice ${l.cols === NARROW_COLS ? 'on' : ''}" data-act="cols" data-v="${NARROW_COLS}">${s.narrow} · 14</button>
              <button class="choice ${l.cols === WIDE_COLS ? 'on' : ''}" data-act="cols" data-v="${WIDE_COLS}">${s.wide} · 28</button></div></div>
            <div><div class="section-title">${s.heightLabel}</div>
              <div style="display:flex;align-items:center;gap:10px"><span style="flex:1;font-size:17px">${s.rowsCount(l.rows)}</span>
                <button class="icon-btn" data-act="rows" data-v="-5" ${l.rows > MIN_ROWS ? '' : 'disabled'} style="border-radius:10px">${raw(icon('minus', 16))}</button>
                <button class="icon-btn" data-act="rows" data-v="5" ${l.rows < MAX_ROWS ? '' : 'disabled'} style="border-radius:10px">${raw(icon('plus', 16))}</button></div>
              <div class="muted small-text" style="margin-top:6px">${s.shrinkWarning}</div></div>
            <div><div class="section-title">${s.fuelLabel}</div>
              <div style="display:flex;align-items:center;gap:10px"><span style="color:var(--orange)">${raw(icon('fuel', 18))}</span>
                <span class="fuel-value" style="font-size:20px;font-weight:900;width:40px">${Math.trunc(fuel)}</span>
                <input type="range" name="fuel" min="${FUEL_MIN}" max="${FUEL_MAX}" step="1" value="${fuel}"></div>
              <div class="muted small-text" style="margin-top:6px">${s.fuelDetail}</div></div>
            <button class="btn danger" data-act="delete">${raw(icon('trash', 17))}<span>${s.deleteLevel}</span></button>
          </div>`);
      };
      render();
      const commitName = () => {
        const input = el.querySelector('input[name=name]');
        if (input) session.rename(input.value);
      };
      const commitFuel = () => {
        if (Math.round(fuel) !== session.level.fuel) session.edit((l) => { l.fuel = Math.round(fuel); });
      };
      el.addEventListener('input', (e) => {
        if (e.target.name === 'fuel') {
          fuel = Number(e.target.value);
          el.querySelector('.fuel-value').textContent = String(Math.trunc(fuel));
        }
      });
      el.addEventListener('change', (e) => {
        if (e.target.name === 'fuel') commitFuel();
        if (e.target.name === 'name') commitName();
      });
      el.addEventListener('click', (e) => {
        const t = e.target.closest('[data-act]');
        if (!t) return;
        sound.play('click', 0.4);
        const v = Number(t.dataset.v);
        switch (t.dataset.act) {
          case 'done': commitName(); commitFuel(); close(); break;
          case 'theme': session.edit((l) => { l.theme = v; }); render(); break;
          case 'cols': session.edit((l) => resize(l, v, l.rows)); render(); break;
          case 'rows': session.edit((l) => resize(l, l.cols, l.rows + v)); render(); break;
          case 'delete':
            dialog(s.deleteLevelTitle, s.deleteLevelMessage, [
              { label: s.cancel, role: 'cancel' },
              { label: s.delete, role: 'destructive', action: () => { close(); app.maker.remove(session.level.id); app.go('maker'); } },
            ]);
            break;
          default: break;
        }
      });
    }, () => {
      // Closing by tapping outside still keeps the typed name and fuel.
      const input = document.querySelector('.sheet input[name=name]');
      if (input) session.rename(input.value);
    });
  }
}

// ---------------------------------------------------------------- canvas

class EditorCanvas {
  constructor(canvas, session, app) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.session = session;
    this.app = app;
    this.pointers = new Map();
    this.stroke = null;
    this.pinch = null;
    this.drag = null;
    this.cursor = null;
    this.shownRock = null;
    this.shownObjects = -1;
    this.t0 = performance.now();
    this.resize = () => this.layout(false);
    window.addEventListener('resize', this.resize);
    this.ro = typeof ResizeObserver !== 'undefined' ? new ResizeObserver(() => this.layout(false)) : null;
    if (this.ro) this.ro.observe(canvas);
    canvas.addEventListener('pointerdown', (e) => this.down(e));
    canvas.addEventListener('pointermove', (e) => this.move(e));
    for (const ev of ['pointerup', 'pointercancel']) canvas.addEventListener(ev, (e) => this.up(e, ev === 'pointercancel'));
    canvas.addEventListener('wheel', (e) => this.wheel(e), { passive: false });
    canvas.addEventListener('contextmenu', (e) => e.preventDefault());
    this.layout(true);
    const frame = () => {
      if (this.dead) return;
      this.draw();
      this.raf = requestAnimationFrame(frame);
    };
    this.raf = requestAnimationFrame(frame);
  }

  destroy() {
    this.dead = true;
    cancelAnimationFrame(this.raf);
    window.removeEventListener('resize', this.resize);
    if (this.ro) this.ro.disconnect();
    this.session.camera = { x: this.cam.x, y: this.cam.y, scale: this.scale };
  }

  get levelW() { return this.session.level.cols * CELL; }
  get levelH() { return this.session.level.rows * CELL; }

  layout(first) {
    const r = this.canvas.getBoundingClientRect();
    if (r.width < 2 || r.height < 2) return;
    this.W = r.width;
    this.H = r.height;
    this.dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.canvas.width = Math.round(this.W * this.dpr);
    this.canvas.height = Math.round(this.H * this.dpr);
    if (!this.cam && this.session.camera) {
      this.cam = { x: this.session.camera.x, y: this.session.camera.y };
      this.scale = this.session.camera.scale;
      this.userMoved = true;
    } else if (!this.cam || !this.userMoved) {
      // Until the player moves the view, keep the level framed as the layout settles.
      this.frameLevel();
    }
    this.clamp();
  }

  scaleRange() {
    const minScale = this.W / 150;
    const fitAll = Math.min(this.W / (this.levelW + 120), this.H / (this.levelH + 120));
    return [Math.min(fitAll, minScale / 1.5), minScale];
  }

  frameLevel() {
    const [lo, hi] = this.scaleRange();
    this.scale = Math.min(Math.max(this.W / (this.levelW + 40), lo), hi);
    const viewH = this.H / this.scale;
    const y = viewH / 2 - 30;
    const start = this.session.level.start;
    this.cam = { x: this.levelW / 2, y: start ? Math.max(y, start.r * CELL - viewH * 0.25) : y };
  }

  clamp() {
    if (!this.cam) return;
    const [lo, hi] = this.scaleRange();
    this.scale = Math.min(Math.max(this.scale, lo), hi);
    const m = 80, viewW = this.W / this.scale, viewH = this.H / this.scale;
    const w = this.levelW, h = this.levelH;
    this.cam.x = viewW >= w + 2 * m ? w / 2 : Math.min(Math.max(this.cam.x, viewW / 2 - m), w + m - viewW / 2);
    this.cam.y = viewH >= h + 2 * m ? h / 2 : Math.min(Math.max(this.cam.y, viewH / 2 - m), h + m - viewH / 2);
  }

  toWorld(p) {
    return { x: this.cam.x + (p.x - this.W / 2) / this.scale, y: this.cam.y - (p.y - this.H / 2) / this.scale };
  }

  cellAt(p) {
    const w = this.toWorld(p);
    return { c: Math.floor(w.x / CELL), r: Math.floor(w.y / CELL) };
  }

  local(e) {
    const r = this.canvas.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  }

  down(e) {
    sound.unlock();
    this.canvas.setPointerCapture(e.pointerId);
    const p = this.local(e);
    this.pointers.set(e.pointerId, p);
    const session = this.session;
    if (this.pointers.size >= 2) {
      // Two fingers: undo what the first finger started and switch to pan/zoom.
      if (this.stroke && !this.stroke.cancelled) {
        session.cancelStroke();
        this.stroke.cancelled = true;
      }
      this.drag = null;
      this.cursor = null;
      this.beginPinch();
      return;
    }
    if (session.tool === 'hand' || e.button === 1 || e.button === 2) {
      this.drag = { start: p, cam: { ...this.cam } };
      this.userMoved = true;
      return;
    }
    this.stroke = { id: e.pointerId, cancelled: false, last: this.cellAt(p) };
    session.beginStroke();
    this.cursor = this.stroke.last;
    if (paints(session.tool)) session.paint(this.stroke.last);
  }

  move(e) {
    if (!this.pointers.has(e.pointerId)) {
      if (e.pointerType === 'mouse') this.hover = this.cellAt(this.local(e));
      return;
    }
    const p = this.local(e);
    this.pointers.set(e.pointerId, p);
    if (this.pointers.size >= 2 && this.pinch) {
      this.updatePinch();
      return;
    }
    if (this.drag) {
      this.cam.x = this.drag.cam.x - (p.x - this.drag.start.x) / this.scale;
      this.cam.y = this.drag.cam.y + (p.y - this.drag.start.y) / this.scale;
      this.clamp();
      return;
    }
    if (!this.stroke || this.stroke.id !== e.pointerId || this.stroke.cancelled) return;
    const c = this.cellAt(p);
    if (paints(this.session.tool)) for (const step of cellsBetween(this.stroke.last, c)) this.session.paint(step);
    this.stroke.last = c;
    this.cursor = c;
  }

  up(e, cancelled) {
    if (!this.pointers.has(e.pointerId)) return;
    this.pointers.delete(e.pointerId);
    const session = this.session;
    if (this.stroke && this.stroke.id === e.pointerId) {
      if (cancelled) session.cancelStroke();
      else if (!this.stroke.cancelled) {
        if (!paints(session.tool)) session.place(this.stroke.last);
        session.endStroke();
      }
      this.stroke = null;
      this.cursor = null;
    }
    if (this.pointers.size < 2) this.pinch = null;
    if (this.pointers.size === 0) this.drag = null;
    else if (this.pointers.size === 1 && session.tool === 'hand') {
      const [p] = [...this.pointers.values()];
      this.drag = { start: p, cam: { ...this.cam } };
    }
  }

  beginPinch() {
    this.userMoved = true;
    const [a, b] = [...this.pointers.values()];
    this.pinch = { center: { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 }, dist: Math.max(10, Math.hypot(a.x - b.x, a.y - b.y)), cam: { ...this.cam }, scale: this.scale };
  }

  updatePinch() {
    const [a, b] = [...this.pointers.values()];
    const st = this.pinch;
    const center = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
    const dist = Math.max(10, Math.hypot(a.x - b.x, a.y - b.y));
    const [lo, hi] = this.scaleRange();
    const scale = Math.min(Math.max(st.scale * dist / st.dist, lo), hi);
    // Keep the world point that was under the fingers under the fingers.
    const ax = st.cam.x + (st.center.x - this.W / 2) / st.scale;
    const ay = st.cam.y - (st.center.y - this.H / 2) / st.scale;
    this.scale = scale;
    this.cam.x = ax - (center.x - this.W / 2) / scale;
    this.cam.y = ay + (center.y - this.H / 2) / scale;
    this.clamp();
  }

  wheel(e) {
    e.preventDefault();
    this.userMoved = true;
    const p = this.local(e);
    if (e.ctrlKey || e.metaKey) {
      // Pinch on a trackpad, or Ctrl + wheel: zoom around the pointer.
      const before = this.toWorld(p);
      this.scale *= Math.exp(-e.deltaY * 0.01);
      this.clamp();
      const after = this.toWorld(p);
      this.cam.x += before.x - after.x;
      this.cam.y += before.y - after.y;
    } else {
      this.cam.x += e.deltaX / this.scale;
      this.cam.y -= e.deltaY / this.scale;
    }
    this.clamp();
  }

  draw() {
    if (!this.cam || !this.W) return;
    const ctx = this.ctx, dpr = this.dpr, W = this.W, H = this.H;
    const session = this.session, l = session.level;
    const th = makeTheme(this.app.library.worlds[l.theme]);
    const t = (performance.now() - this.t0) / 1000;

    if (this.shownRock !== session.version) {
      // Rebuild the rock outline and the compiled objects when the level changed.
      this.shownRock = session.version;
      const w = l.cols * CELL, h = l.rows * CELL;
      const outer = [{ x: -400, y: -400 }, { x: w + 400, y: -400 }, { x: w + 400, y: h + 400 }, { x: -400, y: h + 400 }];
      this.terrain = terrainPath([[outer, ...rockOutlines(l)]]);
      this.compiled = compile(l, { worldCount: this.app.library.worlds.length, withTerrain: false });
      const grid = new Path2D(), bold = new Path2D();
      for (let c = 0; c <= l.cols; c++) { const p = c % 5 === 0 ? bold : grid; p.moveTo(c * CELL, 0); p.lineTo(c * CELL, h); }
      for (let r = 0; r <= l.rows; r++) { const p = r % 5 === 0 ? bold : grid; p.moveTo(0, r * CELL); p.lineTo(w, r * CELL); }
      this.grid = grid;
      this.bold = bold;
    }

    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const bg = ctx.createLinearGradient(0, 0, 0, H);
    bg.addColorStop(0, th.bgTop);
    bg.addColorStop(1, th.bgBottom);
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, W, H);
    const s = this.scale * dpr;
    ctx.setTransform(s, 0, 0, -s, dpr * (W / 2 - this.cam.x * this.scale), dpr * (H / 2 + this.cam.y * this.scale));

    const lv = this.compiled;
    const dyn = {
      t,
      minePos: (i) => {
        const m = lv.mines[i];
        if (m.path.length < 2 || m.speed <= 0) return m.path[0];
        const len = Math.hypot(m.path[1].x - m.path[0].x, m.path[1].y - m.path[0].y);
        const period = (2 * len) / m.speed;
        let k = (t % period) / (period / 2);
        if (k > 1) k = 2 - k;
        k = 0.5 - 0.5 * Math.cos(k * Math.PI);
        return { x: m.path[0].x + (m.path[1].x - m.path[0].x) * k, y: m.path[0].y + (m.path[1].y - m.path[0].y) * k };
      },
      spinnerAngle: (i) => lv.spinners[i].speed * t,
      laserState: () => 'on',
      gone: {},
      landLabel: this.app.s.land,
    };
    drawLevelBack(ctx, lv, th, dyn);
    drawTerrain(ctx, this.terrain, th);
    ctx.lineWidth = 1 / this.scale;
    ctx.strokeStyle = 'rgba(255,255,255,0.07)';
    ctx.stroke(this.grid);
    ctx.strokeStyle = 'rgba(255,255,255,0.15)';
    ctx.stroke(this.bold);
    ctx.strokeStyle = 'rgba(255,255,255,0.45)';
    ctx.lineWidth = 2;
    ctx.strokeRect(0, 0, l.cols * CELL, l.rows * CELL);
    drawLevelFront(ctx, lv, th, dyn);

    if (l.start) {
      ctx.save();
      ctx.translate((l.start.c + 1) * CELL, l.start.r * CELL + RocketShape.spawnHeight);
      drawRocket(ctx, 0);
      ctx.restore();
    }
    const blink = 0.35 + 0.65 * (0.5 + 0.5 * Math.cos(t * Math.PI * 2));
    for (const pad of [l.start, l.goal]) {
      if (!pad || padFits(l, pad)) continue;
      ctx.globalAlpha = blink;
      ctx.beginPath();
      ctx.roundRect(pad.c * CELL, (pad.r - 1) * CELL, CELL * 2, CELL * 3, 6);
      ctx.fillStyle = 'rgba(255,46,77,0.18)';
      ctx.fill();
      ctx.strokeStyle = Palette.hazard;
      ctx.lineWidth = 2;
      ctx.stroke();
      ctx.globalAlpha = 1;
    }
    if (session.pendingMine !== null && l.items[session.pendingMine]) {
      const it = l.items[session.pendingMine];
      ctx.globalAlpha = 0.2 + 0.8 * (0.5 + 0.5 * Math.cos(t * Math.PI * 2.5));
      ctx.beginPath();
      ctx.roundRect(it.c * CELL + 1, it.r * CELL + 1, CELL - 2, CELL - 2, 6);
      ctx.strokeStyle = Palette.star;
      ctx.lineWidth = 2.5;
      ctx.stroke();
      ctx.globalAlpha = 1;
    }
    for (const it of l.items) {
      if (it.kind !== 'wind' || isRock(l, it.c, it.r)) continue;
      ctx.save();
      ctx.translate((it.c + 0.5) * CELL, (it.r + 0.5) * CELL);
      ctx.rotate((-it.dir * Math.PI) / 2);
      ctx.beginPath();
      ctx.moveTo(0, 8); ctx.lineTo(6, -2); ctx.lineTo(2, -2); ctx.lineTo(2, -8); ctx.lineTo(-2, -8); ctx.lineTo(-2, -2); ctx.lineTo(-6, -2);
      ctx.closePath();
      ctx.fillStyle = 'rgba(143,211,255,0.8)';
      ctx.fill();
      ctx.restore();
    }
    const cur = this.cursor || this.hover;
    if (cur && session.tool !== 'hand') {
      const pad = session.tool === 'start' || session.tool === 'goal';
      const color = session.tool === 'erase' ? Palette.hazard : '#FFFFFF';
      ctx.beginPath();
      ctx.roundRect(cur.c * CELL + 1, cur.r * CELL + 1, (pad ? 2 : 1) * CELL - 2, (pad ? 2 : 1) * CELL - 2, 4);
      ctx.fillStyle = color === '#FFFFFF' ? 'rgba(255,255,255,0.12)' : 'rgba(255,46,77,0.12)';
      ctx.fill();
      ctx.strokeStyle = color;
      ctx.lineWidth = 2;
      ctx.stroke();
    }
  }
}

/** Every cell on the straight line between two cells, so fast strokes leave no gaps. */
function cellsBetween(a, b) {
  const cells = [];
  let x = a.c, y = a.r;
  const dx = Math.abs(b.c - a.c), dy = -Math.abs(b.r - a.r);
  const sx = a.c < b.c ? 1 : -1, sy = a.r < b.r ? 1 : -1;
  let err = dx + dy;
  for (let guard = 0; guard < 1000; guard++) {
    cells.push({ c: x, r: y });
    if (x === b.c && y === b.r) break;
    const e2 = 2 * err;
    if (e2 >= dy) { err += dy; x += sx; }
    if (e2 <= dx) { err += dx; y += sy; }
  }
  return cells;
}
