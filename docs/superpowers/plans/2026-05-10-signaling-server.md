# Signaling Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Node.js + `ws` signaling server that brokers WebRTC handshakes between Risk Royal hosts and joiners via 6-character Crockford-base32 codes. Server holds no game state; relays SDP/ICE payloads opaquely.

**Architecture:** A single Node 20+ process running a `ws` WebSocket server. Three source modules: pure code generation, in-memory session store with TTL, and the WebSocket dispatcher. Every behavior covered by `node:test` integration tests against a real `ws` server on a random port. No DB, no Redis, no auth. Deployable to Fly.io's free tier.

**Tech Stack:** Node.js 20 LTS, `ws` 8.x, `node:test` (built-in), `node:assert` (built-in). No transpiler, no bundler, no framework. CommonJS modules.

**Parent spec:** [`docs/superpowers/specs/2026-05-10-networking-lobby-foundation-design.md`](../specs/2026-05-10-networking-lobby-foundation-design.md). All decisions in this plan trace back to that spec — re-read §6.1 (protocol table) before starting Task 4.

**Companion plan (future):** A separate `2026-05-10-godot-lobby-client.md` will be written after this plan is fully implemented and the server is deployable. That plan consumes the protocol contract this plan delivers.

---

## File Structure

```
server/
  .gitignore               # excludes node_modules/
  .nvmrc                   # pins Node 20
  package.json             # deps: ws ^8.18.0; scripts: start, test
  package-lock.json        # generated
  README.md                # how to run, deploy, configure
  fly.toml                 # Fly.io deployment config
  Dockerfile               # for Fly.io (or any container PaaS)
  index.js                 # entry: parses PORT, boots server
  src/
    code-generator.js      # pure: generates 6-char Crockford codes
    session-store.js       # state: code -> host session, with TTL
    server.js              # WebSocket server, message dispatch, lifecycle
  test/
    code-generator.test.js
    session-store.test.js
    server.test.js         # integration tests against real ws server
```

Each source file has a single responsibility:
- `code-generator.js` — no external state, no I/O. Trivially testable.
- `session-store.js` — owns the `code → session` map and TTL timers. Injectable clock for tests.
- `server.js` — owns the WebSocket server, accepts connections, parses JSON, dispatches by `type`. Composes the other two modules.
- `index.js` — boot only. `process.env.PORT`, `process.env.LOG_LEVEL`. Calls `server.start(port)`.

## Conventions

- **TDD strictly:** failing test → run and watch it fail → minimum implementation → run and watch it pass → commit. Never skip the "watch it fail" step — it verifies the test is actually exercising the code. A few tasks in this plan exercise already-built modules and will pass on first run; those are clearly labeled as "watch pass" rather than "watch fail."
- **Commit prefixes:** `feat(server):`, `test(server):`, `chore(server):`, `docs(server):`, `refactor(server):`. The `(server)` scope distinguishes from later Godot client commits.
- **No skipping the protocol contract.** §6.1 of the spec is the source of truth for every message shape. If you find yourself wanting to deviate, update the spec first.
- **Co-author footer** on every commit:
  ```
  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  ```

## Protocol Additions Beyond Spec §6.1

