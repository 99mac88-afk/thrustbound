// Main menu, level select, how to play and settings (port of the SwiftUI screens).
import { html, onAction, raw, setHTML, dialog } from './dom.js';
import { icon } from './icons.js';
import { drawRocket, flamePath } from './art.js';
import { detectLang } from './i18n.js';
import { sound } from './audio.js';
import { deviceInfo, openGetApp } from './device.js';

const accentVars = (hex) => {
  const h = (hex || '#3BE3FF').replace('#', '');
  return `--accent:#${h};--accent-rgb:${parseInt(h.slice(0, 2), 16)},${parseInt(h.slice(2, 4), 16)},${parseInt(h.slice(4, 6), 16)}`;
};

/** The animated rocket on the main menu (RocketGlyph). */
function mountRocketGlyph(canvas, height) {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const w = 110, h = height;
  canvas.width = w * dpr;
  canvas.height = h * dpr;
  canvas.style.width = `${w}px`;
  canvas.style.height = `${h}px`;
  const ctx = canvas.getContext('2d');
  let raf = 0;
  const draw = (ts) => {
    const t = ts / 1000;
    const s = h / 64;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);
    ctx.setTransform(dpr * s, 0, 0, -dpr * s, (dpr * w) / 2, dpr * (h / 2 - 9.5 * s));
    ctx.save();
    ctx.translate(0, -15);
    ctx.scale(1, 1 + 0.18 * Math.sin(t * 31) + 0.08 * Math.sin(t * 53));
    ctx.fillStyle = '#FF7A2E';
    ctx.fill(flamePath(24, 10));
    ctx.fillStyle = '#FFF4B0';
    ctx.fill(flamePath(13, 6));
    ctx.restore();
    drawRocket(ctx, 0);
    raf = requestAnimationFrame(draw);
  };
  raf = requestAnimationFrame(draw);
  return () => cancelAnimationFrame(raf);
}

export class MenuScreen {
  constructor(app) { this.app = app; }

  mount(root) {
    const { app } = this;
    const s = app.s;
    const p = app.progress;
    const next = p.continueIndex;
    const level = app.library.levels[next];
    const dev = deviceInfo();
    const label = level ? app.levelLabel(next) : '';
    root.className = 'screen menu';
    setHTML(root, html`
      <div class="hero">
        <div class="rocket-wrap"><canvas></canvas></div>
        <h1 class="game-title">THRUSTBOUND</h1>
        <p class="tagline">${s.tagline}</p>
      </div>
      <div class="buttons">
        <button class="btn primary" data-act="play" style="height:62px">${raw(icon('play', 18))}<span>${p.hasProgress ? s.continueGame : s.play}</span></button>
        ${level ? html`<div class="next-level">${s.levelLine(label, s.name(level))}</div>` : ''}
        <button class="btn" data-act="levels">${raw(icon('grid', 17))}<span>${s.levelsButton}</span></button>
        <div class="row">
          <button class="btn" data-act="community">${raw(icon('people', 18))}<span>${s.communityButton}</span></button>
          <button class="btn" data-act="maker">${raw(icon('hammer', 17))}<span>${s.makerButton}</span></button>
        </div>
        <div class="row">
          <button class="btn" data-act="howto">${raw(icon('question', 17))}<span>${s.howToButton}</span></button>
          <button class="btn" data-act="settings">${raw(icon('gear', 17))}<span>${s.settingsButton}</span></button>
        </div>
        ${dev.inApp ? '' : html`<button class="get-app" data-act="getapp">${raw(icon(dev.os === 'ios' ? 'apple' : dev.os === 'android' ? 'android' : 'phone', 28))}
          <span><b>${s.getApp}</b><small>${dev.os === 'ios' ? s.iphoneApp : dev.os === 'android' ? s.androidApp : s.phoneTitle}</small></span></button>`}
      </div>
      <div class="stats">
        <span>${raw(icon('star', 15))}${p.totalStars}/${p.maxStars}</span>
        <span>${raw(icon('flag', 15))}${p.completedCount}/${app.library.levels.length}</span>
      </div>`);
    this.stopGlyph = mountRocketGlyph(root.querySelector('canvas'), Math.min(170, window.innerHeight * 0.19));
    this.off = onAction(root, (act) => {
      sound.unlock();
      sound.play('click', 0.6);
      if (act === 'play') app.go('game', { levelIndex: next });
      else if (act === 'getapp') openGetApp(app);
      else app.go(act);
    });
  }

