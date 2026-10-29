// Community server client (port of Backend.swift, AccountStore.swift and CommunityStore.swift).
import { decodeLevel, encodeLevel } from './editor-level.js';
import { problems } from './compiler.js';
import { storage } from './store.js';

export class OnlineError extends Error {
  constructor(code, message = '', serverCode = null) {
    super(message || code);
    this.code = code;          // our own category (offline, signInRequired, ...) or 'server'
    this.serverCode = serverCode;
  }
}

export function cleanConfig(c) {
  if (!c || typeof c.url !== 'string' || typeof c.anonKey !== 'string') return null;
  let url = c.url.trim();
  while (url.endsWith('/')) url = url.slice(0, -1);
  const key = c.anonKey.trim();
  try {
    const u = new URL(url);
    const local = u.hostname === 'localhost' || u.hostname === '127.0.0.1';
    if ((u.protocol !== 'https:' && !(local && u.protocol === 'http:')) || !u.host || !key) return null;
  } catch {
    return null;
  }
  return { url, anonKey: key };
}

/** Auth errors look like {error_code, msg}; table errors like {code, message}. */
export function errorFrom(body, status) {
  const o = body && typeof body === 'object' ? body : {};
  const code = (typeof o.error_code === 'string' && o.error_code) || (typeof o.code === 'string' && o.code) || (typeof o.error === 'string' && o.error) || null;
  const message = o.msg || o.message || o.error_description || o.error || `HTTP ${status}`;
  if (/username is already taken/i.test(message)) return new OnlineError('usernameTaken');
  if (String(message).startsWith('Username must be')) return new OnlineError('badUsername');
  if (code === '42501' || String(message).includes('permission denied')) return new OnlineError(status === 401 ? 'signInRequired' : 'notAllowed');
  if (status === 401 || code === 'PGRST301' || /JWT expired/i.test(message)) return new OnlineError('signInRequired');
  return new OnlineError('server', message, code);
}

export class SupabaseClient {
  constructor(config) {
    this.base = config.url;
    this.key = config.anonKey;
  }

  async send(method, path, { json, token, prefer } = {}) {
    const headers = { apikey: this.key, Accept: 'application/json' };
    // Signed-out requests send only the public key (works with anon and publishable keys).
    if (token) headers.Authorization = `Bearer ${token}`;
    if (prefer) headers.Prefer = prefer;
    let body;
    if (json !== undefined) {
      headers['Content-Type'] = 'application/json';
      body = typeof json === 'string' ? json : JSON.stringify(json);
    }
    let res;
    try {
      res = await fetch(this.base + path, { method, headers, body, cache: 'no-store' });
    } catch {
      throw new OnlineError('offline');
    }
    const text = await res.text().catch(() => '');
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = text; }
    if (!res.ok) throw errorFrom(data, res.status);
    return data;
  }

  session(o) {
    if (!o || !o.access_token || !o.refresh_token || !o.user || !o.user.id) return null;
    return {
      accessToken: o.access_token, refreshToken: o.refresh_token,
      expiresAt: Date.now() + (Number(o.expires_in) || 3600) * 1000,
      userID: o.user.id, email: o.user.email || null, server: this.base,
    };
  }

  async signUp(email, password, username) {
    return this.session(await this.send('POST', '/auth/v1/signup', { json: { email, password, data: { username } } }));
  }

  async signIn(email, password) {
    const s = this.session(await this.send('POST', '/auth/v1/token?grant_type=password', { json: { email, password } }));
    if (!s) throw new OnlineError('server', 'Unexpected reply');
    return s;
  }

  /** Finishes a sign-up with the code from the confirmation email. */
  async verifyEmail(email, code) {
    const s = this.session(await this.send('POST', '/auth/v1/verify', { json: { type: 'email', email, token: code } }));
    if (!s) throw new OnlineError('server', 'Unexpected reply');
    return s;
  }

  /** Emails a new sign-up code. The server answers the same for unknown or already confirmed addresses. */
  async resendCode(email) {
    await this.send('POST', '/auth/v1/resend', { json: { type: 'signup', email } });
  }

  async refresh(refreshToken) {
    const s = this.session(await this.send('POST', '/auth/v1/token?grant_type=refresh_token', { json: { refresh_token: refreshToken } }));
    if (!s) throw new OnlineError('signInRequired');
    return s;
  }

  async signOut(token) {
    try { await this.send('POST', '/auth/v1/logout', { json: {}, token }); } catch { /* already gone */ }
  }

  get(pathAndQuery, token) { return this.send('GET', `/rest/v1/${pathAndQuery}`, { token }); }
  insert(table, body, token) { return this.send('POST', `/rest/v1/${table}`, { json: body, token, prefer: 'return=representation' }); }
  remove(table, filter, token) { return this.send('DELETE', `/rest/v1/${table}?${filter}`, { token, prefer: 'return=representation' }); }
  rpc(name, args, token) { return this.send('POST', `/rest/v1/rpc/${name}`, { json: args, token }); }

  async usernameAvailable(name) {
    return (await this.rpc('username_available', { p_name: name })) === true;
  }
}

