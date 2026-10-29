// Tiny HTML helpers. Every interpolated value is escaped unless wrapped in raw().

export class Raw {
  constructor(s) { this.s = s; }
  toString() { return this.s; }
}
export const raw = (s) => new Raw(String(s));
export const esc = (v) => String(v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

function part(v) {
  if (v === null || v === undefined || v === false) return '';
  if (v instanceof Raw) return v.s;
  if (Array.isArray(v)) return v.map(part).join('');
  return esc(v);
}

export function html(strings, ...values) {
  let out = '';
  strings.forEach((s, i) => {
    out += s;
    if (i < values.length) out += part(values[i]);
  });
  return new Raw(out);
}

export function setHTML(el, content) {
  el.innerHTML = content instanceof Raw ? content.s : esc(content);
}

/** Calls handler(action, element, event) for clicks on [data-act] elements inside root. */
export function onAction(root, handler) {
  const listener = (e) => {
    const t = e.target.closest('[data-act]');
    if (t && root.contains(t) && !t.hasAttribute('disabled')) handler(t.dataset.act, t, e);
  };
  root.addEventListener('click', listener);
  return () => root.removeEventListener('click', listener);
}

let toastTimer = null;
export function toast(text, ms = 2400) {
  document.querySelectorAll('.toast').forEach((t) => t.remove());
  const el = document.createElement('div');
  el.className = 'toast';
  el.textContent = text;
  document.body.appendChild(el);
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.remove(), ms);
}

/** A small alert. buttons: [{ label, role: 'cancel' | 'destructive' | undefined, action }] */
export function dialog(title, message, buttons) {
  const wrap = document.createElement('div');
  wrap.className = 'dialog-wrap';
  setHTML(wrap, html`<div class="dialog" role="alertdialog"><div class="body"><h3>${title}</h3>${message ? html`<p>${message}</p>` : ''}</div>
    <div class="actions">${buttons.map((b, i) => html`<button data-i="${i}" class="${b.role || ''}">${b.label}</button>`)}</div></div>`);
  wrap.addEventListener('click', (e) => {
    const b = e.target.closest('button[data-i]');
    if (b) {
      wrap.remove();
      const def = buttons[Number(b.dataset.i)];
      if (def.action) def.action();
    } else if (e.target === wrap) {
      const cancel = buttons.find((b2) => b2.role === 'cancel');
      wrap.remove();
      if (cancel && cancel.action) cancel.action();
    }
  });
  document.body.appendChild(wrap);
  return wrap;
}

/** A sheet (modal panel). render(el) fills it; returns { el, close }. */
export function sheet(render, onClose) {
  const wrap = document.createElement('div');
  wrap.className = 'sheet-wrap';
  const el = document.createElement('div');
  el.className = 'sheet';
  wrap.appendChild(el);
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    wrap.remove();
    if (onClose) onClose();
  };
  wrap.addEventListener('click', (e) => { if (e.target === wrap) close(); });
  document.body.appendChild(wrap);
  render(el, close);
  return { el, close };
}

/** Shrinks text that does not fit its box (like minimumScaleFactor on iPhone). */
export function fitText(root, selector = '.btn > span, .tab, .header h1, .choice, .ed-tool span, .chip-btn span') {
  for (const el of root.querySelectorAll(selector)) {
    el.style.fontSize = '';
    let size = parseFloat(getComputedStyle(el).fontSize) || 16;
    let guard = 0;
    while (el.scrollWidth > el.clientWidth + 0.5 && size > 9 && guard++ < 20) {
      size -= 0.5;
      el.style.fontSize = `${size}px`;
    }
  }
}
