const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const WebSocket = require('ws');
const { startTestServer } = require('./_helpers');

let env;

before(async () => { env = await startTestServer(); });
after(async () => { await env.close(); });

function connect() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://localhost:${env.port}`);
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

function send(ws, obj) {
  return new Promise((resolve) => {
    ws.send(JSON.stringify(obj), () => resolve());
  });
}

function recv(ws) {
  return new Promise((resolve) => {
    ws.once('message', (data) => resolve(JSON.parse(data.toString())));
  });
}

test('unknown message type returns error', async () => {
  const ws = await connect();
  await send(ws, { type: 'banana' });
  const reply = await recv(ws);
  assert.equal(reply.type, 'error');
  assert.equal(reply.reason, 'unknown_type');
  ws.close();
});

test('malformed JSON returns error', async () => {
  const ws = await connect();
  ws.send('not-json');
  const reply = await recv(ws);
  assert.equal(reply.type, 'error');
  assert.equal(reply.reason, 'bad_json');
  ws.close();
});

test('host message returns a code and registers the session', async () => {
  const ws = await connect();
  await send(ws, { type: 'host' });
  const reply = await recv(ws);
  assert.equal(reply.type, 'code');
  assert.equal(typeof reply.code, 'string');
  assert.equal(reply.code.length, 6);
  assert.equal(env.store.getByCode(reply.code).hostWs.readyState, 1);
  ws.close();
});

test('second host message from same socket returns error', async () => {
  const ws = await connect();
  await send(ws, { type: 'host' }); await recv(ws);
  await send(ws, { type: 'host' });
  const reply = await recv(ws);
  assert.equal(reply.type, 'error');
  assert.equal(reply.reason, 'already_host');
  ws.close();
});

async function hostAndGetCode() {
  const host = await connect();
  await send(host, { type: 'host' });
  const { code } = await recv(host);
  return { host, code };
}

test('join with unknown code returns error', async () => {
  const joiner = await connect();
  await send(joiner, { type: 'join', code: 'ZZZZZZ' });
  const reply = await recv(joiner);
  assert.equal(reply.type, 'error');
  assert.equal(reply.reason, 'unknown_code');
  joiner.close();
});

test('join with lowercase code works (case-insensitive)', async () => {
  const { host, code } = await hostAndGetCode();
  const joiner = await connect();
  await send(joiner, { type: 'join', code: code.toLowerCase() });
  const hostMsg = await recv(host);
  assert.equal(hostMsg.type, 'joiner');
  assert.equal(hostMsg.joinerId, 2);
  host.close(); joiner.close();
});

test('happy join: host receives joiner with monotonic id', async () => {
  const { host, code } = await hostAndGetCode();
  const j1 = await connect();
  await send(j1, { type: 'join', code });
  const m1 = await recv(host);
  assert.equal(m1.type, 'joiner');
  assert.equal(m1.joinerId, 2);

  const j2 = await connect();
  await send(j2, { type: 'join', code });
  const m2 = await recv(host);
  assert.equal(m2.joinerId, 3);
  host.close(); j1.close(); j2.close();
});

test('full session (8 already) rejects further joiners', async () => {
  const { host, code } = await hostAndGetCode();
  // Force-fill: bump nextJoinerId to 9
  env.store.getByCode(code).nextJoinerId = 9;
  const joiner = await connect();
  await send(joiner, { type: 'join', code });
  const reply = await recv(joiner);
  assert.equal(reply.type, 'error');
  assert.equal(reply.reason, 'full');
  host.close(); joiner.close();
});

test('started session rejects further joiners', async () => {
  const { host, code } = await hostAndGetCode();
  env.store.getByCode(code).started = true;
  const joiner = await connect();
  await send(joiner, { type: 'join', code });
  const reply = await recv(joiner);
  assert.equal(reply.type, 'error');
  assert.equal(reply.reason, 'in_progress');
  host.close(); joiner.close();
});

test('join forwards reconnect_token to host when present', async () => {
  const { host, code } = await hostAndGetCode();
  const joiner = await connect();
  await send(joiner, { type: 'join', code, reconnect_token: 'abc123' });
  const m = await recv(host);
  assert.equal(m.type, 'joiner');
  assert.equal(m.reconnect_token, 'abc123');
  host.close(); joiner.close();
});

async function fullHandshakeSetup() {
  const { host, code } = await hostAndGetCode();
  const joiner = await connect();
  await send(joiner, { type: 'join', code });
  await recv(host); // {type:"joiner", joinerId: 2}
  return { host, joiner, code };
}

test('signal from host to joiner is relayed opaquely', async () => {
  const { host, joiner } = await fullHandshakeSetup();
  await send(host, { type: 'signal', to: 2, payload: { sdp: 'OFFER-XYZ' } });
  const m = await recv(joiner);
  assert.equal(m.type, 'signal');
  assert.equal(m.from, 1);
  assert.deepEqual(m.payload, { sdp: 'OFFER-XYZ' });
  host.close(); joiner.close();
});

test('signal from joiner back to host is relayed', async () => {
  const { host, joiner } = await fullHandshakeSetup();
  await send(joiner, { type: 'signal', to: 1, payload: { ice: 'CAND-1' } });
  const m = await recv(host);
  assert.equal(m.type, 'signal');
  assert.equal(m.from, 2);
  assert.deepEqual(m.payload, { ice: 'CAND-1' });
  host.close(); joiner.close();
});

test('signal to unknown peer returns error to sender', async () => {
  const { host, joiner } = await fullHandshakeSetup();
  await send(joiner, { type: 'signal', to: 99, payload: {} });
  const reply = await recv(joiner);
  assert.equal(reply.type, 'error');
  assert.equal(reply.reason, 'unknown_peer');
  host.close(); joiner.close();
});

test('signal from non-session socket returns error', async () => {
  const stranger = await connect();
  await send(stranger, { type: 'signal', to: 1, payload: {} });
  const reply = await recv(stranger);
  assert.equal(reply.type, 'error');
  assert.equal(reply.reason, 'no_session');
  stranger.close();
});

test('connected from joiner releases pendingJoiners and closes joiner ws', async () => {
  const { host, joiner, code } = await fullHandshakeSetup();
  const session = env.store.getByCode(code);
  assert.equal(session.pendingJoiners.size, 1);

  await send(joiner, { type: 'connected' });
  // wait for the server to close our socket — guarantees handler ran
  await new Promise((r) => joiner.once('close', r));
  assert.equal(session.pendingJoiners.size, 0);
  assert.equal(joiner.readyState, joiner.CLOSED);
  host.close();
});

test('connected from host (with peerId) releases that joiner', async () => {
  const { host, joiner, code } = await fullHandshakeSetup();
  const session = env.store.getByCode(code);
  await send(host, { type: 'connected', peerId: 2 });
  // wait for the joiner socket to close — proves the server processed the message
  await new Promise((r) => joiner.once('close', r));
  assert.equal(session.pendingJoiners.size, 0);
  // host stays open (still hosting)
  assert.equal(host.readyState, host.OPEN);
  host.close(); joiner.close();
});

// Exports for later tasks to use:
module.exports = { connect, send, recv };
