// The game screen: simulation loop, touch/keyboard controls, camera, effects, HUD and overlays
// (port of GameScene.swift, GameSession.swift and GameView.swift).
import { GameWorld, Physics, RocketShape, rotate } from './physics.js';
import { Palette, drawGlow, drawRocket, keyColor, lighter, rgba, theme as makeTheme } from './art.js';
import { Particles, Starfield, drawLevelBack, drawLevelFront, drawTerrain, terrainPath } from './render.js';
import { haptics, sound } from './audio.js';
import { html, onAction, raw, setHTML } from './dom.js';
import { icon } from './icons.js';
import { mountLikeButton } from './community.js';

const BASE_R = 62, KNOB_R = 27, GAS_R = 54, DEAD_ZONE = 0.22;

export class GameScreen {
  /** opts: { levelIndex } for the campaign, or { custom: { level, origin: {type:'editor', levelID, hash} | {type:'community', level} } } */
  constructor(app, opts) {
    this.app = app;
    this.custom = opts.custom || null;
    this.levelIndex = this.custom ? 0 : Math.max(0, Math.min(opts.levelIndex || 0, app.library.levels.length - 1));
    this.attempts = 1;
    this.demo = !!opts.demo;
  }

  get s() { return this.app.s; }
  get level() { return this.custom ? this.custom.level : this.app.library.levels[this.levelIndex]; }
  get worldInfo() { return this.app.library.worlds[this.level.world] || null; }
  get starTotal() { return this.custom ? this.level.stars.length : 3; }
  get hasNext() { return !this.custom && this.levelIndex + 1 < this.app.library.levels.length; }
  get levelName() { return this.custom ? this.level.name : this.s.name(this.level); }
  get levelHint() {
    if (!this.custom) return this.s.hint(this.level);
    return this.custom.origin.type === 'community' ? this.s.byAuthor(this.custom.origin.level.author) : this.s.testFlightHint;
  }
  get levelLabel() {
    const idx = this.app.library.levels.map((l, i) => [l, i]).filter(([l]) => l.world === this.level.world).map(([, i]) => i);
    return `${this.level.world + 1}-${idx.indexOf(this.levelIndex) + 1}`;
  }
  get levelTag() {
    if (!this.custom) return this.s.levelTag(this.levelLabel);
    return this.custom.origin.type === 'editor' ? this.s.testFlightTag : this.s.communityTag;
  }
  get backTitle() { return !this.custom ? this.s.levelsButton : this.custom.origin.type === 'editor' ? this.s.editorButton : this.s.communityButton; }
  get backIcon() { return !this.custom ? 'grid' : this.custom.origin.type === 'editor' ? 'hammer' : 'people'; }

  mount(root) {
    this.root = root;
    root.className = 'screen game';
    setHTML(root, html`<canvas class="view"></canvas><div class="hud"></div><div class="intro"></div><div class="keys-hint"></div><div class="overlays"></div>`);
    this.canvas = root.querySelector('canvas');
    this.ctx = this.canvas.getContext('2d');
    this.hudEl = root.querySelector('.hud');
    this.introEl = root.querySelector('.intro');
    this.overlayEl = root.querySelector('.overlays');
    this.hintEl = root.querySelector('.keys-hint');
    this.showControls = this.app.isTouch;
    this.particles = new Particles();
    this.starfield = new Starfield();
    this.pointers = new Map();
    this.keys = new Set();
    this.resize = () => this.layout();
    window.addEventListener('resize', this.resize);
    this.onKeyDown = (e) => this.keyDown(e);
    this.onKeyUp = (e) => this.keyUp(e);
    window.addEventListener('keydown', this.onKeyDown);
    window.addEventListener('keyup', this.onKeyUp);
    this.onVisibility = () => { if (document.hidden) this.pause(); };
    document.addEventListener('visibilitychange', this.onVisibility);
    this.canvas.addEventListener('pointerdown', (e) => this.pointerDown(e));
    this.canvas.addEventListener('pointermove', (e) => this.pointerMove(e));
    for (const ev of ['pointerup', 'pointercancel', 'lostpointercapture']) this.canvas.addEventListener(ev, (e) => this.pointerUp(e));
    this.canvas.addEventListener('contextmenu', (e) => e.preventDefault());
    this.offActions = onAction(root, (act) => this.action(act));
    this.load();
    this.layout();
    this.running = true;
    this.lastTime = 0;
    const frame = (ts) => {
      if (!this.running) return;
      this.frame(ts / 1000);
      this.raf = requestAnimationFrame(frame);
    };
    this.raf = requestAnimationFrame(frame);
  }

  unmount() {
    this.running = false;
    cancelAnimationFrame(this.raf);
    window.removeEventListener('resize', this.resize);
    window.removeEventListener('keydown', this.onKeyDown);
    window.removeEventListener('keyup', this.onKeyUp);
    document.removeEventListener('visibilitychange', this.onVisibility);
    this.offActions();
    clearTimeout(this.introTimer);
    sound.setThrust(false);
  }