  unmount() {
    this.stopGlyph();
    this.off();
  }
}

export class LevelsScreen {
  constructor(app) { this.app = app; }

  mount(root) {
    const { app } = this;
    const s = app.s;
    const p = app.progress;
    const lib = app.library;
    const worlds = [...new Set(lib.levels.map((l) => l.world))].sort((a, b) => a - b);
    root.className = 'screen';
    setHTML(root, html`
      <div class="header narrow">
        <button class="icon-btn" data-act="back">${raw(icon('back', 18))}</button>
        <h1>${s.levelsTitle}</h1>
        <span class="pill">${raw(icon('star', 15, 'gold'))}${p.totalStars}/${p.maxStars}</span>
      </div>
      <div class="scroll"><div class="narrow" style="padding-top:8px">
        ${worlds.map((wi) => {
          const info = lib.worlds[wi];
          const idx = lib.levels.map((l, i) => [l, i]).filter(([l]) => l.world === wi).map(([, i]) => i);
          const got = idx.reduce((n, i) => n + (p.record(i) ? p.record(i).stars : 0), 0);
          return html`<section class="world" id="world-${wi}" style="${raw(accentVars(info && info.neon))}">
            <div class="world-head">
              <div><div class="world-tag">${s.worldTag(wi)}</div><div class="world-name">${s.worldName(info, wi)}</div><div class="world-sub">${s.worldSubtitle(info)}</div></div>
              <span style="display:flex;gap:4px;align-items:center;font-size:14px">${raw(icon('star', 14, 'gold'))}${got}/${idx.length * 3}</span>
            </div>
            <div class="tiles">${idx.map((i, n) => {
              const rec = p.record(i);
              if (!p.isUnlocked(i)) return html`<button class="tile locked">${raw(icon('lock', 18))}</button>`;
              const st = rec ? rec.stars : 0;
              return html`<button class="tile ${rec ? 'done' : ''}" data-act="play" data-i="${i}">${n + 1}
                <span class="stars-mini">${[0, 1, 2].map((k) => raw(icon(k < st ? 'star' : 'starOutline', 10, k < st ? 'star-on' : 'star-off')))}</span></button>`;
            })}</div>
          </section>`;
        })}
      </div></div>`);
    this.off = onAction(root, (act, el) => {
      sound.play('click', 0.6);
      if (act === 'back') app.go('menu');
      else if (act === 'play') app.go('game', { levelIndex: Number(el.dataset.i) });
    });
    const target = lib.levels[p.continueIndex].world;
    if (target > 0) {
      requestAnimationFrame(() => {
        const sec = root.querySelector(`#world-${target}`);
        if (sec) sec.scrollIntoView({ block: 'start' });
      });
    }
  }

  unmount() { this.off(); }
}

export class HowToScreen {
  constructor(app) { this.app = app; }

  mount(root) {
    const { app } = this;
    const s = app.s;
    const colors = ['var(--cyan)', 'var(--orange)', 'var(--green)', 'var(--gold)', 'var(--orange)', 'var(--red)', '#8FD3FF', '#FFC23D'];
    const icons = ['gamecontroller', 'flame', 'landing', 'star', 'fuel', 'warning', 'wind', 'key'];
    root.className = 'screen';
    setHTML(root, html`
      <div class="header narrow"><button class="icon-btn" data-act="back">${raw(icon('back', 18))}</button><h1>${s.howToTitle}</h1></div>
      <div class="scroll"><div class="narrow stack">
        <div class="diagram">
          <canvas style="position:absolute;left:50%;top:18px;transform:translateX(-50%) rotate(-18deg)"></canvas>
          <div style="position:absolute;left:18px;right:18px;bottom:16px;display:flex;justify-content:space-between;align-items:flex-end">
            <div style="text-align:center;width:72px">
              <div style="width:72px;height:72px;border-radius:50%;border:2px solid rgba(255,255,255,.35);position:relative">
                <div style="position:absolute;width:30px;height:30px;border-radius:50%;background:rgba(255,255,255,.85);left:9px;top:11px"></div></div>
              <div class="muted" style="font-size:11px;margin-top:8px">${s.steer}</div></div>
            <div style="text-align:center;width:72px">
              <div style="width:66px;height:66px;margin:0 auto;border-radius:50%;border:2px solid var(--cyan);background:rgba(59,227,255,.25);display:flex;align-items:center;justify-content:center;font-size:15px">${s.gas}</div>
              <div class="muted" style="font-size:11px;margin-top:8px">${s.thrust}</div></div>
          </div>
        </div>
        ${app.isTouch ? '' : html`<div class="card center" style="font-size:14px">${s.keysHint}</div>`}
        ${s.tips.map((tip, i) => html`<div class="card tip"><div class="bubble" style="color:${raw(colors[i % colors.length])};background:rgba(255,255,255,.08)">${raw(icon(icons[i], 20))}</div>
          <div><h3>${tip.title}</h3><p>${tip.text}</p></div></div>`)}
        <button class="btn primary" data-act="fly" style="margin-top:8px">${raw(icon('play', 17))}<span>${s.letsFly}</span></button>
      </div></div>`);
    this.stopGlyph = mountRocketGlyph(root.querySelector('canvas'), 70);
    this.off = onAction(root, (act) => {
      sound.play('click', 0.6);
      if (act === 'back') app.go('menu');
      else if (act === 'fly') app.go('game', { levelIndex: app.progress.continueIndex });
    });
  }

