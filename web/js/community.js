// Community browser, level details, likes and the account sheet (port of CommunityView.swift / AccountSheet.swift).
import { html, onAction, raw, setHTML, sheet, dialog } from './dom.js';
import { icon } from './icons.js';
import { compile } from './compiler.js';
import { TABS, USERNAME_RE } from './online.js';
import { haptics, sound } from './audio.js';

export class CommunityScreen {
  constructor(app) {
    this.app = app;
    this.tab = app.communityTab || 'newest';
  }

  mount(root) {
    this.root = root;
    root.className = 'screen';
    this.render();
    const refresh = () => this.renderList();
    this.offStore = this.app.community.on(refresh);
    let lastViewer = this.app.community.viewerKey;
    this.offAccount = this.app.account.on(() => {
      this.renderHeader();
      if (this.app.community.viewerKey !== lastViewer) {
        lastViewer = this.app.community.viewerKey;
        this.app.community.reset();
        this.app.community.reload(this.tab);
      }
    });
    this.off = onAction(root, (act, el) => this.action(act, el));
    this.onScroll = () => {
      const sc = this.root.querySelector('.scroll');
      if (sc && sc.scrollTop + sc.clientHeight > sc.scrollHeight - 300) this.app.community.loadMore(this.tab);
    };
    root.addEventListener('scroll', this.onScroll, true);
    if (this.app.account.isConfigured) this.app.community.loadIfNeeded(this.tab);
  }

  unmount() {
    this.offStore();
    this.offAccount();
    this.off();
    this.root.removeEventListener('scroll', this.onScroll, true);
  }

  render() {
    const s = this.app.s;
    setHTML(this.root, html`
      <div class="header narrow head-slot"></div>
      ${this.app.account.isConfigured ? html`<div class="tabs narrow">${TABS.map((t) => html`<button class="tab ${t === this.tab ? 'on' : ''}" data-act="tab" data-tab="${t}">${s.tabName(t)}</button>`)}</div>` : ''}
      <div class="scroll"><div class="narrow list-slot"></div></div>`);
    this.renderHeader();
    this.renderList();
  }

  renderHeader() {
    const { app } = this;
    const s = app.s, a = app.account;
    const slot = this.root.querySelector('.head-slot');
    if (!slot) return;
    setHTML(slot, html`
      <button class="icon-btn" data-act="back">${raw(icon('back', 18))}</button>
      <h1>${s.communityTitle}</h1>
      ${a.isConfigured ? html`<button class="icon-btn" data-act="reload" aria-label="Reload">${raw(icon('restart', 17))}</button>` : ''}
      <button class="chip-btn" data-act="account">${raw(icon(a.isSignedIn ? 'person' : 'personPlus', 16))}
        <span style="max-width:110px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${a.profile ? a.profile.username : a.isSignedIn ? s.accountTitle : s.signIn}</span>
        ${a.isAdmin ? raw(icon('shield', 14, 'gold')) : ''}</button>`);
  }

  renderList() {
    const { app } = this;
    const s = app.s, c = app.community, a = app.account;
    const slot = this.root.querySelector('.list-slot');
    if (!slot) return;
    const message = (text, ic, extra) => html`<div class="empty">${raw(icon(ic, 30, 'cyan'))}<div style="font-size:15px;font-weight:600;color:rgba(255,255,255,.8)">${text}</div>${extra}</div>`;
    if (!a.isConfigured) {
      setHTML(slot, message(s.notConfiguredBody, 'server', html`<button class="btn" data-act="account">${raw(icon('gear', 17))}<span>${s.serverTitle}</span></button>`));
      return;
    }
    if (this.tab === 'mine' && !a.isSignedIn) {
      setHTML(slot, message(s.signInForMine, 'person', html`<button class="btn primary" data-act="account">${raw(icon('person', 17))}<span>${s.signIn}</span></button>`));
      return;
    }
    const levels = c.levels(this.tab);
    let footer = '';
    if (c.loading.has(this.tab)) footer = html`<div class="spinner"></div>`;
    else if (c.errors[this.tab]) footer = message(s.onlineError(c.errors[this.tab]), 'wifiOff', html`<button class="btn" data-act="reload">${raw(icon('restart', 17))}<span>${s.retryShort}</span></button>`);
    else if (levels.length === 0 && c.lists[this.tab]) {
      footer = message(this.tab === 'mine' ? s.emptyMine : s.emptyList, this.tab === 'mine' ? 'hammer' : 'sparkles', html`<button class="btn" data-act="maker">${raw(icon('hammer', 17))}<span>${s.makerButton}</span></button>`);
    }
    setHTML(slot, html`${levels.map((l) => {
      const liked = c.liked.has(l.id);
      return html`<button class="level-row" data-act="open" data-id="${l.id}">
        <div class="main"><div class="name">${l.title}${l.authorID === a.userID ? html`<span class="tag-mini">${s.yours}</span>` : ''}</div>
          <div class="meta">${s.byAuthor(l.author)}${l.createdAt ? ` · ${s.ago(l.createdAt)}` : ''}</div></div>
        <div class="counts"><span style="color:${raw(liked ? 'var(--red)' : '#fff')}">${raw(icon(liked ? 'heart' : 'heartOutline', 14))}${l.likes}</span>
          <span style="color:rgba(255,255,255,.7)">${raw(icon('eye', 14))}${l.views}</span></div>
        <span style="color:rgba(255,255,255,.35)">${raw(icon('back', 13, '').replace('<svg', '<svg style="transform:scaleX(-1)"'))}</span>
      </button>`;
    })}${footer}`);
  }

