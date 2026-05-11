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

// Exports for later tasks to use:
module.exports = { connect, send, recv };