class Emitter {
  constructor() { this.listeners = new Set(); }
  on(fn) { this.listeners.add(fn); return () => this.listeners.delete(fn); }
  emit() { for (const fn of [...this.listeners]) { try { fn(); } catch (e) { console.error(e); } } }
}

const SERVER_KEY = 'tb.server.v1';
const SESSION_KEY = 'tb.session.v1';
const PROFILE_KEY = 'tb.profile.v1';
const PENDING_KEY = 'tb.pending.v1';
export const USERNAME_RE = /^[A-Za-z0-9_]{3,20}$/;
/** How long to wait before offering to send another code. */
export const RESEND_DELAY = 60000;

/** Keeps only the digits of a typed or pasted code (Supabase codes have 6 to 10 digits). */
export function cleanCode(text) {
  return String(text || '').replace(/[^0-9]/g, '').slice(0, 10);
}

export function isCompleteCode(code) {
  return /^[0-9]{6,10}$/.test(code);
}

export class AccountStore extends Emitter {
  constructor(bundled) {
    super();
    this.bundled = cleanConfig(bundled);
    const custom = cleanConfig(storage.get(SERVER_KEY));
    this.config = custom || this.bundled;
    this.usingCustomServer = !!custom;
    this.session = null;
    this.profile = null;
    this.refreshing = null;
    /** A new account waiting for the code from its confirmation email: {email, server, codeSentAt}. */
    this.pending = null;
    const saved = storage.get(SESSION_KEY);
    if (saved && this.config && saved.server === this.config.url && saved.accessToken) {
      this.session = saved;
      const p = storage.get(PROFILE_KEY);
      if (p && p.user === saved.userID) this.profile = { username: p.username, isAdmin: !!p.admin };
      this.refreshProfile();
    } else {
      const p = storage.get(PENDING_KEY);
      if (p && this.config && p.server === this.config.url && typeof p.email === 'string' &&
          typeof p.codeSentAt === 'number' && Date.now() - p.codeSentAt < 2 * 86400000) this.pending = p;
    }
  }

  get client() { return this.config ? new SupabaseClient(this.config) : null; }
  get isConfigured() { return !!this.config; }
  get isSignedIn() { return !!this.session; }
  get isAdmin() { return !!(this.profile && this.profile.isAdmin); }
  get userID() { return this.session ? this.session.userID : null; }
  get hasBundledServer() { return !!this.bundled; }

  setServer(url, key) {
    const c = cleanConfig({ url, anonKey: key });
    if (!c) return false;
    storage.set(SERVER_KEY, c);
    if (!this.config || c.url !== this.config.url || c.anonKey !== this.config.anonKey) this.clearSession();
    this.config = c;
    this.usingCustomServer = true;
    this.emit();
    return true;
  }

  useBuiltInServer() {
    storage.remove(SERVER_KEY);
    this.clearSession();
    this.config = this.bundled;
    this.usingCustomServer = false;
    this.emit();
  }