  action(act, el) {
    const { app } = this;
    sound.play('click', 0.6);
    switch (act) {
      case 'back': app.go('menu'); break;
      case 'tab':
        this.tab = el.dataset.tab;
        app.communityTab = this.tab;
        this.render();
        app.community.loadIfNeeded(this.tab);
        break;
      case 'reload': app.community.reload(this.tab); break;
      case 'account': openAccount(app); break;
      case 'maker': app.go('maker'); break;
      case 'open': {
        const level = app.community.find(el.dataset.id);
        if (level) openDetail(app, level);
        break;
      }
      default: break;
    }
  }
}

function openDetail(app, level) {
  const s = app.s;
  let busy = false;
  let errorText = '';
  sheet((el, close) => {
    const off = app.community.on(() => { if (el.isConnected) render(); else off(); });
    const render = () => {
      const cur = app.community.find(level.id) || level;
      const mine = cur.authorID === app.account.userID;
      const adminDelete = app.account.isAdmin && !mine;
      setHTML(el, html`
        <div class="sheet-head"><span></span><button class="link-btn" data-act="close">${s.done}</button></div>
        <div class="stack center">
          <div style="color:var(--green)">${raw(icon('checkered', 40))}</div>
          <h2 style="margin:0;font-size:28px;font-weight:900;word-break:break-word">${cur.title}</h2>
          <div class="muted">${s.byAuthor(cur.author)}${cur.createdAt ? ` · ${s.ago(cur.createdAt)}` : ''}</div>
          <div style="display:flex;gap:12px;justify-content:center;flex-wrap:wrap">
            <span class="pill" style="background:rgba(59,227,255,.15)">${raw(icon('eye', 15))}${s.viewsCount(cur.views)}</span>
            <span class="pill" style="background:rgba(255,46,77,.15)">${raw(icon('heart', 15))}${s.likesCount(cur.likes)}</span>
          </div>
          <button class="btn primary ${busy ? 'disabled' : ''}" data-act="play" style="height:60px">${busy ? html`<span class="spinner" style="width:22px;height:22px;margin:0"></span>` : raw(icon('play', 18))}<span>${s.play}</span></button>
          <div class="like-slot"></div>
          ${errorText ? html`<div class="error-text">${errorText}</div>` : ''}
          ${app.community.canDelete(cur) ? html`<button class="btn danger" data-act="delete">${raw(icon(adminDelete ? 'shield' : 'trash', 17))}<span>${s.deleteOnline}</span>${adminDelete ? html`<span class="badge">${s.adminBadge}</span>` : ''}</button>` : ''}
        </div>`);
      mountLikeButton(el.querySelector('.like-slot'), app, cur);
    };
    render();
    el.addEventListener('click', async (e) => {
      const t = e.target.closest('[data-act]');
      if (!t) return;
      const act = t.dataset.act;
      if (act === 'close') {
        sound.play('click', 0.6);
        off();
        close();
      } else if (act === 'play' && !busy) {
        sound.play('click', 0.6);
        busy = true;
        errorText = '';
        render();
        try {
          const cur = app.community.find(level.id) || level;
          const editorLevel = await app.community.download(cur);
          const compiled = compile(editorLevel, { worldCount: app.library.worlds.length, title: cur.title });
          app.community.registerView(cur.id);
          off();
          close();
          app.go('custom', { custom: { level: compiled, origin: { type: 'community', level: cur } } });
        } catch (err) {
          busy = false;
          errorText = s.onlineError(err);
          render();
        }
      } else if (act === 'delete') {
        const cur = app.community.find(level.id) || level;
        dialog(s.deleteOnlineTitle(cur.title), s.deleteOnlineMessage, [
          { label: s.cancel, role: 'cancel' },
          {
            label: s.delete, role: 'destructive', action: async () => {
              try {
                await app.community.remove(cur);
                haptics.success();
                off();
                close();
              } catch (err) {
                errorText = s.onlineError(err);
                render();
              }
            },
          },
        ]);
      }
    });
  });
}