  unmount() {
    this.stopGlyph();
    this.off();
  }
}

export class SettingsScreen {
  constructor(app) { this.app = app; }

  mount(root) {
    this.root = root;
    root.className = 'screen';
    this.render();
    this.off = onAction(root, (act, el) => {
      const { app } = this;
      sound.play('click', 0.6);
      if (act === 'back') return app.go('menu');
      if (act === 'lang') {
        app.setSetting('language', el.dataset.v);
        return this.render();
      }
      if (act === 'toggle') {
        const key = el.dataset.k;
        app.setSetting(key, !app.progress.settings[key]);
        return this.render();
      }
      if (act === 'reset') {
        const s = app.s;
        dialog(s.resetConfirmTitle, s.resetConfirmMessage, [
          { label: s.cancel, role: 'cancel' },
          { label: s.reset, role: 'destructive', action: () => { app.progress.reset(); this.render(); } },
        ]);
      }
      return null;
    });
  }

  render() {
    const { app } = this;
    const s = app.s;
    const st = app.progress.settings;
    const toggle = (k, ic, title, sub) => html`<div class="card setting"><div class="bubble">${raw(icon(ic, 18))}</div>
      <div class="text"><div class="title">${title}</div><div class="sub">${sub}</div></div>
      <button class="switch ${st[k] ? 'on' : ''}" data-act="toggle" data-k="${k}" aria-label="${title}"></button></div>`;
    const choice = (label, v) => html`<button class="choice ${st.language === v ? 'on' : ''}" data-act="lang" data-v="${v}">${label}</button>`;
    setHTML(this.root, html`
      <div class="header narrow"><button class="icon-btn" data-act="back">${raw(icon('back', 18))}</button><h1>${s.settingsTitle}</h1></div>
      <div class="scroll"><div class="narrow stack">
        <div class="card">
          <div class="setting"><div class="bubble">${raw(icon('globe', 18))}</div>
            <div class="text"><div class="title">${s.languageTitle}</div><div class="sub">${st.language === 'system' ? s.languageAuto(detectLang()) : s.languageManual}</div></div></div>
          <div class="choices">${choice(s.languageSystem, 'system')}${choice('English', 'en')}${choice('Русский', 'ru')}</div>
        </div>
        ${toggle('sound', 'speaker', s.soundEffects, s.soundEffectsDetail)}
        ${toggle('haptics', 'vibrate', s.vibration, s.vibrationDetail)}
        ${toggle('swap', 'swap', s.leftHanded, s.leftHandedDetail)}
        ${toggle('unlockAll', 'unlock', s.unlockAll, s.unlockAllDetail)}
        <button class="card setting" data-act="reset" style="border:0;width:100%;text-align:left;color:#fff">
          <div class="bubble" style="color:var(--red);background:rgba(255,46,77,.15)">${raw(icon('trash', 18))}</div>
          <div class="text"><div class="title">${s.resetProgress}</div><div class="sub">${s.resetProgressDetail}</div></div></button>
        <div class="center" style="margin-top:20px">
          <div style="font-size:16px;font-weight:900;letter-spacing:2px;color:var(--cyan)">THRUSTBOUND</div>
          <div class="muted small-text">${s.version(app.version, app.library.levels.length)}</div>
        </div>
      </div></div>`);
  }

  unmount() { this.off(); }
}