  /** Resolves to false when the server emailed a code that has to be entered before the account works. */
  async signUp(username, email, password) {
    const client = this.client;
    if (!client) throw new OnlineError('notConfigured');
    const name = username.trim();
    if (!USERNAME_RE.test(name)) throw new OnlineError('badUsername');
    if (!(await client.usernameAvailable(name))) throw new OnlineError('usernameTaken');
    const mail = email.trim();
    const s = await client.signUp(mail, password, name);
    if (!s) {
      this.setPending({ email: mail, server: client.base, codeSentAt: Date.now() });
      return false;
    }
    this.store(s);
    await this.refreshProfile();
    return true;
  }

  /** Throws 'confirmEmail' (after asking for a fresh code) when the account's email isn't confirmed yet. */
  async signIn(email, password) {
    const client = this.client;
    if (!client) throw new OnlineError('notConfigured');
    const mail = email.trim();
    let s;
    try {
      s = await client.signIn(mail, password);
    } catch (e) {
      if (e.serverCode !== 'email_not_confirmed') throw e;
      // The old code may have run out, so send a new one right away.
      let sent = true;
      try { await client.resendCode(mail); } catch { sent = false; }
      this.setPending({ email: mail, server: client.base, codeSentAt: sent ? Date.now() : 0 });
      throw new OnlineError('confirmEmail');
    }
    this.store(s);
    await this.refreshProfile();
  }

  /** Finishes a sign-up with the code from the email and signs in. */
  async confirmEmail(code) {
    const client = this.client;
    if (!client) throw new OnlineError('notConfigured');
    if (!this.pending) throw new OnlineError('signInRequired');
    this.store(await client.verifyEmail(this.pending.email, cleanCode(code)));
    await this.refreshProfile();
  }

  async resendCode() {
    const client = this.client;
    if (!client) throw new OnlineError('notConfigured');
    const p = this.pending;
    if (!p) throw new OnlineError('signInRequired');
    await client.resendCode(p.email);
    this.setPending({ ...p, codeSentAt: Date.now() });
  }

  /** Seconds until another code may be requested (0 when it can be sent now). */
  resendWait(now = Date.now()) {
    if (!this.pending) return 0;
    return Math.max(0, Math.ceil((RESEND_DELAY - (now - this.pending.codeSentAt)) / 1000));
  }

  /** Forgets the account that was waiting for its code (to use another email or sign in instead). */
  cancelPending() {
    this.setPending(null);
  }

  setPending(p) {
    this.pending = p;
    if (p) storage.set(PENDING_KEY, p);
    else storage.remove(PENDING_KEY);
    this.emit();
  }

  async signOut() {
    const token = this.session && this.session.accessToken;
    const client = this.client;
    this.clearSession();
    this.emit();
    if (token && client) await client.signOut(token);
  }

  store(s) {
    this.session = s;
    storage.set(SESSION_KEY, s);
    if (this.pending) {
      this.pending = null;
      storage.remove(PENDING_KEY);
    }
    this.emit();
  }

  clearSession() {
    this.session = null;
    this.profile = null;
    this.refreshing = null;
    this.pending = null;
    storage.remove(SESSION_KEY);
    storage.remove(PROFILE_KEY);
    storage.remove(PENDING_KEY);
  }

  /** A fresh access token, refreshed first when it is about to run out. */
  async accessToken(force = false) {
    const current = this.session;
    if (!current) throw new OnlineError('signInRequired');
    if (!force && current.expiresAt - Date.now() > 60000) return current.accessToken;
    const client = this.client;
    if (!client) throw new OnlineError('notConfigured');
    if (!this.refreshing) this.refreshing = client.refresh(current.refreshToken);
    try {
      const fresh = await this.refreshing;
      this.refreshing = null;
      if (!this.session || this.session.userID !== fresh.userID) throw new OnlineError('signInRequired');
      this.store(fresh);
      return fresh.accessToken;
    } catch (e) {
      this.refreshing = null;
      if (e.code === 'offline') throw e;
      // Only a rejected refresh token means the sign-in is gone; other failures may be temporary.
      const rejected = e.code === 'signInRequired' || /refresh_token|session/.test(e.serverCode || '');
      if (rejected && this.session && this.session.refreshToken === current.refreshToken) {
        this.clearSession();
        this.emit();
      }
      throw rejected ? new OnlineError('signInRequired') : e;
    }
  }