/** Heart button with the like count; asks the player to sign in first if needed. */
export function mountLikeButton(container, app, level) {
  if (!container) return;
  const s = app.s;
  let errorText = '';
  const render = () => {
    if (!container.isConnected) return false;
    const liked = app.community.liked.has(level.id);
    const cur = app.community.find(level.id);
    const likes = cur ? cur.likes : level.likes;
    setHTML(container, html`<button class="like-btn ${liked ? 'on' : ''}" data-like ${app.community.liking.has(level.id) ? 'disabled' : ''}>
        ${raw(icon(liked ? 'heart' : 'heartOutline', 20))}<span>${s.like}</span><span style="opacity:.7;font-variant-numeric:tabular-nums">${likes}</span></button>
      ${errorText ? html`<div class="error-text" style="margin-top:6px">${errorText}</div>`
        : app.account.isSignedIn ? '' : html`<div class="muted small-text" style="margin-top:6px">${s.signInToLike}</div>`}`);
    return true;
  };
  render();
  const off1 = app.community.on(() => { if (!render()) { off1(); off2(); } });
  const off2 = app.account.on(() => { if (!render()) { off1(); off2(); } });
  container.addEventListener('click', async (e) => {
    if (!e.target.closest('[data-like]')) return;
    haptics.light();
    if (!app.account.isSignedIn) {
      openAccount(app);
      return;
    }
    try {
      errorText = '';
      const reply = await app.community.toggleLike(level.id);
      if (reply && reply.liked) haptics.success();
    } catch (err) {
      errorText = s.onlineError(err);
    }
    render();
  });
}