  // ---- Level setup

  load() {
    this.world = new GameWorld(this.level);
    this.theme = makeTheme(this.worldInfo);
    this.root.style.setProperty('--accent', this.theme.neon);
    const [r, g, b] = [1, 3, 5].map((i) => parseInt(this.theme.neon.slice(i, i + 2), 16));
    this.root.style.setProperty('--accent-rgb', `${r}, ${g}, ${b}`);
    this.terrain = terrainPath(this.level.terrain);
    this.particles.clear();
    for (const w of this.level.winds) this.particles.addWind(w.rect, w.force);
    this.gone = { stars: new Map(), cans: new Map(), keys: new Map(), doors: new Map() };
    this.popups = [];
    this.flashes = [];
    this.shards = [];
    this.phase = 'playing';
    this.finished = false;
    this.paused = false;
    this.outcome = null;
    this.flame = 0;
    this.rocketVisible = true;
    this.shake = 0;
    this.accumulator = 0;
    this.hudTimer = 0;
    this.demoClock = 0;
    this.exhaustAcc = 0;
    this.joy = null;
    this.gasPointers = new Set();
    this.targetAngle = null;
    this.wasThrusting = false;
    this.result = null;
    this.lastHUD = '';
    this.renderHUD();
    this.showIntro(true);
    this.overlayEl.innerHTML = '';
    this.camInit = false;
  }

  showIntro(on) {
    clearTimeout(this.introTimer);
    if (on) {
      setHTML(this.introEl, html`<div class="tag">${this.levelTag}</div><div class="name">${this.levelName}</div><div class="hint">${this.levelHint}</div>`);
      this.introEl.style.opacity = '1';
      this.introTimer = setTimeout(() => this.showIntro(false), 4500);
    } else {
      this.introEl.style.opacity = '0';
    }
  }

  // ---- Layout and camera

  layout() {
    const r = this.canvas.getBoundingClientRect();
    this.W = Math.max(1, r.width);
    this.H = Math.max(1, r.height);
    this.dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.canvas.width = Math.round(this.W * this.dpr);
    this.canvas.height = Math.round(this.H * this.dpr);
    this.insets = this.app.insets();
    this.scale = Math.min(this.W / 420, this.H / 640);
    this.starfield.layout(this.W, this.H, this.theme.neon);
    const bottomMargin = Math.max(this.insets.bottom, 12) + 22;
    const swapped = this.app.progress.settings.swap;
    const y = this.H - bottomMargin - BASE_R;
    const joyX = swapped ? this.W - 24 - BASE_R : 24 + BASE_R;
    const gasX = swapped ? 26 + GAS_R : this.W - 26 - GAS_R;
    this.joyHome = { x: joyX, y };
    this.gasCenter = { x: gasX, y };
    this.reservedBottom = this.showControls ? bottomMargin + BASE_R * 2 + 16 : 36 + this.insets.bottom;
    this.reservedTop = this.insets.top + 96;
    this.hudLimitY = this.insets.top + 92;
    this.hintEl.textContent = this.showControls ? '' : this.s.keysHint;
    if (!this.camInit && this.world) {
      this.cam = this.cameraTarget();
      this.camInit = true;
    }
  }

  cameraTarget() {
    const w = this.world, l = this.level, scale = this.scale;
    const viewW = this.W / scale, viewH = this.H / scale;
    const bottomUI = this.reservedBottom / scale, topUI = this.reservedTop / scale;
    let x = w.position.x + Math.max(-90, Math.min(90, w.velocity.x * 0.18));
    let y = w.position.y + Math.max(-110, Math.min(110, w.velocity.y * 0.22));
    y -= (bottomUI - topUI) / 2;
    const minX = viewW / 2, maxX = l.width - viewW / 2;
    x = minX > maxX ? l.width / 2 : Math.min(Math.max(x, minX), maxX);
    const minY = viewH / 2 - bottomUI, maxY = l.height - viewH / 2 + topUI;
    y = minY > maxY ? (minY + maxY) / 2 : Math.min(Math.max(y, minY), maxY);
    return { x, y };
  }

  // ---- Input

  isJoyZone(p) { return p.y > this.hudLimitY && (this.app.progress.settings.swap ? p.x > this.W / 2 : p.x < this.W / 2); }
  isGasZone(p) { return p.y > this.hudLimitY && (this.app.progress.settings.swap ? p.x <= this.W / 2 : p.x >= this.W / 2); }

  pointerDown(e) {
    sound.unlock();
    if (e.pointerType === 'mouse' && !this.showControls) {
      this.showControls = true;
      this.layout();
    }
    if (this.paused || this.finished) return;
    const p = this.localPoint(e);
    if (this.isJoyZone(p)) {
      if (!this.joy) {
        this.canvas.setPointerCapture(e.pointerId);
        let c = this.joyHome;
        if (Math.hypot(p.x - c.x, p.y - c.y) > BASE_R * 1.1) {
          const m = BASE_R + 8;
          c = { x: Math.min(Math.max(p.x, m), this.W - m), y: Math.min(Math.max(p.y, this.hudLimitY + m), this.H - m) };
        }
        this.joy = { id: e.pointerId, center: c, knob: { x: 0, y: 0 } };
        this.moveStick(p);
      }
    } else if (this.isGasZone(p)) {
      this.canvas.setPointerCapture(e.pointerId);
      this.gasPointers.add(e.pointerId);
    }
    e.preventDefault();
  }