  /** Runs a request with the player's token, refreshing and retrying once if it was rejected. */
  async authorized(work) {
    const client = this.client;
    if (!client) throw new OnlineError('notConfigured');
    const token = await this.accessToken();
    try {
      return await work(client, token);
    } catch (e) {
      if (e.code !== 'signInRequired') throw e;
      return work(client, await this.accessToken(true));
    }
  }

  async refreshProfile() {
    const id = this.userID;
    if (!id) return;
    try {
      const rows = await this.authorized((c, t) => c.get(`profiles?id=eq.${id}&select=username,is_admin`, t));
      const row = Array.isArray(rows) ? rows[0] : null;
      if (row && this.userID === id) {
        this.profile = { username: row.username, isAdmin: !!row.is_admin };
        storage.set(PROFILE_KEY, { user: id, username: row.username, admin: !!row.is_admin });
        this.emit();
      }
    } catch {
      // Keep what we knew; the next visit tries again.
    }
  }
}

export const TABS = ['newest', 'top', 'viewed', 'mine'];
const ORDER = { newest: 'created_at.desc', mine: 'created_at.desc', top: 'likes.desc,created_at.desc', viewed: 'views.desc,created_at.desc' };
const COLUMNS = 'select=id,title,views,likes,created_at,author_id,author:profiles!levels_author_id_fkey(username)';
export const PAGE_SIZE = 30;

export function parseDate(text) {
  if (typeof text !== 'string') return null;
  const d = new Date(text.replace(/(\.\d{3})\d+/, '$1'));
  return isNaN(d.getTime()) ? null : d;
}

export function decodeList(rows) {
  if (!Array.isArray(rows)) throw new OnlineError('server', 'Unexpected reply');
  return rows.map((r) => ({
    id: r.id, title: r.title, views: r.views ?? 0, likes: r.likes ?? 0,
    createdAt: parseDate(r.created_at), authorID: r.author_id,
    author: (r.author && r.author.username) || '?',
  }));
}

export class CommunityStore extends Emitter {
  constructor(account) {
    super();
    this.account = account;
    this.reset(false);
    this.countedViews = new Set();
  }

  reset(emit = true) {
    this.lists = {};
    this.loading = new Set();
    this.exhausted = new Set();
    this.errors = {};
    this.liked = new Set();
    this.liking = new Set();
    this.listedFor = {};
    this.generation = {};
    if (emit) this.emit();
  }

  levels(tab) { return this.lists[tab] || []; }

  find(id) {
    for (const list of Object.values(this.lists)) {
      const l = list.find((x) => x.id === id);
      if (l) return l;
    }
    return null;
  }

  update(id, change) {
    for (const list of Object.values(this.lists)) {
      const l = list.find((x) => x.id === id);
      if (l) change(l);
    }
    this.emit();
  }

  get viewerKey() { return `${this.account.config ? this.account.config.url : ''}|${this.account.userID || ''}`; }

  async loadIfNeeded(tab) {
    if (!this.lists[tab] || this.listedFor[tab] !== this.viewerKey) await this.reload(tab);
  }

  reload(tab) { return this.load(tab, 0); }

  loadMore(tab) {
    if (this.exhausted.has(tab) || this.loading.has(tab)) return Promise.resolve();
    return this.load(tab, this.levels(tab).length);
  }

