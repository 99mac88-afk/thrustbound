// Runs the web app's own community client against real Supabase Auth + PostgREST
// (started by backend/test/run_api_tests.sh). Usage:
//   AUTH_URL=http://127.0.0.1:59999 REST_URL=http://127.0.0.1:53000 ANON_KEY=... node web/test/online-flow.mjs
import assert from 'node:assert/strict';
import http from 'node:http';
import { AccountStore, CommunityStore, ProgressSync } from '../js/online.js';
import { Progress } from '../js/store.js';
import { sampleLevel } from '../js/editor-level.js';
import { compile } from '../js/compiler.js';

const { AUTH_URL, REST_URL, ANON_KEY } = process.env;
const run = Math.random().toString(36).slice(2, 8);

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
const step = (name) => console.log('ok  ', name);

try {
  const alice = new AccountStore({ url: base, anonKey: ANON_KEY });
  const aliceCommunity = new CommunityStore(alice);
  assert.ok(alice.isConfigured);
  await alice.signUp(`webA${run}`, `weba${run}@example.com`, 'hunter22!');
  assert.ok(alice.isSignedIn);
  assert.equal(alice.profile.username, `webA${run}`);
  step('sign up and profile');

  await assert.rejects(new AccountStore({ url: base, anonKey: ANON_KEY }).signUp(`WEBA${run}`, `x${run}@example.com`, 'hunter22!'), (e) => e.code === 'usernameTaken');
  await assert.rejects(new AccountStore({ url: base, anonKey: ANON_KEY }).signIn(`weba${run}@example.com`, 'nope'), (e) => e.serverCode === 'invalid_credentials');
  step('friendly errors');

  const level = sampleLevel(3, `Web Cave ${run}`);
  level.clearTime = 14.2;
  const id = await aliceCommunity.publish(level);
  assert.match(id, /^[0-9a-f-]{36}$/);
  step('publish');

  const bob = new AccountStore({ url: base, anonKey: ANON_KEY });
  const bobCommunity = new CommunityStore(bob);
  await bob.signUp(`webB${run}`, `webb${run}@example.com`, 'hunter22!');
  await bobCommunity.reload('newest');
  const listed = bobCommunity.levels('newest').find((l) => l.id === id);
  assert.ok(listed, 'published level is listed');
  assert.equal(listed.author, `webA${run}`);
  assert.ok(listed.createdAt instanceof Date);
  for (const tab of ['top', 'viewed']) {
    await bobCommunity.reload(tab);
    assert.ok(!bobCommunity.errors[tab], `${tab}: ${bobCommunity.errors[tab]}`);
  }
  step('lists with authors');

  const downloaded = await bobCommunity.download(listed);
  assert.equal(downloaded.name, `Web Cave ${run}`);
  assert.equal(compile(downloaded).stars.length, 3);
  step('download a published level');

  bobCommunity.registerView(id);
  await new Promise((r) => setTimeout(r, 500));
  assert.equal(bobCommunity.find(id).views, 1);
  bobCommunity.registerView(id);
  await new Promise((r) => setTimeout(r, 300));
  assert.equal(bobCommunity.find(id).views, 1, 'one view per page load');
  step('view counter');

  let reply = await bobCommunity.toggleLike(id);
  assert.deepEqual(reply, { liked: true, likes: 1 });
  assert.ok(bobCommunity.liked.has(id));
  await bobCommunity.reload('newest');
  assert.ok(bobCommunity.liked.has(id), 'likes are remembered after reloading');
  reply = await bobCommunity.toggleLike(id);
  assert.equal(reply.likes, 0);
  step('like and unlike');

  await assert.rejects(bobCommunity.remove(listed), (e) => e.code === 'notAllowed');
  step('players cannot delete other levels');

  // Progress follows the account: two devices signed in to Bob's account.
  const levels = [{ id: 1 }, { id: 2 }, { id: 3 }];
  const phone = new Progress(levels);
  phone.recordWin(0, 2, 20);
  phone.recordWin(1, 3, 9);
  const phoneSync = new ProgressSync(bob, phone);
  await phoneSync.sync();
  assert.equal(phoneSync.state, 'synced');
  assert.deepEqual(phoneSync.recordClear(id, 31.5), { newBestStars: false, newBestTime: false, firstClear: true });
  assert.deepEqual(phoneSync.recordClear(id, 40), { newBestStars: false, newBestTime: false, firstClear: false });
  assert.equal(phoneSync.recordClear(id.toUpperCase(), 30).newBestTime, true);
  await phoneSync.sync();

  const bob2 = new AccountStore({ url: base, anonKey: ANON_KEY });
  await bob2.signIn(`webb${run}@example.com`, 'hunter22!');
  const laptop = new Progress(levels);
  laptop.recordWin(0, 3, 25);
  const laptopSync = new ProgressSync(bob2, laptop);
  await laptopSync.sync();
  assert.deepEqual(laptop.records, { 1: { stars: 3, bestTime: 20 }, 2: { stars: 3, bestTime: 9 } }, 'best of both devices');
  assert.equal(laptopSync.clearTime(id), 30, 'finished community level shows on the other device');
  assert.equal(laptopSync.campaignVersion, 1);
  await phoneSync.sync();
  assert.deepEqual(phone.records[1], { stars: 3, bestTime: 20 }, 'and back on the first device');
  step('progress follows the account');

  // Reset on the laptop: the phone (which synced before) takes the empty campaign instead of bringing it back.
  laptop.reset();
  laptopSync.resetCampaign();
  await laptopSync.sync();
  phone.recordWin(2, 1, 50);
  await phoneSync.sync();
  assert.deepEqual(phone.records, {}, 'old progress replaced after a reset elsewhere');
  assert.equal(phoneSync.clearTime(id), 30, 'reset keeps finished community levels');
  phone.recordWin(2, 1, 50);
  await phoneSync.sync();
  await laptopSync.sync();
  assert.deepEqual(laptop.records, { 3: { stars: 1, bestTime: 50 } }, 'new progress after the reset syncs again');
  step('reset progress on every device');

  // Signed out: nothing is sent, finished levels stay on the device.
  const guest = new ProgressSync(new AccountStore({ url: base, anonKey: ANON_KEY }), new Progress(levels));
  await guest.sync();
  assert.equal(guest.state, 'idle');
  assert.deepEqual(guest.recordClear(id, 12).firstClear, true);
  step('signed out play stays on the device');

  await alice.accessToken(true);
  assert.ok(alice.isSignedIn);
  step('token refresh');

  await aliceCommunity.reload('mine');
  assert.deepEqual(aliceCommunity.levels('mine').map((l) => l.id), [id]);
  await aliceCommunity.remove(aliceCommunity.levels('mine')[0]);
  assert.equal(aliceCommunity.levels('mine').length, 0);
  step('author deletes own level');

  await alice.signOut();
  assert.ok(!alice.isSignedIn);
  step('sign out');
  console.log('\nWEB CLIENT: ALL PASSED');
} finally {
  proxy.close();
}
