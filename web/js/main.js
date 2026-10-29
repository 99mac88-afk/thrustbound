// Entry point: loads the levels and the server settings, then starts the app.
import { parseLibrary } from './levels.js';
import { App } from './app.js';

// Canvas roundRect for older browsers (Safari < 16).
for (const proto of [globalThis.CanvasRenderingContext2D && CanvasRenderingContext2D.prototype, globalThis.Path2D && Path2D.prototype]) {
  if (proto && !proto.roundRect) {
    proto.roundRect = function roundRect(x, y, w, h, r) {
      const rr = Math.max(0, Math.min(typeof r === 'number' ? r : 0, Math.abs(w) / 2, Math.abs(h) / 2));
      this.moveTo(x + rr, y);
      this.arcTo(x + w, y, x + w, y + h, rr);
      this.arcTo(x + w, y + h, x, y + h, rr);
      this.arcTo(x, y + h, x, y, rr);
      this.arcTo(x, y, x + w, y, rr);
      this.closePath();
    };
  }
}

async function loadJSON(url, fallback) {
  try {
    const res = await fetch(url, { cache: 'no-cache' });
    if (!res.ok) throw new Error(String(res.status));
    return await res.json();
  } catch {
    return fallback;
  }
}

async function start() {
  const [levels, server, info] = await Promise.all([
    loadJSON('levels.json', null),
    loadJSON('backend.json', null),
    loadJSON('build-info.json', { version: 'dev' }),
  ]);
  if (!levels) {
    document.getElementById('screen').innerHTML = '<div style="margin:auto;text-align:center;padding:30px">Levels could not be loaded.<br>Не удалось загрузить уровни.</div>';
    return;
  }
  const params = new URLSearchParams(location.search);
  const app = new App(parseLibrary(levels), server, info.version || 'dev', { lang: params.get('lang') });
  window.thrustbound = app;
  // The Android app calls this for its back button.
  window.__thrustboundBack = () => app.back();
  const screen = params.get('screen');
  if (screen === 'game' || screen === 'custom-sample') {
    const n = Math.max(1, Math.min(app.library.levels.length, Number(params.get('level')) || 1));
    app.go('game', { levelIndex: n - 1, demo: params.get('demo') === '1' });
  } else if (screen && ['levels', 'howto', 'settings', 'community', 'maker'].includes(screen)) {
    app.go(screen);
  } else if (screen === 'editor') {
    const sample = app.maker.levels.find((l) => l.name === app.s.exampleName) || app.maker.addSample(0, app.s.exampleName);
    app.go('editor', { id: sample.id });
  } else {
    app.go('menu');
  }
}

start();