The spec's §6.1 protocol table lists the message types Godot clients send and the responses they expect. The broker also produces a few **error reasons** and one **notification** that aren't enumerated in §6.1. These are broker implementation details (the Godot client needs to recognize them, but they don't change the behavior described in the spec):

| Symbol | Direction | When |
|---|---|---|
| `joiner_left` (type) | Server → host | A pending joiner's WebSocket closes mid-handshake before completing the WebRTC connection. |
| `host_left` (type) | Server → pending joiner | Host's WebSocket closed while joiner was still in handshake. Symmetric with `joiner_left`. |
| `start_match` (type) | Client (host) → server | Host signals lobby is closed. Server sets `session.started = true`. Replies with `match_started`. |
| `match_started` (type) | Server → host | Ack for `start_match`. |
| `error: not_host` | Server → client | Sent if a non-host socket sends `start_match`. |
| `error: already_host` | Server → client | Client already sent `host` on this socket; rejecting a second `host`. |
| `error: already_joined` | Server → client | Client already sent `join` on this socket; rejecting a second `join`. |
| `error: no_session` | Server → client | `signal` arrived on a socket that has no associated session (e.g., never sent `host`/`join`, or session was pruned). `connected` is a teardown hint and is silently ignored in this case, not errored. |
| `error: unknown_peer` | Server → client | `signal` with `to: N` where N isn't a known peer in this session. |
| `error: bad_json` | Server → client | Malformed JSON message. |
| `error: unknown_type` | Server → client | Recognized envelope but `type` is unknown. |
| `error: server_busy` | Server → client | Could not generate a unique code after several tries (extremely rare). |

**Connected semantics (clarification beyond spec §6.1):** The broker treats `connected` from *either* peer as sufficient to release the handshake slot. The spec wording "stops relaying for that pair" is implemented as "removes the joiner from `pendingJoiners` and closes the joiner's signaling WebSocket on the first `connected`." This is an intentional MVP simplification.

The future Godot client plan (`2026-05-10-godot-lobby-client.md`) will consume these additions.

---

## Phase 1: Scaffold

### Task 1: Initialize the server project

**Files:**
- Create: `server/.gitignore`
- Create: `server/.nvmrc`
- Create: `server/package.json`
- Create: `server/README.md`
- Create: `server/index.js`
- Create: `server/src/server.js`

- [ ] **Step 1: Create `.gitignore`**

`server/.gitignore`:
```
node_modules/
*.log
.env
.env.local
```

- [ ] **Step 2: Create `.nvmrc` pinning Node 20**

`server/.nvmrc`:
```
20
```

- [ ] **Step 3: Create `package.json`**

`server/package.json`:
```json
{
  "name": "riskroyal-signaling",
  "version": "0.1.0",
  "description": "WebRTC signaling server for Risk Royal lobbies",
  "private": true,
  "type": "commonjs",
  "engines": {
    "node": ">=20"
  },
  "scripts": {
    "start": "node index.js",
    "test": "node --test \"test/**/*.test.js\""
  },
  "dependencies": {
    "ws": "^8.18.0"
  }
}
```

- [ ] **Step 4: Create the bootable skeleton**

`server/index.js`:
```js
const { start } = require('./src/server');

const port = parseInt(process.env.PORT, 10) || 8080;
start(port);
```

`server/src/server.js`:
```js
const { WebSocketServer } = require('ws');

function start(port) {
  const wss = new WebSocketServer({ port });
  wss.on('connection', (ws) => {
    ws.on('message', (data) => {
      // Filled in by later tasks.
    });
  });
  console.log(`signaling server listening on :${port}`);
  return wss;
}

module.exports = { start };
```

- [ ] **Step 5: Install dependencies**

Run from `server/`:
```
npm install
```

Expected: creates `package-lock.json` and `node_modules/`. No errors.

- [ ] **Step 6: Smoke-test that the server boots and accepts a connection**

Run from `server/`:
```
node index.js &
```

Then in another terminal:
```
node -e "const W=require('ws'); const w=new W('ws://localhost:8080'); w.on('open',()=>{console.log('OK');w.close();process.exit(0)}); w.on('error',e=>{console.error(e.message);process.exit(1)})"
```

Expected: prints `OK` and exits 0. Kill the server (`fg`, Ctrl-C) after.

- [ ] **Step 7: Create README**

`server/README.md`:
```markdown
# Risk Royal Signaling Server

WebSocket server that brokers WebRTC handshakes between game clients using 6-character codes.

## Run locally

    npm install
    npm start          # listens on :8080 by default; PORT env var overrides

## Run tests

    npm test

## Deploy

See `fly.toml` and `Dockerfile`. Created in Task 13.
```

- [ ] **Step 8: Commit**

```
git add server/
git commit -m "$(cat <<'EOF'
chore(server): scaffold Node.js signaling server

- Bootable empty server on configurable PORT (default 8080)
- ws ^8.18.0 dependency
- package.json scripts: start, test (node:test)
- README with run/test instructions

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2: Code Generator (pure function)

### Task 2: Crockford base32 code generator with TDD

The spec §6.1 requires 6-character codes from Crockford base32, excluding `0/O`, `1/I/L`, `U`. That's 30 distinct characters: `23456789ABCDEFGHJKMNPQRSTVWXYZ`. Codes must be case-insensitive on input but emitted uppercase.

**Files:**
- Create: `server/test/code-generator.test.js`
- Create: `server/src/code-generator.js`

- [ ] **Step 1: Write the failing test for character set + length**

`server/test/code-generator.test.js`:
```js
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { generateCode, normalizeCode, ALPHABET } = require('../src/code-generator');

test('ALPHABET excludes ambiguous chars and has 30 unique letters', () => {
  assert.equal(ALPHABET.length, 30);
  assert.equal(new Set(ALPHABET).size, 30);
  for (const bad of ['0', 'O', '1', 'I', 'L', 'U']) {
    assert.ok(!ALPHABET.includes(bad), `ALPHABET must not include "${bad}"`);
  }
});

test('generateCode returns 6 uppercase chars from ALPHABET', () => {
  for (let i = 0; i < 50; i++) {
    const c = generateCode();
    assert.equal(c.length, 6, `got "${c}"`);
    assert.equal(c, c.toUpperCase(), `got "${c}"`);
    for (const ch of c) {
      assert.ok(ALPHABET.includes(ch), `char "${ch}" not in ALPHABET (code="${c}")`);
    }
  }
});
```

- [ ] **Step 2: Run the test and watch it fail**

Run:
```
npm test
```

Expected: `Cannot find module '../src/code-generator'` — the module doesn't exist yet.

- [ ] **Step 3: Implement the minimum that makes the tests pass**

`server/src/code-generator.js`:
```js
const crypto = require('node:crypto');

const ALPHABET = '23456789ABCDEFGHJKMNPQRSTVWXYZ';

function generateCode() {
  const bytes = crypto.randomBytes(6);
  let out = '';
  for (let i = 0; i < 6; i++) {
    out += ALPHABET[bytes[i] % ALPHABET.length];
  }
  return out;
}

function normalizeCode(input) {
  if (typeof input !== 'string') return null;
  return input.trim().toUpperCase();
}

module.exports = { generateCode, normalizeCode, ALPHABET };
```

- [ ] **Step 4: Run the test and watch it pass**

Run:
```
npm test
```

Expected: both tests pass. `node:test` prints `# pass 2`.

- [ ] **Step 5: Add the uniqueness test**

Append to `test/code-generator.test.js`:
```js
test('generateCode produces few collisions across 10000 samples', () => {
  const codes = new Set();
  for (let i = 0; i < 10000; i++) codes.add(generateCode());
  // 30^6 = ~729M codepoints. Expected collisions in 10k samples << 1.
  assert.ok(codes.size > 9990, `only ${codes.size} unique out of 10000`);
});

test('normalizeCode uppercases and trims', () => {
  assert.equal(normalizeCode('  abc234 '), 'ABC234');
  assert.equal(normalizeCode('AbCdEf'), 'ABCDEF');
  assert.equal(normalizeCode(''), '');
  assert.equal(normalizeCode(null), null);
  assert.equal(normalizeCode(undefined), null);
});
```

- [ ] **Step 6: Run all tests and verify pass**

Run:
```
npm test
```

Expected: 4 tests pass.

- [ ] **Step 7: Commit**

```
git add server/src/code-generator.js server/test/code-generator.test.js
git commit -m "$(cat <<'EOF'
feat(server): add Crockford base32 code generator

6-char codes from a 30-char alphabet excluding 0/O, 1/I/L, U.
Cryptographically random. normalizeCode trims and uppercases joiner input.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3: Session Store (state with TTL)

### Task 3: In-memory session store with injectable clock

**Files:**
- Create: `server/test/session-store.test.js`
- Create: `server/src/session-store.js`

The session store is the heart of the server's state. It maps `code → session` where a session holds a reference to the host's WebSocket, the joiner ID counter, and an inactivity timestamp. Time is injected so TTL is testable without real waits.

- [ ] **Step 1: Write the failing test for put + get**

`server/test/session-store.test.js`:
```js
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
```

- [ ] **Step 2: Run and watch fail**

Run:
```
npm test
```

Expected: cannot find module.

- [ ] **Step 3: Implement minimum to pass**

`server/src/session-store.js`:
```js
function createSessionStore({ clock = () => Date.now(), ttlMs = 600000 } = {}) {
  const sessions = new Map(); // code -> session

  function create(code, hostWs) {
    if (sessions.has(code)) return null;
    const session = {
      code,
      hostWs,
      nextJoinerId: 2,         // 1 is the host
      pendingJoiners: new Map(), // joinerId -> joinerWs (during handshake only)
      lastActivityAt: clock(),
      started: false,           // becomes true when host signals match start
    };
    sessions.set(code, session);
    return session;
  }

  function getByCode(code) {
    return sessions.get(code) || null;
  }

  function remove(code) {
    return sessions.delete(code);
  }

  function touch(session) {
    session.lastActivityAt = clock();
  }

  function pruneExpired() {
    const cutoff = clock() - ttlMs;
    const removed = [];
    for (const [code, s] of sessions) {
      if (s.lastActivityAt < cutoff) {
        sessions.delete(code);
        removed.push(code);
      }
    }
    return removed;
  }

  function size() { return sessions.size; }

  return { create, getByCode, remove, touch, pruneExpired, size };
}

module.exports = { createSessionStore };
```

- [ ] **Step 4: Run and watch pass**

Run:
```
npm test
```

Expected: tests added in this task all pass.

- [ ] **Step 5: Add tests for TTL pruning + touch**

Append to `test/session-store.test.js`:
```js
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
```

- [ ] **Step 6: Run all tests, verify pass**

Run:
```
npm test
```

Expected: all session-store tests pass alongside code-generator tests.

- [ ] **Step 7: Commit**

```
git add server/src/session-store.js server/test/session-store.test.js
git commit -m "$(cat <<'EOF'
feat(server): in-memory session store with injectable clock

create / getByCode / remove / touch / pruneExpired. TTL defaults to 10 min
per spec §6.1. Injectable clock keeps TTL tests synchronous (no real waits).
Sessions track hostWs, monotonic nextJoinerId starting at 2 (host is 1),
pendingJoiners map for in-flight handshakes, and a started flag.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4: WebSocket Dispatch + Protocol Handlers

These tasks all share a test harness that boots a real `ws` server on a random port and connects real client sockets. The harness lives at the top of `server/test/server.test.js`.

### Task 4: Test harness + message dispatch skeleton

**Files:**
- Modify: `server/src/server.js`
- Create: `server/test/server.test.js`

- [ ] **Step 1: Write a harness + failing dispatch test**

`server/test/server.test.js`:
```js
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

// Exports for next tasks to use:
module.exports = { connect, send, recv };
```

`server/test/_helpers.js`:
```js
const { start } = require('../src/server');

async function startTestServer(opts = {}) {
  const wss = start(0, opts); // port 0 = pick a free one
  await new Promise((resolve) => wss.once('listening', resolve));
  const port = wss.address().port;
  return {
    port,
    close: () => new Promise((resolve) => wss.close(resolve)),
    store: wss._store,
  };
}

module.exports = { startTestServer };
```

- [ ] **Step 2: Run, watch fail**

Run:
```
npm test
```

Expected: tests fail because `server.js` doesn't dispatch or handle unknown types.

- [ ] **Step 3: Implement dispatch in server.js**

Replace `server/src/server.js` with:
```js
const { WebSocketServer } = require('ws');
const { createSessionStore } = require('./session-store');
const { generateCode, normalizeCode } = require('./code-generator');

function sendJson(ws, obj) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
}

function sendError(ws, reason) {
  sendJson(ws, { type: 'error', reason });
}

function start(port, opts = {}) {
  const store = opts.store || createSessionStore({});
  const wss = new WebSocketServer({ port });
  wss._store = store;

  wss.on('connection', (ws) => {
    ws._role = null;       // 'host' | 'joiner'
    ws._peerId = null;
    ws._code = null;

    ws.on('message', (data) => {
      let msg;
      try { msg = JSON.parse(data.toString()); }
      catch { return sendError(ws, 'bad_json'); }

      switch (msg.type) {
        // Filled in by tasks 5–8.
        default:
          return sendError(ws, 'unknown_type');
      }
    });

    ws.on('close', () => {
      // Filled in by task 10.
    });
  });

  wss.on('listening', () => {
    console.log(`signaling server listening on :${wss.address().port}`);
  });

  return wss;
}

module.exports = { start };
```

- [ ] **Step 4: Run, watch pass**

Run:
```
npm test
```

Expected: harness tests pass.

- [ ] **Step 5: Commit**

```
git add server/src/server.js server/test/server.test.js server/test/_helpers.js
git commit -m "$(cat <<'EOF'
feat(server): WebSocket dispatch skeleton with test harness

Boots a ws server on configurable port (0 = ephemeral for tests).
Handles malformed JSON and unknown message types with structured errors.
_helpers.js exposes a startTestServer fixture for integration tests.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Host message → issue code

**Files:**
- Modify: `server/src/server.js`
- Modify: `server/test/server.test.js`

- [ ] **Step 1: Write the failing test**

Append to `server/test/server.test.js`:
```js
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
```

- [ ] **Step 2: Run, watch fail**

Expected: dispatch returns `unknown_type` instead of `code`.

- [ ] **Step 3: Implement the `host` handler**

In `server/src/server.js`, replace the `switch (msg.type)` block:
```js
switch (msg.type) {
  case 'host': {
    if (ws._role) return sendError(ws, 'already_host');
    // try a few times in case of (extremely unlikely) collision
    let code = null;
    for (let i = 0; i < 5 && !code; i++) {
      const candidate = generateCode();
      if (!store.getByCode(candidate)) code = candidate;
    }
    if (!code) return sendError(ws, 'server_busy');
    store.create(code, ws);
    ws._role = 'host';
    ws._peerId = 1;
    ws._code = code;
    return sendJson(ws, { type: 'code', code });
  }
  default:
    return sendError(ws, 'unknown_type');
}
```

- [ ] **Step 4: Run, watch pass**

Run `npm test`. Expected: 2 new tests pass.

- [ ] **Step 5: Commit**

```
git add server/src/server.js server/test/server.test.js
git commit -m "$(cat <<'EOF'
feat(server): handle host message and issue session code

Host opens a WebSocket and sends {type:"host"}. Server picks a unique 6-char
code, registers the session, and replies {type:"code", code}. Second host
message on the same socket is rejected with already_host.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Join message → forward joiner to host, with errors

The join path has four outcomes:
1. Code unknown → `error: unknown_code` to joiner.
2. Host's session is full (8 connected players) → `error: full`.
3. Host's session has already started → `error: in_progress`.
4. Happy path → server assigns `joinerId`, sends `joiner` to host, joiner waits for SDP.

For MVP, "full" is checked against `session.nextJoinerId > 8`. The match-in-progress check uses `session.started`. Both fields exist on the session per Task 3.

**Files:**
- Modify: `server/src/server.js`
- Modify: `server/test/server.test.js`

- [ ] **Step 1: Write failing tests for each outcome**

Append to `server/test/server.test.js`:
```js
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
```

- [ ] **Step 2: Run, watch fail**

Run `npm test`. Expected: 6 new join tests fail.

- [ ] **Step 3: Implement the `join` handler**

Add to the `switch` in `server/src/server.js`, before `default`:
```js
case 'join': {
  if (ws._role) return sendError(ws, 'already_joined');
  const code = normalizeCode(msg.code);
  if (!code) return sendError(ws, 'unknown_code');
  const session = store.getByCode(code);
  if (!session) return sendError(ws, 'unknown_code');
  if (session.started) return sendError(ws, 'in_progress');
  if (session.nextJoinerId > 8) return sendError(ws, 'full');

  const joinerId = session.nextJoinerId++;
  ws._role = 'joiner';
  ws._peerId = joinerId;
  ws._code = code;
  session.pendingJoiners.set(joinerId, ws);
  store.touch(session);

  const forward = { type: 'joiner', joinerId };
  if (typeof msg.reconnect_token === 'string') {
    forward.reconnect_token = msg.reconnect_token;
  }
  return sendJson(session.hostWs, forward);
}
```

- [ ] **Step 4: Run, watch pass**

Run `npm test`. Expected: all 6 join tests pass.

- [ ] **Step 5: Commit**

```
git add server/src/server.js server/test/server.test.js
git commit -m "$(cat <<'EOF'
feat(server): handle join message with error paths

- Unknown code → error: unknown_code (also covers empty/null code)
- Started session → error: in_progress
- 8 already joined → error: full
- Happy path → host receives {type:"joiner", joinerId} with monotonic id
- Codes are case-insensitive (normalizeCode applied)
- Optional reconnect_token forwarded transparently

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Signal relay (opaque SDP/ICE pass-through)

**Files:**
- Modify: `server/src/server.js`
- Modify: `server/test/server.test.js`

The server must relay `{type:"signal", to, payload}` between host and joiners. The `payload` is opaque — the server never parses SDP or ICE. The `to` is a peerId (1 for host, 2+ for joiners). Sender is identified by `ws._peerId`.

- [ ] **Step 1: Write failing tests**

Append to `server/test/server.test.js`:
```js
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
```

- [ ] **Step 2: Run, watch fail**

Expected: 4 new tests fail.

- [ ] **Step 3: Implement signal relay**

Add to the `switch` in `server/src/server.js`:
```js
case 'signal': {
  if (!ws._code) return sendError(ws, 'no_session');
  const session = store.getByCode(ws._code);
  if (!session) return sendError(ws, 'no_session');
  const to = msg.to;
  let target;
  if (to === 1) target = session.hostWs;
  else target = session.pendingJoiners.get(to);
  if (!target) return sendError(ws, 'unknown_peer');
  store.touch(session);
  return sendJson(target, {
    type: 'signal',
    from: ws._peerId,
    payload: msg.payload,
  });
}
```

- [ ] **Step 4: Run, watch pass**

Run `npm test`. All signal tests should pass.

- [ ] **Step 5: Commit**

```
git add server/src/server.js server/test/server.test.js
git commit -m "$(cat <<'EOF'
feat(server): relay signal messages opaquely between peers

Server forwards {type:"signal", to, payload} as {type:"signal", from, payload}
to the target peer (host or joiner). Payload is never parsed. Errors for
unknown_peer and no_session. touch()es the session to defer TTL pruning.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Connected message → release relay slot

Once the P2P WebRTC connection is up, both peers send `{type:"connected"}` and the server releases the joiner's relay slot. After both ends report connected for a given joiner, the joiner's socket can be closed by the server.

For MVP, the simpler semantics: when EITHER peer reports `connected`, we remove the joiner from `pendingJoiners`. The other peer's later `connected` becomes a no-op. The joiner WebSocket is closed by the server at this point — the P2P link carries everything else.

**Files:**
- Modify: `server/src/server.js`
- Modify: `server/test/server.test.js`

- [ ] **Step 1: Write failing tests**

Append to `server/test/server.test.js`:
```js
test('connected from joiner releases pendingJoiners and closes joiner ws', async () => {
  const { host, joiner, code } = await fullHandshakeSetup();
  const session = env.store.getByCode(code);
  assert.equal(session.pendingJoiners.size, 1);

  await send(joiner, { type: 'connected' });
  // give the server an event-loop tick to close
  await new Promise((r) => setImmediate(r));
  assert.equal(session.pendingJoiners.size, 0);
  await new Promise((r) => joiner.once('close', r));
  assert.equal(joiner.readyState, joiner.CLOSED);
  host.close();
});

test('connected from host (with peerId) releases that joiner', async () => {
  const { host, joiner, code } = await fullHandshakeSetup();
  const session = env.store.getByCode(code);
  await send(host, { type: 'connected', peerId: 2 });
  await new Promise((r) => setImmediate(r));
  assert.equal(session.pendingJoiners.size, 0);
  // host stays open (still hosting)
  assert.equal(host.readyState, host.OPEN);
  host.close(); joiner.close();
});
```

- [ ] **Step 2: Run, watch fail**

Expected: tests fail (no `connected` handler).

- [ ] **Step 3: Implement `connected` handler**

Add to the `switch`:
```js
case 'connected': {
  if (!ws._code) return; // silently ignore
  const session = store.getByCode(ws._code);
  if (!session) return;

  if (ws._role === 'joiner') {
    session.pendingJoiners.delete(ws._peerId);
    ws.close();
  } else if (ws._role === 'host') {
    const target = session.pendingJoiners.get(msg.peerId);
    if (target) {
      session.pendingJoiners.delete(msg.peerId);
      target.close();
    }
  }
  return;
}
```

- [ ] **Step 4: Run, watch pass**

Run `npm test`. Expected: connected tests pass.

- [ ] **Step 5: Commit**

```
git add server/src/server.js server/test/server.test.js
git commit -m "$(cat <<'EOF'
feat(server): handle connected message and release relay slot

When either peer reports {type:"connected"} (host includes peerId; joiner is
implicit), server removes that joiner from pendingJoiners and closes the
joiner WebSocket. Host WebSocket stays open to accept further joiners.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Code TTL enforcement (timer)

The session store can prune; now wire it up so the server actually runs prune periodically.

**Files:**
- Modify: `server/src/server.js`
- Modify: `server/test/server.test.js`

- [ ] **Step 1: Write a test exercising injected clock + manual prune trigger**

This test mostly exercises code from Task 3 (the session store). The new behavior it verifies is that `server.start(port, { store })` accepts an injected store. Expect it to pass on first run if the injection wiring is correct; if not, fix `start()` to read `opts.store`.

Append to `server/test/server.test.js`:
```js
test('idle session is pruned after 10 minutes', async () => {
  // Use a fresh test server with a fake clock.
  const helpers = require('./_helpers');
  let now = 0;
  const customEnv = await helpers.startTestServer({
    store: require('../src/session-store').createSessionStore({
      clock: () => now, ttlMs: 600000,
    }),
  });

  const ws = new WebSocket(`ws://localhost:${customEnv.port}`);
  await new Promise((r) => ws.once('open', r));
  ws.send(JSON.stringify({ type: 'host' }));
  const reply = await new Promise((r) => ws.once('message', (d) => r(JSON.parse(d))));
  const code = reply.code;

  assert.ok(customEnv.store.getByCode(code));
  now = 700000;
  customEnv.store.pruneExpired();
  assert.equal(customEnv.store.getByCode(code), null);

  ws.close();
  await customEnv.close();
});
```

Also modify `_helpers.js` to accept the custom store option:
```js
async function startTestServer(opts = {}) {
  const wss = require('../src/server').start(0, opts);
  await new Promise((resolve) => wss.once('listening', resolve));
  const port = wss.address().port;
  return {
    port,
    close: () => new Promise((resolve) => wss.close(resolve)),
    store: wss._store,
  };
}
```

(It already does — confirm.)

- [ ] **Step 2: Run, watch pass**

This test exercises the store directly (already implemented in Task 3) plus the server's acceptance of an injected store. Run `npm test`.

Expected: test passes if the server correctly accepts `opts.store`. If `wss._store` doesn't reflect the injected store, fix `start()` to use it.

In `server/src/server.js`, ensure:
```js
const store = opts.store || createSessionStore({});
```

is exactly there.

- [ ] **Step 3: Wire automatic pruning timer**

Add to `server/src/server.js`, after `wss._store = store;`:
```js
const pruneInterval = setInterval(() => store.pruneExpired(), 60000);
wss.on('close', () => clearInterval(pruneInterval));
```

- [ ] **Step 4: Write a test that the prune interval is cleared on server close**

Append:
```js
test('server close clears the prune interval (no dangling timers)', async () => {
  const helpers = require('./_helpers');
  const customEnv = await helpers.startTestServer();
  const activeHandlesBefore = process._getActiveHandles().length;
  await customEnv.close();
  // Allow setImmediate tick
  await new Promise((r) => setImmediate(r));
  const activeHandlesAfter = process._getActiveHandles().length;
  assert.ok(activeHandlesAfter <= activeHandlesBefore,
    `handles before=${activeHandlesBefore} after=${activeHandlesAfter}`);
});
```

- [ ] **Step 5: Write a test that messages from a pruned session's socket return `no_session`**

Closes the spec §9.1 coverage gap for "doesn't crash on stale client disconnects/messages after prune."

Append:
```js
test('messages from a socket whose session was pruned return no_session', async () => {
  const helpers = require('./_helpers');
  let now = 0;
  const customEnv = await helpers.startTestServer({
    store: require('../src/session-store').createSessionStore({
      clock: () => now, ttlMs: 600000,
    }),
  });

  // Host a session and capture the still-open WebSocket.
  const host = new WebSocket(`ws://localhost:${customEnv.port}`);
  await new Promise((r) => host.once('open', r));
  host.send(JSON.stringify({ type: 'host' }));
  await new Promise((r) => host.once('message', r)); // discard code

  // Advance time and prune. Host socket remains open but session is gone.
  now = 700000;
  customEnv.store.pruneExpired();

  host.send(JSON.stringify({ type: 'signal', to: 2, payload: {} }));
  const reply = await new Promise((r) => host.once('message', (d) => r(JSON.parse(d))));
  assert.equal(reply.type, 'error');
  assert.equal(reply.reason, 'no_session');

  host.close();
  await customEnv.close();
});
```

- [ ] **Step 6: Run, watch pass**

Run `npm test`. Expected: all TTL/prune/stale tests pass.

- [ ] **Step 7: Commit**

```
git add server/src/server.js server/test/server.test.js server/test/_helpers.js
git commit -m "$(cat <<'EOF'
feat(server): periodic pruning of expired sessions

setInterval triggers store.pruneExpired() every 60s. Cleared on server close
so tests don't leak timers. Injectable store keeps prune logic testable with
fake clocks (no real waits).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Disconnect cleanup

When a host WebSocket closes, free the code immediately. When a pending joiner WebSocket closes during the handshake, remove them from `pendingJoiners` and notify the host.

**Files:**
- Modify: `server/src/server.js`
- Modify: `server/test/server.test.js`

- [ ] **Step 1: Write failing tests**

Append to `server/test/server.test.js`:
```js
test('host disconnect frees the code immediately', async () => {
  const { host, code } = await hostAndGetCode();
  assert.ok(env.store.getByCode(code));
  host.close();
  await new Promise((r) => setTimeout(r, 50));
  assert.equal(env.store.getByCode(code), null);
});

test('joiner disconnect mid-handshake notifies host and removes pending', async () => {
  const { host, joiner, code } = await fullHandshakeSetup();
  const session = env.store.getByCode(code);
  assert.equal(session.pendingJoiners.size, 1);

  joiner.close();
  // Host should receive a {type:"joiner_left", joinerId}
  const m = await recv(host);
  assert.equal(m.type, 'joiner_left');
  assert.equal(m.joinerId, 2);
  assert.equal(session.pendingJoiners.size, 0);
  host.close();
});
```

- [ ] **Step 2: Run, watch fail**

Expected: tests fail (close handler does nothing yet).

- [ ] **Step 3: Implement close handler**

In `server/src/server.js`, replace the `ws.on('close', ...)` block:
```js
ws.on('close', () => {
  if (!ws._code) return;
  const session = store.getByCode(ws._code);
  if (!session) return;

  if (ws._role === 'host') {
    // Notify any pending joiners (they're mid-handshake; tell them it's over)
    for (const [, jWs] of session.pendingJoiners) {
      sendError(jWs, 'host_left');
      jWs.close();
    }
    store.remove(session.code);
  } else if (ws._role === 'joiner') {
    if (session.pendingJoiners.delete(ws._peerId)) {
      sendJson(session.hostWs, { type: 'joiner_left', joinerId: ws._peerId });
    }
  }
});
```

- [ ] **Step 4: Run, watch pass**

Run `npm test`. Expected: disconnect tests pass.

- [ ] **Step 5: Add a host_left propagation test**

Append:
```js
test('host disconnect propagates host_left to pending joiners', async () => {
  const { host, joiner } = await fullHandshakeSetup();
  host.close();
  const m = await recv(joiner);
  assert.equal(m.type, 'error');
  assert.equal(m.reason, 'host_left');
  await new Promise((r) => joiner.once('close', r));
});
```

- [ ] **Step 6: Run, watch pass**

Run `npm test`.

- [ ] **Step 7: Commit**

```
git add server/src/server.js server/test/server.test.js
git commit -m "$(cat <<'EOF'
feat(server): clean up on disconnect

- Host close: notify any pending joiners with host_left, then remove the code.
- Joiner close mid-handshake: notify host with {type:"joiner_left", joinerId}.

These cover the spec §8.5 resilience properties: already-established P2P
peers are unaffected by signaling server connectivity; only in-flight
handshakes care.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 5: Lifecycle, Logging, Deployment

### Task 11: Server lifecycle hooks (SIGINT, SIGTERM)

**Files:**
- Modify: `server/index.js`

- [ ] **Step 1: Add graceful shutdown to index.js**

`server/index.js`:
```js
const { start } = require('./src/server');

const port = parseInt(process.env.PORT, 10) || 8080;
const wss = start(port);

function shutdown(signal) {
  console.log(`received ${signal}, shutting down`);
  wss.close(() => {
    console.log('signaling server stopped');
    process.exit(0);
  });
  // Hard kill after 10s if close hangs
  setTimeout(() => process.exit(1), 10000).unref();
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
```

- [ ] **Step 2: Manual verification**

Run from `server/`:
```
node index.js
```

In another terminal: send a SIGINT (Ctrl-C in the first terminal). Expected: prints `received SIGINT, shutting down`, then `signaling server stopped`, exits cleanly.

- [ ] **Step 3: Commit**

```
git add server/index.js
git commit -m "$(cat <<'EOF'
feat(server): graceful shutdown on SIGINT/SIGTERM

Required for clean container exits on Fly.io / Render. 10s timeout in case
close hangs on a stuck socket.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Structured logging behind LOG_LEVEL

Per spec §9.4, the server has a debug log mode for development. We won't add a logging library — a 20-line helper suffices.

**Files:**
- Create: `server/src/logger.js`
- Modify: `server/src/server.js`

- [ ] **Step 1: Create logger**

`server/src/logger.js`:
```js
const LEVELS = { error: 0, warn: 1, info: 2, debug: 3 };
const active = LEVELS[process.env.LOG_LEVEL] ?? LEVELS.info;

function log(level, event, fields = {}) {
  if (LEVELS[level] > active) return;
  const entry = { ts: new Date().toISOString(), level, event, ...fields };
  console.log(JSON.stringify(entry));
}

module.exports = {
  debug: (event, fields) => log('debug', event, fields),
  info:  (event, fields) => log('info', event, fields),
  warn:  (event, fields) => log('warn', event, fields),
  error: (event, fields) => log('error', event, fields),
};
```

- [ ] **Step 2: Sprinkle log calls in server.js**

In `server/src/server.js`, after each handler:
- `host` issued: `log.info('host_issued', { code })`
- `join` accepted: `log.info('join_accepted', { code, joinerId, reconnect: !!msg.reconnect_token })`
- `join` rejected: `log.warn('join_rejected', { code: msg.code, reason })`
- `signal` relayed: `log.debug('signal_relayed', { from: ws._peerId, to: msg.to })`
- `connected`: `log.debug('connected', { peerId: ws._peerId })`
- Host close: `log.info('host_disconnect', { code: ws._code })`
- Joiner close mid-handshake: `log.info('joiner_disconnect', { code: ws._code, joinerId: ws._peerId })`

At the top of `server.js`, `const log = require('./logger');`.

- [ ] **Step 3: Manual verification**

Run with debug:
```
LOG_LEVEL=debug node index.js
```

In another terminal, send a host message via the smoke client from Task 1. Expected: JSON log lines for each event.

- [ ] **Step 4: Commit**

```
git add server/src/logger.js server/src/server.js
git commit -m "$(cat <<'EOF'
feat(server): structured JSON logging behind LOG_LEVEL

LOG_LEVEL=debug surfaces signal_relayed and connected events for
debugging handshakes. Default (info) covers host/join/disconnect events.
Single-line JSON for easy ingestion by Fly.io / Render log shippers.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: Containerize and configure Fly.io deployment

Fly.io free tier supports a small persistent VM that idles for free. Suitable for MVP signaling traffic.

**Files:**
- Create: `server/Dockerfile`
- Create: `server/fly.toml`
- Create: `server/.dockerignore`
- Modify: `server/README.md`

- [ ] **Step 1: Create `.dockerignore`**

`server/.dockerignore`:
```
node_modules
test
.git
*.log
```

- [ ] **Step 2: Create `Dockerfile`**

`server/Dockerfile`:
```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY index.js ./
COPY src ./src
EXPOSE 8080
ENV PORT=8080
CMD ["node", "index.js"]
```

- [ ] **Step 3: Create `fly.toml`**

`server/fly.toml`:
```toml
app = "riskroyal-signaling"
primary_region = "iad"

[build]

[env]
  PORT = "8080"
  LOG_LEVEL = "info"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = "stop"
  auto_start_machines = true
  min_machines_running = 0

[[vm]]
  cpu_kind = "shared"
  cpus = 1
  memory_mb = 256
```

Note: WebSocket traffic is upgraded HTTP so `http_service` is correct. Fly's load balancer terminates TLS and forwards upgrades.

- [ ] **Step 4: Local Docker smoke test**

From `server/`:
```
docker build -t riskroyal-signaling .
docker run --rm -p 8080:8080 riskroyal-signaling
```

In another terminal, run the smoke client from Task 1. Expected: prints `OK`. Kill container.

- [ ] **Step 5: Update README with deploy section**

Replace the deploy section of `server/README.md`:
```markdown
## Deploy to Fly.io

One-time setup:

    flyctl auth login
    flyctl apps create riskroyal-signaling

Deploy:

    flyctl deploy

Logs:

    flyctl logs

The default `fly.toml` uses the smallest shared VM (256 MB) and auto-stops
when idle. WebSocket traffic is upgraded HTTP, so the `http_service` block
covers it; TLS terminates at Fly's load balancer.

After deploy, the signaling URL for the Godot client is:

    wss://riskroyal-signaling.fly.dev

(Update the Godot client's `NetConfig.SIGNALING_URL` once deployed.)
```

- [ ] **Step 6: Commit**

```
git add server/Dockerfile server/.dockerignore server/fly.toml server/README.md
git commit -m "$(cat <<'EOF'
chore(server): containerize and configure Fly.io deployment

Dockerfile (node:20-alpine, prod deps only) + fly.toml for the smallest
shared VM. Auto-stop when idle to stay on the free tier. README documents
deploy + log commands.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 6: Final Verification

### Task 14: Run the full integration suite + manual end-to-end

- [ ] **Step 1: Run the full test suite**

From `server/`:
```
npm test
```

Expected: every test from Tasks 2–10 passes. No skips, no failures. Run-time under 5 seconds.

- [ ] **Step 2: Manual smoke: full handshake echo**

Boot the server:
```
LOG_LEVEL=debug node index.js
```

In a second terminal, run an inline Node script that simulates host + two joiners exchanging signals:
```
node -e "$(cat <<'JS'
const W=require('ws');
async function go(){
  const host=new W('ws://localhost:8080');
  await new Promise(r=>host.once('open',r));
  host.send(JSON.stringify({type:'host'}));
  const codeMsg=await new Promise(r=>host.once('message',d=>r(JSON.parse(d))));
  console.log('host got code',codeMsg.code);

  const j=new W('ws://localhost:8080');
  await new Promise(r=>j.once('open',r));
  j.send(JSON.stringify({type:'join',code:codeMsg.code}));
  const joinerMsg=await new Promise(r=>host.once('message',d=>r(JSON.parse(d))));
  console.log('host got joiner',joinerMsg);

  host.send(JSON.stringify({type:'signal',to:2,payload:{sdp:'OFFER'}}));
  const offerMsg=await new Promise(r=>j.once('message',d=>r(JSON.parse(d))));
  console.log('joiner got offer',offerMsg);

  j.send(JSON.stringify({type:'signal',to:1,payload:{sdp:'ANSWER'}}));
  const answerMsg=await new Promise(r=>host.once('message',d=>r(JSON.parse(d))));
  console.log('host got answer',answerMsg);

  j.send(JSON.stringify({type:'connected'}));
  await new Promise(r=>j.once('close',r));
  console.log('joiner closed after connected');

  host.close();
}
go().catch(e=>{console.error(e);process.exit(1)});
JS
)"
```

Expected output (in order):
```
host got code <CODE>
host got joiner { type: 'joiner', joinerId: 2 }
joiner got offer { type: 'signal', from: 1, payload: { sdp: 'OFFER' } }
host got answer { type: 'signal', from: 2, payload: { sdp: 'ANSWER' } }
joiner closed after connected
```

Server logs (in the first terminal) should show: `listening`, `host_issued`, `join_accepted`, two `signal_relayed`, one `connected` (debug), and `host_disconnect` when the host closes. Note: no `joiner_disconnect` fires on a graceful `connected` flow — Task 12 places that log only inside the `pendingJoiners.delete()` truthy branch, which is false after Task 8's `connected` handler already removed the joiner.

- [ ] **Step 3: Kill the server (Ctrl-C); verify clean shutdown logs**

Expected: `received SIGINT, shutting down`, `signaling server stopped`, exit 0.

- [ ] **Step 4: Tag the milestone**

```
git tag signaling-server-v0.1
```

- [ ] **Step 5: Final commit if any cleanup**

If any files changed during verification, commit them with `chore(server): final verification cleanup`.

---

## Done

When all checkboxes above are checked, this sub-project deliverable is complete:

1. The server module is at `server/`, fully tested with `npm test`.
2. The server can be deployed to Fly.io with `flyctl deploy`.
3. The protocol matches spec §6.1 exactly.
4. The Godot client plan (`2026-05-10-godot-lobby-client.md`, written separately) can begin development against this server.

**Next step:** Invoke `superpowers:writing-plans` again to produce the Godot client implementation plan, which will consume this server's deployed contract.
