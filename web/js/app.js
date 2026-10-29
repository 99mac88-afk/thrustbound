// Navigation and shared state for the web version.
import { L10n, detectLang } from './i18n.js';
import { Progress } from './store.js';
import { haptics, sound } from './audio.js';
import { AccountStore, CommunityStore } from './online.js';
import { LevelStore } from './maker.js';
import { MenuScreen, LevelsScreen, HowToScreen, SettingsScreen } from './ui.js';
import { GameScreen } from './game.js';
import { CommunityScreen } from './community.js';
import { MakerScreen, EditorScreen } from './maker.js';
import { MenuBackground } from './background.js';
import { fitText } from './dom.js';

const SCREENS = {
  menu: MenuScreen, levels: LevelsScreen, howto: HowToScreen, settings: SettingsScreen,
  game: GameScreen, custom: GameScreen, community: CommunityScreen, maker: MakerScreen, editor: EditorScreen,
};
const BACKGROUND = new Set(['menu', 'levels', 'howto', 'settings', 'community', 'maker']);

export class App {
  constructor(library, bundledServer, version, options = {}) {
    this.library = library;
    this.version = version;
    this.options = options;
    this.progress = new Progress(library.levels);
    this.maker = new LevelStore();
    this.account = new AccountStore(bundledServer);
    this.community = new CommunityStore(this.account);
    this.isTouch = (globalThis.matchMedia && matchMedia('(pointer: coarse)').matches) || (navigator.maxTouchPoints || 0) > 0;
    this.screenEl = document.getElementById('screen');
    this.background = new MenuBackground(document.getElementById('bg'));
    this.current = null;
    this.currentName = null;
    this.applySettings();
    // Any re-rendered screen part gets its labels fitted again.
    new MutationObserver(() => this.fit()).observe(document.body, { childList: true, subtree: true });
    window.addEventListener('resize', () => this.fit());
    this.probe = document.createElement('div');
    this.probe.style.cssText = 'position:fixed;left:0;top:0;visibility:hidden;pointer-events:none;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';
    document.body.appendChild(this.probe);
    const unlock = () => sound.unlock();
    window.addEventListener('pointerdown', unlock, { capture: true });
    window.addEventListener('keydown', unlock, { capture: true });
  }

  get lang() {
    if (this.options.lang === 'en' || this.options.lang === 'ru') return this.options.lang;
    const v = this.progress.settings.language;
    return v === 'en' || v === 'ru' ? v : detectLang();
  }

  get s() {
    if (!this._s || this._s.lang !== this.lang) this._s = new L10n(this.lang);
    return this._s;
  }

  applySettings() {
    sound.enabled = this.progress.settings.sound;
    haptics.enabled = this.progress.settings.haptics;
    if (!sound.enabled) sound.stopAll();
    document.documentElement.lang = this.lang;
  }

  setSetting(key, value) {
    this.progress.settings[key] = value;
    this.progress.saveSettings();
    this.applySettings();
  }

  insets() {
    const cs = getComputedStyle(this.probe);
    const n = (v) => parseFloat(v) || 0;
    return { top: n(cs.paddingTop), right: n(cs.paddingRight), bottom: n(cs.paddingBottom), left: n(cs.paddingLeft) };
  }

  levelLabel(index) {
    const level = this.library.levels[index];
    const inWorld = this.library.levels.map((l, i) => [l, i]).filter(([l]) => l.world === level.world).map(([, i]) => i);
    return `${level.world + 1}-${inWorld.indexOf(index) + 1}`;
  }

  go(name, params = {}) {
    const Screen = SCREENS[name] || MenuScreen;
    if (this.currentName === 'editor' && name !== 'editor' && name !== 'custom') this.maker.closeSession();
    if (this.current) {
      try { this.current.unmount(); } catch (e) { console.error(e); }
    }
    sound.setThrust(false);
    this.screenEl.innerHTML = '';
    document.querySelectorAll('.sheet-wrap, .dialog-wrap').forEach((el) => el.remove());
    const root = document.createElement('div');
    root.className = 'screen';
    this.screenEl.appendChild(root);
    this.currentName = name;
    this.currentParams = params;
    this.current = new Screen(this, { ...params, demo: params.demo || false });
    this.background.setActive(BACKGROUND.has(name));
    this.current.mount(root);
    document.documentElement.lang = this.lang;
    this.fit();
  }

  /** Re-fits labels after anything re-renders (cheap, runs on the next frame). */
  fit() {
    if (this.fitPending) return;
    this.fitPending = true;
    requestAnimationFrame(() => {
      this.fitPending = false;
      fitText(document.body);
    });
  }

  /** Android back button / Escape outside the game. Returns false when there is nowhere to go back to. */
  back() {
    const open = document.querySelector('.dialog-wrap, .sheet-wrap');
    if (open) {
      open.remove();
      return true;
    }
    switch (this.currentName) {
      case 'menu': return false;
      case 'game':
      case 'custom':
        if (this.current.phase === 'playing' && !this.current.finished) this.current.pause();
        else if (this.current.phase === 'paused') this.current.resume();
        else this.current.quitToLevels();
        return true;
      case 'editor': this.go('maker'); return true;
      default: this.go('menu'); return true;
    }
  }
}