  async load(tab, offset) {
    const client = this.account.client;
    if (!client) {
      this.errors[tab] = new OnlineError('notConfigured');
      this.emit();
      return;
    }
    const ticket = (this.generation[tab] || 0) + 1;
    this.generation[tab] = ticket;
    this.loading.add(tab);
    this.emit();
    const viewer = this.viewerKey;
    let query = `levels?${COLUMNS}&order=${ORDER[tab]}&limit=${PAGE_SIZE}&offset=${offset}`;
    try {
      let rows;
      if (tab === 'mine') {
        const me = this.account.userID;
        if (!me) throw new OnlineError('signInRequired');
        query += `&author_id=eq.${me}`;
        rows = await this.account.authorized((c, t) => c.get(query, t));
      } else if (this.account.isSignedIn) {
        rows = await this.account.authorized((c, t) => c.get(query, t));
      } else {
        rows = await client.get(query, null);
      }
      const page = decodeList(rows);
      if (viewer !== this.viewerKey || this.generation[tab] !== ticket) return;
      const list = offset === 0 ? [] : this.levels(tab).slice();
      const known = new Set(list.map((l) => l.id));
      for (const l of page) if (!known.has(l.id)) list.push(l);
      this.lists[tab] = list;
      this.listedFor[tab] = viewer;
      delete this.errors[tab];
      if (page.length < PAGE_SIZE) this.exhausted.add(tab); else this.exhausted.delete(tab);
      await this.refreshLikes(page.map((l) => l.id));
    } catch (e) {
      if (this.generation[tab] === ticket) this.errors[tab] = e instanceof OnlineError ? e : new OnlineError('server', String(e));
    } finally {
      if (this.generation[tab] === ticket) this.loading.delete(tab);
      this.emit();
    }
  }

  async refreshLikes(ids) {
    if (!this.account.isSignedIn || ids.length === 0) return;
    try {
      const rows = await this.account.authorized((c, t) => c.get(`level_likes?select=level_id&level_id=in.(${ids.join(',')})`, t));
      const mine = new Set((rows || []).map((r) => r.level_id));
      for (const id of ids) if (mine.has(id)) this.liked.add(id); else this.liked.delete(id);
    } catch { /* likes are a nicety */ }
  }

  /** Downloads a level and checks it can be played. */
  async download(level) {
    const client = this.account.client;
    if (!client) throw new OnlineError('notConfigured');
    const rows = await client.get(`levels?id=eq.${level.id}&select=data`, null);
    let decoded;
    try {
      decoded = decodeLevel(rows[0].data);
    } catch {
      throw new OnlineError('badLevel');
    }
    if (problems(decoded).length) throw new OnlineError('badLevel');
    return decoded;
  }

  /** Counts a view the first time a level is played after the page loads. */
  registerView(id) {
    const client = this.account.client;
    if (this.countedViews.has(id) || !client) return;
    this.countedViews.add(id);
    client.rpc('register_view', { p_level: id }, null)
      .then((views) => { if (typeof views === 'number') this.update(id, (l) => { l.views = views; }); })
      .catch(() => {});
  }

  async toggleLike(id) {
    if (this.liking.has(id)) return;
    this.liking.add(id);
    this.emit();
    try {
      const reply = await this.account.authorized((c, t) => c.rpc('toggle_like', { p_level: id }, t));
      if (reply.liked) this.liked.add(id); else this.liked.delete(id);
      this.update(id, (l) => { l.likes = reply.likes; });
      return reply;
    } finally {
      this.liking.delete(id);
      this.emit();
    }
  }

  canDelete(level) {
    return this.account.isAdmin || (!!this.account.userID && level.authorID === this.account.userID);
  }

  async remove(level) {
    const rows = await this.account.authorized((c, t) => c.remove('levels', `id=eq.${level.id}`, t));
    // Row level security returns nothing (instead of an error) when we may not delete it.
    if (!Array.isArray(rows) || rows.length === 0) throw new OnlineError('notAllowed');
    for (const tab of Object.keys(this.lists)) this.lists[tab] = this.lists[tab].filter((l) => l.id !== level.id);
    this.emit();
  }

  /** Uploads a level and returns its id on the server. */
  async publish(level) {
    const body = { title: level.name, data: encodeLevel(level, false) };
    const rows = await this.account.authorized((c, t) => c.insert('levels', body, t));
    const [row] = decodeList(rows);
    if (!row) throw new OnlineError('server', 'Unexpected reply');
    for (const tab of ['newest', 'mine']) {
      if (this.lists[tab]) this.lists[tab] = [row, ...this.lists[tab].filter((l) => l.id !== row.id)];
    }
    this.emit();
    return row.id;
  }
}