  pointerMove(e) {
    if (this.joy && e.pointerId === this.joy.id) this.moveStick(this.localPoint(e));
  }

  pointerUp(e) {
    if (this.joy && e.pointerId === this.joy.id) this.joy = null;
    this.gasPointers.delete(e.pointerId);
  }

  localPoint(e) {
    const r = this.canvas.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  }

  moveStick(p) {
    const j = this.joy;
    let vx = p.x - j.center.x, vy = -(p.y - j.center.y);
    const len = Math.hypot(vx, vy);
    if (len > BASE_R) { vx *= BASE_R / len; vy *= BASE_R / len; }
    j.knob = { x: vx, y: vy };
    if (Math.hypot(vx, vy) / BASE_R >= DEAD_ZONE) this.targetAngle = Math.atan2(-vx, vy);
  }

  releaseInput() {
    this.joy = null;
    this.gasPointers.clear();
    this.keys.clear();
    if (this.wasThrusting) {
      this.wasThrusting = false;
      sound.setThrust(false);
    }
  }

  keyDown(e) {
    if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA')) return;
    const k = e.key;
    if (k === 'Escape' || k === 'p' || k === 'P') {
      if (this.phase === 'playing') this.pause(); else if (this.phase === 'paused') this.resume();
      e.preventDefault();
      return;
    }
    if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', ' ', 'a', 'd', 'w', 's', 'A', 'D', 'W', 'S'].includes(k)) {
      sound.unlock();
      if (this.phase === 'playing') this.keys.add(k.length === 1 ? k.toLowerCase() : k);
      e.preventDefault();
    } else if (k === 'r' || k === 'R') {
      if (this.phase !== 'paused') this.restart();
    } else if (k === 'Enter') {
      const primary = this.overlayEl.querySelector('.btn.primary');
      if (primary) primary.click();
    }
  }

  keyUp(e) {
    const k = e.key;
    this.keys.delete(k.length === 1 ? k.toLowerCase() : k);
  }

  currentInput(dt) {
    const input = { thrust: false, targetAngle: null };
    if (this.finished) return input;
    const left = this.keys.has('ArrowLeft') || this.keys.has('a');
    const right = this.keys.has('ArrowRight') || this.keys.has('d');
    const down = this.keys.has('ArrowDown') || this.keys.has('s');
    input.thrust = this.gasPointers.size > 0 || this.keys.has('ArrowUp') || this.keys.has('w') || this.keys.has(' ');
    if (left !== right) {
      // Arrow keys turn at full speed and stop turning when released.
      this.targetAngle = null;
      input.targetAngle = this.world.angle + (left ? 1 : -1);
    } else if (down) {
      this.targetAngle = 0;
      input.targetAngle = 0;
    } else {
      // The stick keeps its last direction after release, like on iPhone.
      input.targetAngle = this.targetAngle;
    }
    if (this.demo) {
      this.demoClock += dt;
      if (this.demoClock > 0.4) {
        input.targetAngle = this.world.position.x < this.level.width / 2 ? -0.22 : 0.22;
        input.thrust = this.world.position.y < this.level.start.y + 150 || this.world.velocity.y < -15;
      }
    }
    return input;
  }

  // ---- Frame loop

  frame(now) {
    let dt = this.lastTime === 0 ? 1 / 60 : now - this.lastTime;
    this.lastTime = now;
    dt = Math.min(Math.max(dt, 0), 1 / 20);
    const w = this.world;
    if (!this.paused) {
      const input = this.currentInput(dt);
      this.accumulator += dt;
      let steps = 0;
      while (this.accumulator >= Physics.step && steps < 60) {
        w.step(Physics.step, input);
        this.accumulator -= Physics.step;
        steps++;
      }
      this.handle(w.drainEvents());
      const thrusting = w.thrusting && !this.finished;
      if (thrusting !== this.wasThrusting) {
        this.wasThrusting = thrusting;
        sound.setThrust(thrusting);
      }
      this.flame += ((thrusting ? 1 : 0) - this.flame) * Math.min(1, dt * 20);
      if (thrusting) this.emitExhaust(dt);
      this.particles.step(dt);
      this.stepEffects(dt);
      this.updateCamera(dt);
      if (this.outcome) {
        this.outcome.delay -= dt;
        if (this.outcome.delay <= 0) {
          const fn = this.outcome.fn;
          this.outcome = null;
          fn();
        }
      }
      if (w.started && this.introEl.style.opacity !== '0') this.showIntro(false);
    }
    this.draw();
    this.hudTimer += dt;
    if (this.hudTimer >= 0.05) {
      this.hudTimer = 0;
      this.renderHUD();
    }
  }

  emitExhaust(dt) {
    const w = this.world;
    this.exhaustAcc += 240 * dt;
    const nozzle = rotate({ x: 0, y: -17 }, w.angle);
    while (this.exhaustAcc >= 1) {
      this.exhaustAcc -= 1;
      const a = w.angle - Math.PI / 2 + (Math.random() - 0.5) * 0.7;
      const v = 170 + (Math.random() - 0.5) * 100;
      this.particles.add({
        x: w.position.x + nozzle.x, y: w.position.y + nozzle.y, vx: Math.cos(a) * v, vy: Math.sin(a) * v,
        age: 0, life: 0.42 + (Math.random() - 0.5) * 0.3, size: 10, sizeSpeed: 1.1, ay: 0,
        colors: ['#FFF6C2', '#FFB13B', '#FF4A2A', '#FF4A2A', '#5A3A55'], alpha: 0.9, alphaSpeed: -2, square: false, spin: 0,
      });
    }
  }

  updateCamera(dt) {
    const target = this.cameraTarget();
    const k = 1 - Math.exp(-dt * 6);
    this.cam.x += (target.x - this.cam.x) * k;
    this.cam.y += (target.y - this.cam.y) * k;
    if (this.shake > 0.1) this.shake *= Math.exp(-dt * 7); else this.shake = 0;
  }

  stepEffects(dt) {
    for (const p of this.popups) p.age += dt;
    this.popups = this.popups.filter((p) => p.age < 0.9);
    for (const f of this.flashes) f.age += dt;
    this.flashes = this.flashes.filter((f) => f.age < 0.35);
    for (const s of this.shards) {
      s.age += dt;
      const k = 1 - Math.exp(-s.age * 4);
      s.x = s.x0 + s.dx * k;
      s.y = s.y0 + s.dy * k;
      s.rot += s.spin * dt;
    }
    this.shards = this.shards.filter((s) => s.age < 0.9);
  }

  // ---- Events

  schedule(delay, fn) { this.outcome = { delay, fn }; }

  handle(events) {
    const t = this.world.time;
    for (const e of events) {
      switch (e.type) {
        case 'star':
          this.gone.stars.set(e.index, t);
          this.sparkle(this.level.stars[e.index], Palette.star);
          sound.play('star');
          haptics.light();
          break;
        case 'fuelCan': {
          this.gone.cans.set(e.index, t);
          const p = this.level.cans[e.index];
          this.sparkle(p, Palette.fuel);
          this.popup(this.s.plusFuel, p, Palette.fuel);
          sound.play('fuel');
          haptics.light();
          break;
        }
        case 'key': {
          this.gone.keys.set(e.index, t);
          const k = this.level.keys[e.index];
          this.sparkle(k.position, keyColor(k.color));
          sound.play('key');
          haptics.medium();
          break;
        }
        case 'doorOpened': {
          this.gone.doors.set(e.index, t);
          const d = this.level.doors[e.index];
          this.sparkle({ x: d.rect.x + d.rect.w / 2, y: d.rect.y + d.rect.h / 2 }, keyColor(d.color), 40, 90);
          sound.play('door');
          break;
        }
        case 'crashed':
          this.explode(e.at);
          break;
        case 'landed':
          this.celebrate();
          break;
        case 'outOfFuel':
          this.finished = true;
          this.releaseInput();
          this.schedule(0.3, () => this.showOverlay('outOfFuel'));
          sound.play('lowfuel');
          haptics.failure();
          break;
        case 'bump': {
          const v = Math.min(1, e.speed / Physics.crashSpeed);
          sound.play('bump', 0.3 + 0.7 * v);
          haptics.impact(v);
          break;
        }
        case 'lowFuel':
          sound.play('lowfuel', 0.7);
          this.popup(this.s.lowFuel, { x: this.world.position.x, y: this.world.position.y + 34 }, Palette.hazard);
          break;
        default:
          break;
      }
    }
  }

  sparkle(p, color, count = 24, speed = 120) {
    this.particles.burst(p.x, p.y, { count, speed, speedRange: speed * 0.5, life: 0.6, lifeRange: 0.3, size: 9, sizeSpeed: -0.35, colors: [color], alpha: 1, alphaSpeed: -1.4 });
  }

  popup(text, p, color) {
    this.popups.push({ text, x: p.x, y: p.y + 18, color, age: 0 });
  }

  explode(point) {
    this.finished = true;
    this.releaseInput();
    const pos = this.world.position;
    const c = { x: pos.x + (point.x - pos.x) * 0.4, y: pos.y + (point.y - pos.y) * 0.4 };
    this.rocketVisible = false;
    this.particles.burst(c.x, c.y, { count: 160, speed: 190, speedRange: 160, life: 0.9, lifeRange: 0.5, size: 16, sizeSpeed: -0.4, colors: ['#FFFFFF', '#FFD25A', Palette.rocketRed, Palette.rocketRed, '#3A2030'], ay: -120, alpha: 1, alphaSpeed: -1 });
    this.flashes.push({ x: c.x, y: c.y, age: 0 });
    for (let i = 0; i < 9; i++) {
      const a = (i / 9) * Math.PI * 2 + (Math.random() - 0.5) * 0.6;
      const d = 50 + Math.random() * 70;
      this.shards.push({ x0: c.x, y0: c.y, x: c.x, y: c.y, dx: Math.cos(a) * d, dy: Math.sin(a) * d - 30, age: 0, rot: 0, spin: (Math.random() - 0.5) * 16, color: i % 3 === 0 ? Palette.rocketRed : Palette.hull });
    }
    this.shake = 12;
    sound.play('crash');
    haptics.heavy();
    this.schedule(1.1, () => this.showOverlay('crashed'));
  }

  celebrate() {
    this.finished = true;
    this.releaseInput();
    const g = this.level.goal;
    this.particles.burst(g.x, g.y + 6, { count: 90, speed: 260, speedRange: 120, life: 1.6, lifeRange: 0.6, size: 7, colors: [Palette.goal, Palette.star, Palette.window, Palette.rocketRed, Palette.goal], ay: -320, angle: Math.PI / 2, spread: 2.2, alpha: 1, alphaSpeed: -0.5, square: true });
    sound.play('land');
    haptics.success();
    const stars = this.world.collectedStars.size, time = this.world.flightTime, fuel = this.world.fuelFraction;
    this.schedule(1.0, () => this.didWin(stars, time, fuel));
  }

  // ---- Drawing

  draw() {
    const ctx = this.ctx, W = this.W, H = this.H, dpr = this.dpr;
    const w = this.world, t = w.time;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const bg = ctx.createLinearGradient(0, 0, 0, H);
    bg.addColorStop(0, this.theme.bgTop);
    bg.addColorStop(1, this.theme.bgBottom);
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, W, H);
    const shakeX = this.shake > 0.1 ? (Math.random() * 2 - 1) * this.shake : 0;
    const shakeY = this.shake > 0.1 ? (Math.random() * 2 - 1) * this.shake : 0;
    const camX = this.cam.x + shakeX, camY = this.cam.y + shakeY;
    this.starfield.draw(ctx, camX * this.scale, camY * this.scale, 1, performance.now() / 1000);

    const s = this.scale * dpr;
    ctx.setTransform(s, 0, 0, -s, dpr * (W / 2 - camX * this.scale), dpr * (H / 2 + camY * this.scale));
    const dyn = {
      t,
      minePos: (i) => w.minePosition(i),
      spinnerAngle: (i) => w.spinnerAngle(i),
      laserState: (i) => w.laserState(i),
      gone: this.gone,
      landLabel: this.s.land,
    };
    drawLevelBack(ctx, this.level, this.theme, dyn);
    this.particles.draw(ctx);
    drawTerrain(ctx, this.terrain, this.theme);
    drawLevelFront(ctx, this.level, this.theme, dyn);

    if (this.rocketVisible) {
      ctx.save();
      ctx.translate(w.position.x, w.position.y);
      ctx.rotate(w.angle);
      drawRocket(ctx, this.flame);
      ctx.restore();
    }
    for (const f of this.flashes) {
      const k = f.age / 0.35;
      ctx.save();
      ctx.globalCompositeOperation = 'lighter';
      ctx.globalAlpha = 0.9 * (1 - k);
      drawGlow(ctx, f.x, f.y, 30 * (1 + 4 * k), '#FFD25A');
      ctx.restore();
    }
    for (const sh of this.shards) {
      ctx.save();
      ctx.globalAlpha = sh.age < 0.5 ? 1 : 1 - (sh.age - 0.5) / 0.4;
      ctx.translate(sh.x, sh.y);
      ctx.rotate(sh.rot);
      ctx.beginPath();
      ctx.moveTo(-3, -2);
      ctx.lineTo(4, -1);
      ctx.lineTo(0, 4);
      ctx.closePath();
      ctx.fillStyle = sh.color;
      ctx.fill();
      ctx.restore();
    }
    for (const p of this.popups) {
      ctx.save();
      ctx.translate(p.x, p.y + 40 * (p.age / 0.9));
      ctx.scale(1, -1);
      ctx.globalAlpha = p.age < 0.5 ? 1 : 1 - (p.age - 0.5) / 0.4;
      ctx.font = '900 14px ui-rounded, system-ui, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillStyle = p.color;
      ctx.fillText(p.text, 0, 0);
      ctx.restore();
    }

    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.drawGoalArrow(ctx, camX, camY);
    if (this.showControls) this.drawControls(ctx);
  }

  drawGoalArrow(ctx, camX, camY) {
    if (this.finished) return;
    const g = this.level.goal;
    const relX = (g.x - camX) * this.scale;
    const relY = (g.y + 10 - camY) * this.scale; // y up, relative to the screen centre
    const halfW = this.W / 2 - 34;
    const yMin = -this.H / 2 + this.reservedBottom + 10;
    const yMax = this.H / 2 - this.reservedTop - 10;
    if (yMax <= yMin) return;
    const cy = (yMin + yMax) / 2, halfH = (yMax - yMin) / 2;
    const dx = relX, dy = relY - cy;
    const tx = Math.abs(dx) > 0.001 ? halfW / Math.abs(dx) : Infinity;
    const ty = Math.abs(dy) > 0.001 ? halfH / Math.abs(dy) : Infinity;
    const tt = Math.min(tx, ty);
    if (tt >= 1) return;
    const px = this.W / 2 + dx * tt, py = this.H / 2 - (cy + dy * tt);
    const pulse = 1 + 0.15 * (0.5 - 0.5 * Math.cos(performance.now() / 1000 * Math.PI * 2));
    ctx.save();
    ctx.translate(px, py);
    ctx.rotate(-(Math.atan2(dy, dx) - Math.PI / 2));
    ctx.scale(pulse, pulse);
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.globalAlpha = 0.45;
    drawGlow(ctx, 0, 0, 22, Palette.goal);
    ctx.restore();
    ctx.beginPath();
    ctx.moveTo(0, -14);
    ctx.lineTo(11, 8);
    ctx.lineTo(0, 3);
    ctx.lineTo(-11, 8);
    ctx.closePath();
    ctx.fillStyle = Palette.goal;
    ctx.fill();
    ctx.strokeStyle = '#FFFFFF';
    ctx.lineWidth = 1.2;
    ctx.stroke();
    ctx.restore();
  }

  drawControls(ctx) {
    const neon = this.theme.neon;
    const j = this.joy;
    const c = j ? j.center : this.joyHome;
    ctx.save();
    ctx.globalAlpha = j ? 1 : 0.75;
    ctx.beginPath();
    ctx.arc(c.x, c.y, BASE_R, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(255,255,255,0.06)';
    ctx.fill();
    ctx.strokeStyle = 'rgba(255,255,255,0.28)';
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.fillStyle = 'rgba(255,255,255,0.35)';
    for (let i = 0; i < 4; i++) {
      ctx.save();
      ctx.translate(c.x, c.y);
      ctx.rotate((i * Math.PI) / 2);
      ctx.fillRect(-1.5, -54, 3, 10);
      ctx.restore();
    }
    ctx.globalAlpha = j ? 1 : 0.7;
    const kx = c.x + (j ? j.knob.x : 0), ky = c.y - (j ? j.knob.y : 0);
    ctx.beginPath();
    ctx.arc(kx, ky, KNOB_R, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(255,255,255,0.85)';
    ctx.fill();
    ctx.strokeStyle = neon;
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.globalAlpha = 1;
    ctx.font = '900 11px ui-rounded, system-ui, sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = 'rgba(255,255,255,0.45)';
    ctx.fillText(this.s.steer, c.x, c.y + BASE_R + 14);

    const g = this.gasCenter;
    const pressed = this.gasPointers.size > 0 || this.keys.has('ArrowUp') || this.keys.has('w') || this.keys.has(' ');
    if (pressed) {
      ctx.save();
      ctx.globalCompositeOperation = 'lighter';
      ctx.globalAlpha = 0.35;
      drawGlow(ctx, g.x, g.y, 90, neon);
      ctx.restore();
    }
    ctx.translate(g.x, g.y);
    ctx.scale(pressed ? 0.92 : 1, pressed ? 0.92 : 1);
    ctx.beginPath();
    ctx.arc(0, 0, GAS_R, 0, Math.PI * 2);
    ctx.fillStyle = rgba(neon, pressed ? 0.5 : 0.16);
    ctx.fill();
    ctx.strokeStyle = neon;
    ctx.lineWidth = 2.5;
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(-7, -22);
    ctx.quadraticCurveTo(-7, -22 + 11, 0, -2);
    ctx.quadraticCurveTo(7, -22 + 11, 7, -22);
    ctx.closePath();
    ctx.fillStyle = lighter(neon, 0.4);
    ctx.fill();
    ctx.fillStyle = '#FFFFFF';
    ctx.font = `900 ${this.s.gas.length > 4 ? 17 : 22}px ui-rounded, system-ui, sans-serif`;
    ctx.fillText(this.s.gas, 0, 12);
    ctx.restore();
  }

  // ---- HUD

  renderHUD() {
    const w = this.world, s = this.s;
    const fuel = w.fuelFraction;
    const fuelColor = fuel > 0.5 ? 'var(--green)' : fuel > 0.2 ? 'var(--gold)' : 'var(--red)';
    const ratio = Math.hypot(w.velocity.x, w.velocity.y) / Physics.crashSpeed;
    const speedColor = ratio < 0.75 ? 'var(--green)' : ratio < 1 ? 'var(--gold)' : 'var(--red)';
    const stars = w.collectedStars.size;
    const keys = w.heldKeyColors;
    let pill = '';
    if (w.tiltedOnGoal) pill = html`<span class="status-pill" style="background:var(--gold)">${s.levelOut}</span>`;
    else if (w.landingProgress > 0.02) pill = html`<span class="status-pill" style="background:var(--green)">${s.touchdown(Math.floor(w.landingProgress * 100))}</span>`;
    const key = [stars, Math.round(fuel * 200), Math.round(ratio * 60), Math.floor(w.flightTime * 10), keys.join(','), w.tiltedOnGoal, Math.floor(w.landingProgress * 100), s.lang].join('|');
    if (key === this.lastHUD) return;
    this.lastHUD = key;
    const starRow = this.starTotal > 0
      ? html`<div class="hud-stars">${Array.from({ length: this.starTotal }, (_, i) => raw(icon(i < stars ? 'star' : 'starOutline', 20, i < stars ? 'star-on' : 'star-off')))}</div>`
      : '';
    setHTML(this.hudEl, html`
      <div class="hud-top">
        <button class="icon-btn" data-act="pause" aria-label="${s.paused}">${raw(icon('pause', 16))}</button>
        <div class="hud-name"><div class="hud-tag">${this.levelTag}</div><div class="hud-title">${this.levelName}</div></div>
        ${starRow}
      </div>
      <div class="hud-gauges">
        <div class="gauge fuel" style="color:${raw(fuelColor)}">${raw(icon('fuel', 14))}<div class="bar"><div style="width:${raw((Math.max(0, Math.min(1, fuel)) * 100).toFixed(1))}%;background:${raw(fuelColor)};box-shadow:0 0 5px ${raw(fuelColor)}"></div></div></div>
        <div class="gauge speed" style="color:${raw(speedColor)}">${raw(icon('speed', 14))}<div class="bar"><div style="width:${raw((58 * Math.max(0.04, Math.min(1, ratio / 1.5))).toFixed(1))}px;background:${raw(speedColor)}"></div><div class="mark"></div></div></div>
        <div class="hud-time">${s.time(w.flightTime)}</div>
      </div>
      <div class="hud-row3">${keys.map((c) => html`<span class="hud-key" style="color:${raw(keyColor(c))}">${raw(icon('key', 14))}</span>`)}${pill}</div>`);
  }

  // ---- Session actions (GameSession.swift)

  action(act) {
    sound.play('click', 0.6);
    switch (act) {
      case 'pause': this.pause(); break;
      case 'resume': this.resume(); break;
      case 'restart': this.restart(); break;
      case 'next': this.nextLevel(); break;
      case 'back': this.quitToLevels(); break;
      case 'menu': this.quitToMenu(); break;
      case 'toggleSound':
        this.app.setSetting('sound', !this.app.progress.settings.sound);
        this.showOverlay('paused');
        break;
      case 'toggleHaptics':
        this.app.setSetting('haptics', !this.app.progress.settings.haptics);
        this.showOverlay('paused');
        break;
      default: break;
    }
  }

  pause() {
    if (this.phase !== 'playing' || this.finished || this.world.status !== 'flying') return;
    this.paused = true;
    this.releaseInput();
    sound.setThrust(false);
    this.phase = 'paused';
    this.showOverlay('paused');
  }

  resume() {
    if (this.phase !== 'paused') return;
    this.paused = false;
    this.lastTime = 0;
    this.phase = 'playing';
    this.overlayEl.innerHTML = '';
  }

  restart() {
    this.attempts += 1;
    this.load();
    this.layout();
  }

  nextLevel() {
    if (!this.hasNext) return;
    this.levelIndex += 1;
    this.attempts = 1;
    this.camInit = false;
    this.load();
    this.layout();
  }

  quitToLevels() {
    sound.setThrust(false);
    if (!this.custom) this.app.go('levels');
    else if (this.custom.origin.type === 'editor') this.app.go('editor', { id: this.custom.origin.levelID });
    else this.app.go('community');
  }

  quitToMenu() {
    sound.setThrust(false);
    this.app.go('menu');
  }

  didWin(stars, time, fuelLeft) {
    let update = { newBestStars: false, newBestTime: false, firstClear: false };
    if (!this.custom) {
      update = this.app.progress.recordWin(this.levelIndex, stars, time);
      if (update.firstClear || update.newBestStars || update.newBestTime) this.app.sync.sync();
    } else if (this.custom.origin.type === 'editor') {
      this.app.maker.recordClear(this.custom.origin.levelID, this.custom.origin.hash, time);
    } else {
      update = this.app.sync.recordClear(this.custom.origin.level.id, time);
    }
    this.result = { stars, time, fuelLeft, par: this.level.par, update };
    this.showOverlay('won');
  }

  showOverlay(kind) {
    if (kind !== 'paused') this.phase = kind;
    const s = this.s;
    const back = html`<button class="btn" data-act="back">${raw(icon(this.backIcon, 17))}<span>${this.backTitle}</span></button>`;
    const menu = html`<button class="btn" data-act="menu">${raw(icon('home', 17))}<span>${s.menu}</span></button>`;
    let body;
    if (kind === 'paused') {
      const st = this.app.progress.settings;
      body = html`
        <h2>${s.paused}</h2>
        <p style="font-size:15px">${this.custom ? this.levelName : s.levelLine(this.levelLabel, this.levelName)}</p>
        ${this.levelHint ? html`<p style="font-size:14px;color:rgba(255,255,255,.6)">${this.levelHint}</p>` : ''}
        <button class="btn primary" data-act="resume">${raw(icon('play', 17))}<span>${s.resume}</span></button>
        <button class="btn" data-act="restart">${raw(icon('restart', 17))}<span>${s.restart}</span></button>
        <div class="row">${back}${menu}</div>
        <div class="toggle-chips">
          <button class="chip-btn" data-act="toggleSound" style="opacity:${st.sound ? 1 : 0.45}">${raw(icon(st.sound ? 'speaker' : 'mute', 16))}${s.sound}</button>
          <button class="chip-btn" data-act="toggleHaptics" style="opacity:${st.haptics ? 1 : 0.45}">${raw(icon('vibrate', 16))}${s.haptics}</button>
        </div>`;
    } else if (kind === 'crashed' || kind === 'outOfFuel') {
      const fuel = kind === 'outOfFuel';
      const tips = fuel ? s.fuelTips : s.crashTips;
      const tip = tips[(this.attempts - 1 + this.levelIndex) % tips.length];
      body = html`
        <div style="color:${raw(fuel ? 'var(--orange)' : 'var(--red)')}">${raw(icon(fuel ? 'fuel' : 'flame', 34))}</div>
        <h2>${fuel ? s.outOfFuel : s.crashed}</h2>
        <p>${tip}</p>
        <p style="font-size:12px;color:rgba(255,255,255,.4)">${s.attempt(this.attempts)}</p>
        <button class="btn primary" data-act="restart">${raw(icon('restart', 17))}<span>${s.tryAgain}</span></button>
        <div class="row">${back}${menu}</div>`;
    } else {
      const r = this.result;
      const total = this.starTotal;
      const perfect = total > 0 && r.stars >= total;
      const starsRow = total > 0 ? html`<div class="big-stars">${Array.from({ length: total }, (_, i) =>
        raw(`<span style="animation-delay:${0.15 + 0.18 * i}s">${icon(i < r.stars ? 'star' : 'starOutline', 42, `${i < r.stars ? 'star-on' : 'star-off'} ${total === 3 && i === 1 ? 'mid' : ''}`)}</span>`))}</div>` : '';
      const stat = (ic, label, value, badge) => html`<div class="stat"><span style="color:var(--accent)">${raw(icon(ic, 14))}</span><span class="label">${label}</span>${badge ? html`<span class="badge">${badge}</span>` : ''}<span class="value">${value}</span></div>`;
      let actions;
      if (this.custom) {
        actions = this.custom.origin.type === 'editor'
          ? html`<p class="green" style="font-weight:800">${s.testCleared}</p><button class="btn primary" data-act="back">${raw(icon('hammer', 17))}<span>${s.editorButton}</span></button>`
          : html`<div class="like-slot"></div><button class="btn primary" data-act="back">${raw(icon('people', 17))}<span>${s.communityButton}</span></button>`;
        actions = html`${actions}<button class="btn" data-act="restart">${raw(icon('restart', 17))}<span>${s.retry}</span></button>`;
      } else {
        actions = html`
          ${this.hasNext ? '' : html`<p class="gold" style="font-weight:800">${s.allDone}</p>`}
          ${this.hasNext
            ? html`<button class="btn primary" data-act="next">${raw(icon('play', 17))}<span>${s.nextLevel}</span></button>`
            : html`<button class="btn primary" data-act="menu">${raw(icon('home', 17))}<span>${s.mainMenu}</span></button>`}
          <div class="row"><button class="btn" data-act="restart">${raw(icon('restart', 17))}<span>${s.retry}</span></button>${back}</div>`;
      }
      body = html`
        <h2 style="text-shadow:0 0 14px rgba(68,255,136,.8)">${perfect ? s.perfect : s.landed}</h2>
        ${starsRow}
        <div class="stats-box">
          ${stat('timer', s.timeLabel, s.time(r.time), r.update.newBestTime ? s.newBest : null)}
          ${stat('flag', s.parLabel, s.wholeSeconds(r.par), r.time <= r.par ? s.underPar : null)}
          ${stat('fuel', s.fuelLeft, `${Math.round(r.fuelLeft * 100)}%`, null)}
        </div>
        ${actions}`;
    }
    setHTML(this.overlayEl, html`<div class="overlay"><div class="overlay-card">${body}</div></div>`);
    const slot = this.overlayEl.querySelector('.like-slot');
    if (slot && this.custom && this.custom.origin.type === 'community') mountLikeButton(slot, this.app, this.custom.origin.level);
  }
}