/** Sign up, sign in, profile, and (for server owners) a custom server. */
export function openAccount(app) {
  const s = app.s;
  const a = app.account;
  const state = { creating: true, username: '', email: '', password: '', busy: false, error: '', showServer: !a.isConfigured, serverURL: a.usingCustomServer ? a.config.url : '', serverKey: a.usingCustomServer ? a.config.anonKey : '', serverNote: '' };
  if (a.isSignedIn) a.refreshProfile();
  sheet((el, close) => {
    const off = a.on(() => { if (el.isConnected) render(); else off(); });
    const field = (name, label, type, foot, autocomplete) => html`<div class="field"><label>${label}</label>
      <input name="${name}" type="${type}" value="${state[name]}" autocomplete="${autocomplete}" autocapitalize="off" autocorrect="off" spellcheck="false">
      ${foot ? html`<div class="foot">${foot}</div>` : ''}</div>`;
    const canSubmit = () => {
      const mailOK = state.email.includes('@') && state.email.includes('.');
      if (state.creating) return mailOK && state.password.length >= 6 && USERNAME_RE.test(state.username.trim());
      return mailOK && state.password.length > 0;
    };
    const render = () => {
      let body;
      if (!a.isConfigured) {
        body = html`<div class="note" style="background:rgba(255,225,77,.1)">${raw(icon('server', 18, 'gold'))}<span>${s.notConfiguredBody}</span></div>`;
      } else if (a.isSignedIn) {
        body = html`<div class="card stack">
          <div style="display:flex;gap:14px;align-items:center"><span class="cyan">${raw(icon('person', 44))}</span>
            <div style="min-width:0"><div style="font-size:22px;font-weight:900">${a.profile ? a.profile.username : '…'} ${a.isAdmin ? html`<span class="badge">${s.adminBadge}</span>` : ''}</div>
            ${a.session.email ? html`<div class="muted small-text">${a.session.email}</div>` : ''}</div></div>
          ${a.isAdmin ? html`<div class="note" style="background:rgba(255,225,77,.1)">${raw(icon('shield', 18, 'gold'))}<span>${s.adminNote}</span></div>` : ''}
          <button class="btn" data-act="signout">${raw(icon('signout', 17))}<span>${s.signOut}</span></button></div>`;
      } else {
        body = html`<div class="stack">
          <p class="muted" style="margin:0;font-size:15px">${s.accountPitch}</p>
          ${state.creating ? field('username', s.usernameLabel, 'text', s.usernameRules, 'username') : ''}
          ${field('email', s.emailLabel, 'email', '', 'email')}
          ${field('password', s.passwordLabel, 'password', state.creating ? s.passwordRules : '', state.creating ? 'new-password' : 'current-password')}
          ${state.error ? html`<div class="error-text">${state.error}</div>` : ''}
          <button class="btn primary submit ${state.busy || !canSubmit() ? 'disabled' : ''}" data-act="submit">${raw(icon(state.creating ? 'personPlus' : 'person', 17))}<span>${state.creating ? s.signUp : s.signIn}</span></button>
          <button class="link-btn" data-act="switch">${state.creating ? s.haveAccount : s.needAccount}</button></div>`;
      }
      const serverStatus = a.usingCustomServer ? s.serverCustom : a.hasBundledServer ? s.serverBuiltIn : s.serverNone;
      setHTML(el, html`
        <div class="sheet-head"><h2>${s.accountTitle}</h2><button class="link-btn" data-act="close">${s.done}</button></div>
        ${body}
        <div class="card" style="margin-top:20px">
          <button data-act="server" style="display:flex;width:100%;align-items:center;gap:10px;border:0;background:none;color:#fff;font-size:15px;font-weight:800;padding:0">
            ${raw(icon('server', 16))}<span style="flex:1;text-align:left">${s.serverTitle}</span><span class="muted small-text">${serverStatus}</span></button>
          ${state.showServer ? html`<div class="stack" style="margin-top:12px">
            <div class="muted small-text">${s.serverHelp}</div>
            ${field('serverURL', s.serverURL, 'url', '', 'off')}
            ${field('serverKey', s.serverKey, 'text', '', 'off')}
            ${state.serverNote ? html`<div class="gold small-text">${state.serverNote}</div>` : ''}
            <div class="row"><button class="btn small" data-act="saveServer">${raw(icon('check', 16))}<span>${s.serverSave}</span></button>
            ${a.usingCustomServer && a.hasBundledServer ? html`<button class="btn small" data-act="builtin">${raw(icon('undo', 16))}<span>${s.useBuiltIn}</span></button>` : ''}</div>
          </div>` : ''}
        </div>`);
    };
    render();
    el.addEventListener('input', (e) => {
      const t = e.target;
      if (t.name in state) {
        state[t.name] = t.value;
        const btn = el.querySelector('.submit');
        if (btn) btn.classList.toggle('disabled', state.busy || !canSubmit());
      }
    });
    el.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && e.target.tagName === 'INPUT' && !a.isSignedIn && a.isConfigured && canSubmit()) submit();
    });
    const submit = async () => {
      if (state.busy || !canSubmit()) return;
      state.busy = true;
      state.error = '';
      render();
      try {
        if (state.creating) await a.signUp(state.username, state.email, state.password);
        else await a.signIn(state.email, state.password);
        state.password = '';
        app.community.reset();
        haptics.success();
      } catch (err) {
        if (err.code === 'confirmEmail') state.creating = false;
        state.error = s.onlineError(err);
      }
      state.busy = false;
      render();
    };
    el.addEventListener('click', async (e) => {
      const t = e.target.closest('[data-act]');
      if (!t) return;
      sound.play('click', 0.6);
      switch (t.dataset.act) {
        case 'close': off(); close(); break;
        case 'switch': state.creating = !state.creating; state.error = ''; render(); break;
        case 'submit': submit(); break;
        case 'signout': await a.signOut(); app.community.reset(); render(); break;
        case 'server': state.showServer = !state.showServer; render(); break;
        case 'saveServer':
          if (a.setServer(state.serverURL, state.serverKey)) {
            state.serverNote = '';
            app.community.reset();
            haptics.success();
          } else {
            state.serverNote = s.serverInvalid;
            haptics.failure();
          }
          render();
          break;
        case 'builtin':
          a.useBuiltInServer();
          state.serverURL = '';
          state.serverKey = '';
          app.community.reset();
          render();
          break;
        default: break;
      }
    });
  });
}
