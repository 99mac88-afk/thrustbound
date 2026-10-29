// Which device is this, and which app should we recommend?
import { html, raw, setHTML, sheet } from './dom.js';
import { icon } from './icons.js';
import { sound } from './audio.js';

export const REPO = 'https://github.com/99mac88-afk/rocket';
export const DOWNLOADS = {
  ios: `${REPO}/releases/latest/download/Thrustbound.ipa`,
  android: `${REPO}/releases/latest/download/Thrustbound.apk`,
  all: `${REPO}/releases/latest`,
};

export function deviceInfo(ua = navigator.userAgent || '', platform = navigator.platform || '', touchPoints = navigator.maxTouchPoints || 0) {
  const android = /Android/i.test(ua);
  // iPadOS reports itself as a Mac, but Macs have no touch screen.
  const ios = !android && (/iPhone|iPad|iPod/i.test(ua) || (/Mac/i.test(platform) && touchPoints > 1));
  const inApp = /ThrustboundApp/.test(ua);
  let standalone = false;
  try {
    standalone = (globalThis.matchMedia && matchMedia('(display-mode: standalone)').matches) || navigator.standalone === true;
  } catch { /* old browser */ }
  return { os: ios ? 'ios' : android ? 'android' : 'desktop', inApp, standalone };
}

/** The "get the app" sheet: recommends the version for this phone. */
export function openGetApp(app) {
  const s = app.s;
  const dev = deviceInfo();
  const choice = (os, best) => html`<a class="app-choice ${best ? 'best' : ''}" href="${DOWNLOADS[os]}" data-os="${os}" rel="noopener">
      <span class="logo">${raw(icon(os === 'ios' ? 'apple' : 'android', 28))}</span>
      <span class="what">${best ? html`<span class="rec">${s.recommended}</span>` : ''}<b>${os === 'ios' ? s.iphoneApp : s.androidApp}</b>
        <small>${os === 'ios' ? s.iphoneSteps : s.androidSteps}</small></span>
      <span style="color:var(--green)">${raw(icon('download', 22))}</span></a>`;
  const intro = dev.os === 'ios' ? s.onIPhone : dev.os === 'android' ? s.onAndroid : s.onDesktop;
  const order = dev.os === 'android' ? ['android', 'ios'] : ['ios', 'android'];
  sheet((el, close) => {
    setHTML(el, html`
      <div class="sheet-head"><h2>${s.phoneTitle}</h2><button class="link-btn" data-close>${s.close}</button></div>
      <div class="stack">
        <p class="muted" style="margin:0;font-size:15px">${s.phoneIntro}</p>
        <p style="margin:0;font-size:15px">${intro}</p>
        ${order.map((os, i) => choice(os, dev.os !== 'desktop' && i === 0))}
        ${dev.os === 'ios' && !dev.standalone ? html`<div class="note" style="background:rgba(59,227,255,.1)">${raw(icon('sparkles', 18, 'cyan'))}<span>${s.homeScreenTip}</span></div>` : ''}
        <a class="muted small-text center" href="${DOWNLOADS.all}" rel="noopener" style="color:rgba(255,255,255,.6)">${s.allVersions} ↗</a>
        <button class="btn primary" data-close>${raw(icon('play', 17))}<span>${s.keepPlaying}</span></button>
      </div>`);
    el.addEventListener('click', (e) => {
      if (e.target.closest('[data-close]')) {
        sound.play('click', 0.6);
        close();
      }
    });
  });
}
