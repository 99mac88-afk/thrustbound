// Sign-up with an emailed code: runs the web app's account client against a Supabase Auth
// server with "Confirm email" on, reading the codes from backend/test/mail_sink.py.
// Started by backend/test/run_api_tests.sh. Usage:
//   AUTH_URL=http://127.0.0.1:59998 REST_URL=http://127.0.0.1:53000 ANON_KEY=... MAIL_DIR=... node web/test/confirm-flow.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';

const { AUTH_URL, REST_URL, ANON_KEY, MAIL_DIR } = process.env;
const run = Math.random().toString(36).slice(2, 8);

// The account store keeps the waiting sign-up in localStorage, like in a browser.
const saved = new Map();
globalThis.localStorage = {
  getItem: (k) => (saved.has(k) ? saved.get(k) : null),
  setItem: (k, v) => saved.set(k, String(v)),
  removeItem: (k) => saved.delete(k),
};
const { AccountStore, cleanCode } = await import('../js/online.js');
const { L10n } = await import('../js/i18n.js');

// A tiny stand-in for Supabase's gateway: /auth/v1 -> Auth, /rest/v1 -> PostgREST.
const proxy = http.createServer((req, res) => {
  const target = req.url.startsWith('/auth/v1') ? AUTH_URL + req.url.slice(8) : REST_URL + req.url.slice(8);
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', async () => {
    const headers = { ...req.headers };
    delete headers.host;
    delete headers['content-length'];
    try {
      const r = await fetch(target, { method: req.method, headers, body: chunks.length ? Buffer.concat(chunks) : undefined });
      res.writeHead(r.status, { 'content-type': r.headers.get('content-type') || 'application/json' });
      res.end(Buffer.from(await r.arrayBuffer()));
    } catch (e) {
      res.writeHead(502);
      res.end(String(e));
    }
  });
});
await new Promise((ok) => proxy.listen(0, '127.0.0.1', ok));
const base = `http://127.0.0.1:${proxy.address().port}`;
const config = { url: base, anonKey: ANON_KEY };
const step = (name) => console.log('ok  ', name);
const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));
const en = new L10n('en');

/** Every email the sink got for this address, oldest first. */
function mails(email) {
  return fs.readdirSync(MAIL_DIR).filter((f) => f.endsWith('.json')).sort()
    .map((f) => JSON.parse(fs.readFileSync(path.join(MAIL_DIR, f), 'utf8')))
    .filter((m) => m.to.includes(email.toLowerCase()));
}

async function nextCode(email, seen) {
  for (let i = 0; i < 50; i++) {
    const list = mails(email);
    if (list.length > seen) {
      const m = /code: (\d{6,10})/.exec(list[list.length - 1].text);
      assert.ok(m, 'the email has a code');
      return m[1];
    }
    await sleep(100);
  }
  throw new Error(`no email arrived for ${email}`);
}

try {
  // Sign up: no session yet, a code is emailed and the store waits for it.
  const carolMail = `carol${run}@example.com`;
  const carol = new AccountStore(config);
  assert.equal(await carol.signUp(`carol${run}`, carolMail, 'hunter22!'), false);
  assert.ok(!carol.isSignedIn);
  assert.equal(carol.pending.email, carolMail);
  assert.ok(carol.resendWait() > 55, 'the resend button waits a minute');
  const first = await nextCode(carolMail, 0);
  step('sign up emails a code');

  // Closing and reopening the app keeps the code step.
  const reopened = new AccountStore(config);
  assert.equal(reopened.pending && reopened.pending.email, carolMail);
  step('waiting sign-up survives a reload');

  await assert.rejects(reopened.confirmEmail(first === '000000' ? '111111' : '000000'), (e) => e.serverCode === 'otp_expired');
  assert.match(en.onlineError({ code: 'server', serverCode: 'otp_expired' }), /code is wrong/);
  assert.ok(!reopened.isSignedIn);
  step('a wrong code is refused');

  // Asking again too soon is refused by the server too, with a readable wait.
  await assert.rejects(reopened.client.resendCode(carolMail), (e) => {
    assert.equal(e.serverCode, 'over_email_send_rate_limit');
    assert.match(en.onlineError(e), /^Wait \d+ s and try again\.$/);
    return true;
  });
  await sleep(3500);
  await reopened.resendCode();
  const second = await nextCode(carolMail, 1);
  assert.ok(reopened.resendWait() > 55);
  if (second !== first) {
    await assert.rejects(reopened.confirmEmail(first), (e) => e.serverCode === 'otp_expired');
  }
  step('a new code replaces the old one');

  await reopened.confirmEmail(` ${second.slice(0, 3)} ${second.slice(3)} `);
  assert.ok(reopened.isSignedIn);
  assert.equal(reopened.pending, null);
  assert.equal(localStorage.getItem('tb.pending.v1'), null);
  assert.equal(reopened.profile.username, `carol${run}`);
  step('the right code signs in');

  const again = new AccountStore({ ...config });
  again.clearSession();
  await again.signIn(carolMail, 'hunter22!');
  assert.ok(again.isSignedIn);
  step('a confirmed account signs in with its password');

  // Signing in before confirming: a fresh code is sent and the code step opens.
  saved.clear();
  const daveMail = `dave${run}@example.com`;
  const dave = new AccountStore(config);
  assert.equal(await dave.signUp(`dave${run}`, daveMail, 'hunter22!'), false);
  await nextCode(daveMail, 0);
  dave.cancelPending();
  assert.equal(dave.pending, null);
  await assert.rejects(dave.signIn(daveMail, 'wrong-password'), (e) => e.serverCode === 'invalid_credentials');
  assert.equal(dave.pending, null);
  await sleep(3500);
  await assert.rejects(dave.signIn(daveMail, 'hunter22!'), (e) => e.code === 'confirmEmail');
  assert.equal(dave.pending.email, daveMail);
  assert.ok(dave.resendWait() > 55, 'a fresh code was sent');
  const daveCode = await nextCode(daveMail, 1);
  await dave.confirmEmail(daveCode);
  assert.ok(dave.isSignedIn);
  assert.equal(dave.profile.username, `dave${run}`);
  step('signing in before confirming sends a code');

  assert.equal(cleanCode('12 34-56'), '123456');
  console.log('confirm flow passed');
} finally {
  proxy.close();
}
