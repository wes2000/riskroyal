const { test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { createSessionStore } = require('../src/session-store');

let now = 1000;
const clock = () => now;
let store;

beforeEach(() => {
  now = 1000;
  store = createSessionStore({ clock, ttlMs: 600000 }); // 10 min
});

test('put + getByCode returns the same session', () => {
  const hostWs = { mockHost: true };
  const session = store.create('ABCDEF', hostWs);
  assert.equal(store.getByCode('ABCDEF'), session);
  assert.equal(session.code, 'ABCDEF');
  assert.equal(session.hostWs, hostWs);
});

test('create returns null when code already exists', () => {
  store.create('ABCDEF', { id: 1 });
  assert.equal(store.create('ABCDEF', { id: 2 }), null);
});

test('pruneExpired removes inactive sessions past ttl', () => {
  store.create('AAAAAA', {});
  store.create('BBBBBB', {});
  now += 599999; // just under 10 min
  assert.deepEqual(store.pruneExpired(), []);
  assert.equal(store.size(), 2);
  now += 2; // now > ttl
  assert.deepEqual(store.pruneExpired().sort(), ['AAAAAA', 'BBBBBB']);
  assert.equal(store.size(), 0);
});

test('touch resets lastActivityAt so session survives prune', () => {
  store.create('AAAAAA', {});
  now += 500000;
  store.touch(store.getByCode('AAAAAA'));
  now += 200000; // 700000 total, but touched at 501000 → only 199000 stale
  assert.deepEqual(store.pruneExpired(), []);
});

test('remove deletes a session', () => {
  store.create('AAAAAA', {});
  assert.equal(store.remove('AAAAAA'), true);
  assert.equal(store.getByCode('AAAAAA'), null);
});
