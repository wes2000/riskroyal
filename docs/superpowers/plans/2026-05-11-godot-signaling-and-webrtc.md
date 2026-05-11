# Godot Signaling + WebRTC Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the Godot client's `NetSession` (from Plan B) to a real Node.js signaling server (from Plan A) and a real `WebRTCMultiplayerPeer`, so two headless Godot instances can host/join, exchange SDP/ICE through the signaling broker, complete the WebRTC handshake, populate player lists via RPC, and fire `match_starting`. End-to-end integration smoke test included. No UI in this plan — that's Plan D.

**Architecture:** `SignalingClient` (real `WebSocketPeer` to the broker) and `WebRTCTransport` (wraps `WebRTCMultiplayerPeer`) honor the same signal contracts as Plan B's fakes, so `NetSession`'s existing 55 unit tests stay green. A new `NetSessionMain` autoload Node owns the production lifecycle: instantiates the real transport/signaling, wires the inner `NetSession` RefCounted, and parents a real Timer for the 30 s grace timeout. SDP/ICE flows via `signal_received` → `WebRTCTransport.feed_remote_signal(...)` and `WebRTCTransport.signal_to_send` → `SignalingClient.send_signal(...)`.

**Tech Stack:** Godot 4.6 desktop (`WebSocketPeer`, `WebRTCMultiplayerPeer`, `WebRTCPeerConnection`, `Timer`, autoload), GDScript, GUT for unit + integration tests. Node.js signaling server from Plan A (extended in Task 1) running on `ws://localhost:8080` for integration tests.

**Parent spec:** [`docs/superpowers/specs/2026-05-10-networking-lobby-foundation-design.md`](../specs/2026-05-10-networking-lobby-foundation-design.md). Sub-project #1B continued.

**Protocol contract:** [`docs/superpowers/plans/2026-05-10-signaling-server.md`](2026-05-10-signaling-server.md) §"Protocol Additions" + spec §6.1. **This plan extends the protocol with a new `joined` message** (Task 1) so the joiner can learn its assigned `peer_id` before `WebRTCMultiplayerPeer.create_client(peer_id)` is called (Godot 4.6 requires the peer_id at create-time, ≥ 2).

**Companion plans:**
- Plan A — signaling server: `2026-05-10-signaling-server.md` (implemented; Task 1 amends it).
- Plan B — NetSession foundations: `2026-05-11-godot-netsession-foundations.md` (implemented).
- Plan D (future) — lobby UI + manual playtest checklist. Will be written after Plan C lands.

---

## File Structure

```
server/                                 # Plan A's signaling server
  src/server.js                         # MODIFY: emit 'joined' to joiner on accept
  test/server.test.js                   # MODIFY: test joiner receives peerId
scripts/net/
  signaling_client.gd                   # NEW: real WebSocket client
  signaling_client_interface.gd         # MODIFY: document new peer_id_assigned signal
  fake_signaling_client.gd  (in tests/) # MODIFY: add peer_id_assigned + emit helper
  web_rtc_transport.gd                  # NEW: WebRTCMultiplayerPeer wrapper
  net_session.gd                        # MODIFY: peer_id_assigned handler, Timer arg, welcome/sync RPCs
  net_session_main.gd                   # NEW: autoload that wires real implementations
tests/
  fakes/
    fake_web_socket_peer.gd             # NEW: WebSocketPeer stub for SignalingClient unit tests
    fake_timer.gd                       # NEW: Timer-shaped object for NetSession unit tests
    fake_signaling_client.gd            # MODIFY: see above
  unit/
    test_signaling_client.gd            # NEW: protocol-level unit tests against FakeWebSocketPeer
    test_net_session_timer.gd           # NEW: timer wiring tests using FakeTimer
    test_net_session_snapshot.gd        # NEW: client snapshot RPC tests
    test_web_rtc_transport_smoke.gd     # NEW: minimal smoke test for WebRTCTransport
  integration/
    test_two_instance_handshake.gd      # NEW: 2 NetSessions connect via real signaling server
project.godot                           # MODIFY: register NetSessionMain autoload
```

## Conventions

- TDD strictly: red → run-fail → minimal-green → run-pass → commit.
- Commit prefixes: `feat(client):`, `test(client):`, `chore(client):`, `refactor(client):`, plus `feat(server):` for Task 1 (the server amendment).
- Tabs for indentation in `.gd` files; 2-space indent for JS (matches Plan A).
- No `class_name` registration — keep `preload(...)` discipline from Plan B.
- Headless GUT unit tests:
  ```
  godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
  ```
- Integration tests (separate dir, **require signaling server running**):
  ```
  godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/integration -gexit
  ```
  Start the server with `cd server; node index.js`.
- Server tests still run via `npm test` from `server/`.
- Co-author footer on every commit:
  ```
  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  ```

## Pre-flight: protocol cheat sheet

**Outgoing (client → server):**
- `{type: "host"}` → server replies `{type: "code", code}`
- `{type: "join", code, reconnect_token?}` → server replies to *joiner* with `{type: "joined", peerId}` **(NEW in Task 1)** and forwards to *host* as `{type: "joiner", joinerId, reconnect_token?}`
- `{type: "signal", to, payload}` → server forwards as `{type: "signal", from, payload}`
- `{type: "connected", peerId?}` → server releases relay slot
- `{type: "start_match"}` → server marks session started, replies `{type: "match_started"}`

**Inbound (server → client):**
- `{type: "code", code}` (to host)
- `{type: "joined", peerId}` **(NEW)** (to joiner — tells joiner its assigned peer_id)
- `{type: "joiner", joinerId, reconnect_token?}` (to host)
- `{type: "signal", from, payload}` (to anyone)
- `{type: "joiner_left", joinerId}` (to host)
- `{type: "host_left"}` (to joiner during handshake)
- `{type: "match_started"}` (to host)
- `{type: "error", reason}`

---

## Phase 1: Server protocol extension

### Task 1: Server delivers assigned `peerId` to joiner

The joiner's WebRTC peer needs its assigned id BEFORE calling `WebRTCMultiplayerPeer.create_client(peer_id)` (Godot 4.6 rejects peer_id < 2). The server already knows the assignment — it just needs to also send it to the joiner.

**Files:**
- Modify: `server/src/server.js`
- Modify: `server/test/server.test.js`
- Modify: `docs/superpowers/plans/2026-05-10-signaling-server.md` (protocol additions table)

- [ ] **Step 1: Write the failing test**

Append to `server/test/server.test.js`:
```js
test('joiner receives {type:"joined", peerId} immediately on accept', async () => {
  const { host, code } = await hostAndGetCode();
  const joiner = await connect();
  await send(joiner, { type: 'join', code });

  // Joiner first message should be 'joined' with the assigned peerId.
  const joinerMsg = await recv(joiner);
  assert.equal(joinerMsg.type, 'joined');
  assert.equal(joinerMsg.peerId, 2);

  // Host still receives the existing 'joiner' forward.
  const hostMsg = await recv(host);
  assert.equal(hostMsg.type, 'joiner');
  assert.equal(hostMsg.joinerId, 2);

  host.close(); joiner.close();
});
```

- [ ] **Step 2: Run, watch fail**

From `server/`:
```
npm test
```

Expected: this one test fails (joiner currently never receives an acknowledgment).

- [ ] **Step 3: Implement**

In `server/src/server.js`, modify the `join` case. Find the line that sends the `joiner` forward to the host and INSERT before it:
```js
// Tell the joiner what peer_id the server assigned (Plan C: WebRTC create_client needs this).
sendJson(ws, { type: 'joined', peerId: joinerId });
log.debug('joined_ack', { code: session.code, joinerId });
```

This must go AFTER `const joinerId = session.nextJoinerId++;` and AFTER the `ws._role`/`ws._peerId` assignments, but BEFORE the `sendJson(session.hostWs, forward)` call. Order matters because the test expects the joiner's `joined` to arrive before the host's `joiner`.

- [ ] **Step 4: Run, watch pass**

From `server/`:
```
npm test
```

Expected: 56/56 pass (55 prior + 1 new).

- [ ] **Step 5: Update protocol-additions docs**

In `docs/superpowers/plans/2026-05-10-signaling-server.md`, find the "Protocol Additions Beyond Spec §6.1" table. Add a row:
```
| `joined` (type) | Server → joiner | Server's reply to a successful `join` carrying the assigned `peerId`. Sent before the `joiner` forward to the host so the joiner can call `WebRTCMultiplayerPeer.create_client(peerId)` (Godot requires peer_id ≥ 2 at create-time). |
```

- [ ] **Step 6: Commit**

```
feat(server): emit 'joined' message to joiner with assigned peerId

The joiner needs its assigned peer_id BEFORE calling Godot's
WebRTCMultiplayerPeer.create_client(peer_id), which rejects peer_id < 2.
The server already knows the assignment; it now sends
{type:"joined", peerId} to the joiner immediately on accept, before the
existing {type:"joiner", joinerId} forward to the host.

Plan A's protocol-additions doc updated. Existing 55 server tests unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 2: SignalingClient

### Task 2: `FakeWebSocketPeer` test double

**Files:**
- Create: `tests/fakes/fake_web_socket_peer.gd`

- [ ] **Step 1: Create the fake**

`tests/fakes/fake_web_socket_peer.gd`:
```gdscript
# Test double for Godot's WebSocketPeer.
# Tests drive incoming packets via emit_packet(dict).
extends RefCounted

const STATE_CONNECTING := 0
const STATE_OPEN := 1
const STATE_CLOSING := 2
const STATE_CLOSED := 3

var connect_to_url_calls: Array = []
var sent_packets: Array = []
var close_calls: int = 0
var ready_state: int = STATE_CONNECTING

var _inbound_queue: Array = []

func connect_to_url(url: String, _tls_options = null) -> int:
    connect_to_url_calls.append({"url": url})
    ready_state = STATE_OPEN
    return OK

func poll() -> void:
    pass

func get_ready_state() -> int:
    return ready_state

func put_packet(bytes: PackedByteArray) -> int:
    sent_packets.append(bytes.get_string_from_utf8())
    return OK

func get_available_packet_count() -> int:
    return _inbound_queue.size()

func get_packet() -> PackedByteArray:
    if _inbound_queue.is_empty():
        return PackedByteArray()
    var s: String = _inbound_queue.pop_front()
    return s.to_utf8_buffer()

func close(_code: int = 1000, _reason: String = "") -> void:
    close_calls += 1
    ready_state = STATE_CLOSED

# --- test helpers ---

func emit_packet(obj) -> void:
    var s: String = JSON.stringify(obj) if typeof(obj) != TYPE_STRING else obj
    _inbound_queue.append(s)

func set_ready_state(s: int) -> void:
    ready_state = s
```

- [ ] **Step 2: Verify GUT still runs cleanly**

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
```

Expected: 55/55 pass (unchanged; this file is test scaffolding).

- [ ] **Step 3: Commit**

```
test(client): add FakeWebSocketPeer test double

Mirrors Godot's WebSocketPeer surface (connect_to_url, poll, put_packet,
get_packet, close, ready_state, STATE_* constants). emit_packet helper
lets tests inject inbound JSON packets without a real network.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 3: `SignalingClient` skeleton + outgoing API

**Files:**
- Create: `scripts/net/signaling_client.gd`
- Create: `tests/unit/test_signaling_client.gd`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_signaling_client.gd`:
```gdscript
extends GutTest

const SignalingClient = preload("res://scripts/net/signaling_client.gd")
const FakeWebSocketPeer = preload("res://tests/fakes/fake_web_socket_peer.gd")

var ws
var client

func before_each():
    ws = FakeWebSocketPeer.new()
    client = SignalingClient.new(ws)

func _sent_messages() -> Array:
    var out: Array = []
    for s in ws.sent_packets:
        out.append(JSON.parse_string(s))
    return out

func test_signals_declared():
    assert_true(client.has_signal("code_issued"))
    assert_true(client.has_signal("peer_arriving"))
    assert_true(client.has_signal("peer_id_assigned"))
    assert_true(client.has_signal("match_started_ack"))
    assert_true(client.has_signal("host_left"))
    assert_true(client.has_signal("joiner_left"))
    assert_true(client.has_signal("signaling_error"))
    assert_true(client.has_signal("signal_received"))

func test_request_code_opens_connection_and_sends_host():
    client.request_code()
    assert_eq(ws.connect_to_url_calls.size(), 1)
    var sent = _sent_messages()
    assert_eq(sent.size(), 1)
    assert_eq(sent[0].type, "host")

func test_connect_to_code_sends_join():
    client.connect_to_code("ABC234")
    var sent = _sent_messages()
    assert_eq(sent[0].type, "join")
    assert_eq(sent[0].code, "ABC234")
    assert_false(sent[0].has("reconnect_token"))

func test_connect_to_code_with_token_includes_token():
    client.connect_to_code("ABC234", "tok123")
    var sent = _sent_messages()
    assert_eq(sent[0].reconnect_token, "tok123")

func test_send_signal_serializes_payload():
    client.connect_to_code("ABC234")
    ws.sent_packets.clear()
    client.send_signal(1, {"sdp": "OFFER"})
    var sent = _sent_messages()
    assert_eq(sent[0].type, "signal")
    assert_eq(sent[0].to, 1)
    assert_eq(sent[0].payload, {"sdp": "OFFER"})

func test_notify_connected_with_no_peer_id():
    client.connect_to_code("ABC234")
    ws.sent_packets.clear()
    client.notify_connected()
    var sent = _sent_messages()
    assert_eq(sent[0].type, "connected")
    assert_false(sent[0].has("peerId"))

func test_notify_connected_with_peer_id():
    client.request_code()
    ws.sent_packets.clear()
    client.notify_connected(2)
    var sent = _sent_messages()
    assert_eq(sent[0].peerId, 2)

func test_send_start_match():
    client.request_code()
    ws.sent_packets.clear()
    client.send_start_match()
    var sent = _sent_messages()
    assert_eq(sent[0].type, "start_match")

func test_close_calls_underlying_close():
    client.request_code()
    client.close()
    assert_eq(ws.close_calls, 1)
```

- [ ] **Step 2: Run, watch fail**

Expected: parse failure.

- [ ] **Step 3: Implement**

`scripts/net/signaling_client.gd`:
```gdscript
# Real WebSocket signaling client.
# Honors res://scripts/net/signaling_client_interface.gd's signal contract.
extends RefCounted

const NetConfig = preload("res://scripts/net/net_config.gd")

signal code_issued(code: String)
signal peer_arriving(joiner_id: int, reconnect_token: String)
signal peer_id_assigned(peer_id: int)
signal match_started_ack()
signal host_left()
signal joiner_left(joiner_id: int)
signal signaling_error(reason: String)
signal signal_received(from_peer: int, payload: Dictionary)

var _ws
var _url: String
var _connected_url := false

func _init(ws_peer = null, url: String = NetConfig.SIGNALING_URL) -> void:
    if ws_peer == null:
        ws_peer = WebSocketPeer.new()
    _ws = ws_peer
    _url = url

func _ensure_connected() -> void:
    if _connected_url:
        return
    _ws.connect_to_url(_url)
    _connected_url = true

func _send(obj: Dictionary) -> void:
    _ensure_connected()
    var s := JSON.stringify(obj)
    _ws.put_packet(s.to_utf8_buffer())

func request_code() -> void:
    _send({"type": "host"})

func connect_to_code(code: String, reconnect_token: String = "") -> void:
    var msg := {"type": "join", "code": code}
    if reconnect_token != "":
        msg["reconnect_token"] = reconnect_token
    _send(msg)

func send_signal(to_peer: int, payload: Dictionary) -> void:
    _send({"type": "signal", "to": to_peer, "payload": payload})

func notify_connected(peer_id: int = 0) -> void:
    var msg := {"type": "connected"}
    if peer_id != 0:
        msg["peerId"] = peer_id
    _send(msg)

func send_start_match() -> void:
    _send({"type": "start_match"})

func close() -> void:
    _ws.close()
    _connected_url = false

# Called every tick by the autoload to drain inbound packets.
func pump() -> void:
    _ws.poll()
    while _ws.get_available_packet_count() > 0:
        var bytes := _ws.get_packet()
        var s := bytes.get_string_from_utf8()
        var parsed = JSON.parse_string(s)
        if typeof(parsed) != TYPE_DICTIONARY:
            continue
        _dispatch_inbound(parsed)

func _dispatch_inbound(_msg: Dictionary) -> void:
    pass  # Filled in by Tasks 4-6.
```

- [ ] **Step 4: Run, watch pass**

Expected: 64/64 pass (55 prior + 9 new — note `peer_id_assigned` is in the signal-existence test).

- [ ] **Step 5: Commit**

```
feat(client): SignalingClient skeleton with outgoing message API

WebSocket-based signaling client. Accepts an injectable WebSocketPeer-like
object (real WebSocketPeer in production; FakeWebSocketPeer in tests).
9 unit tests cover the outgoing methods (host, join, signal, connected,
start_match, close), the optional-token / optional-peerId branches, and
the signal contract including peer_id_assigned (handled by Task 4).
Inbound dispatch stubbed; Tasks 4-6 fill it in.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 4: SignalingClient inbound — `code`, `joiner`, `joined`

**Files:**
- Modify: `scripts/net/signaling_client.gd`
- Modify: `scripts/net/signaling_client_interface.gd` (document `peer_id_assigned`)
- Modify: `tests/fakes/fake_signaling_client.gd` (mirror `peer_id_assigned`)
- Modify: `tests/unit/test_signaling_client.gd`

- [ ] **Step 1: Append tests**

In `tests/unit/test_signaling_client.gd`:
```gdscript
func test_inbound_code_emits_code_issued():
    client.request_code()
    var received := []
    client.code_issued.connect(func(c): received.append(c))
    ws.emit_packet({"type": "code", "code": "QX7K2P"})
    client.pump()
    assert_eq(received, ["QX7K2P"])

func test_inbound_joined_emits_peer_id_assigned():
    client.connect_to_code("ABC234")
    var received := []
    client.peer_id_assigned.connect(func(id): received.append(id))
    ws.emit_packet({"type": "joined", "peerId": 2})
    client.pump()
    assert_eq(received, [2])

func test_inbound_joiner_without_token_emits_peer_arriving_with_empty_token():
    client.request_code()
    var received := []
    client.peer_arriving.connect(func(jid, tok): received.append([jid, tok]))
    ws.emit_packet({"type": "joiner", "joinerId": 2})
    client.pump()
    assert_eq(received, [[2, ""]])

func test_inbound_joiner_with_token_emits_peer_arriving_with_token():
    client.request_code()
    var received := []
    client.peer_arriving.connect(func(jid, tok): received.append([jid, tok]))
    ws.emit_packet({"type": "joiner", "joinerId": 3, "reconnect_token": "abc"})
    client.pump()
    assert_eq(received, [[3, "abc"]])
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/net/signaling_client.gd`, replace `_dispatch_inbound`:
```gdscript
func _dispatch_inbound(msg: Dictionary) -> void:
    match msg.get("type", ""):
        "code":
            code_issued.emit(msg.get("code", ""))
        "joined":
            peer_id_assigned.emit(int(msg.get("peerId", 0)))
        "joiner":
            var tok: String = msg.get("reconnect_token", "")
            peer_arriving.emit(int(msg.get("joinerId", 0)), tok)
        _:
            pass  # Other types in Tasks 5-6.
```

Update `scripts/net/signaling_client_interface.gd` to document the new signal. Add to the signal list comment block:
```
#   peer_id_assigned(peer_id: int)
```

Update `tests/fakes/fake_signaling_client.gd`. Add to the signals block:
```gdscript
signal peer_id_assigned(peer_id: int)
```
And add a helper:
```gdscript
func emit_peer_id_assigned(peer_id: int) -> void:
    peer_id_assigned.emit(peer_id)
```

- [ ] **Step 4: Run, watch pass**

Expected: 68/68 pass (64 prior + 4 new).

- [ ] **Step 5: Commit**

```
feat(client): SignalingClient inbound dispatch for code, joined, joiner

pump() polls the WebSocket and decodes JSON packets, dispatching by type:
- code -> code_issued
- joined -> peer_id_assigned (NEW per Task 1 server change)
- joiner -> peer_arriving(joiner_id, reconnect_token)

FakeSignalingClient and the interface doc updated to mirror the new
peer_id_assigned signal so NetSession's wiring (Task 8) can stay agnostic
to real vs. fake.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 5: SignalingClient inbound — `signal`, `match_started`, `host_left`, `joiner_left`

**Files:**
- Modify: `scripts/net/signaling_client.gd`
- Modify: `tests/unit/test_signaling_client.gd`

- [ ] **Step 1: Append tests**

```gdscript
func test_inbound_signal_emits_signal_received():
    client.request_code()
    var received := []
    client.signal_received.connect(func(from_peer, payload): received.append([from_peer, payload]))
    ws.emit_packet({"type": "signal", "from": 2, "payload": {"sdp": "OFFER"}})
    client.pump()
    assert_eq(received, [[2, {"sdp": "OFFER"}]])

func test_inbound_match_started_emits_ack():
    client.request_code()
    var ack_count = [0]
    client.match_started_ack.connect(func(): ack_count[0] += 1)
    ws.emit_packet({"type": "match_started"})
    client.pump()
    assert_eq(ack_count[0], 1)

func test_inbound_host_left_emits_signal():
    client.connect_to_code("ABC234")
    var fired = [false]
    client.host_left.connect(func(): fired[0] = true)
    ws.emit_packet({"type": "host_left"})
    client.pump()
    assert_true(fired[0])

func test_inbound_joiner_left_emits_with_id():
    client.request_code()
    var received := []
    client.joiner_left.connect(func(jid): received.append(jid))
    ws.emit_packet({"type": "joiner_left", "joinerId": 4})
    client.pump()
    assert_eq(received, [4])
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

Extend `_dispatch_inbound` in `scripts/net/signaling_client.gd`:
```gdscript
        "signal":
            var payload = msg.get("payload", {})
            if typeof(payload) != TYPE_DICTIONARY:
                payload = {}
            signal_received.emit(int(msg.get("from", 0)), payload)
        "match_started":
            match_started_ack.emit()
        "host_left":
            host_left.emit()
        "joiner_left":
            joiner_left.emit(int(msg.get("joinerId", 0)))
```

- [ ] **Step 4: Run, watch pass**

Expected: 72/72 pass.

- [ ] **Step 5: Commit**

```
feat(client): SignalingClient inbound dispatch for signal/lifecycle messages

Routes signal -> signal_received, match_started -> match_started_ack,
host_left and joiner_left -> their respective signals. Payload coerced
to Dictionary if malformed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 6: SignalingClient inbound — `error` + unknown-type tolerance

**Files:**
- Modify: `scripts/net/signaling_client.gd`
- Modify: `tests/unit/test_signaling_client.gd`

- [ ] **Step 1: Append tests**

```gdscript
func test_inbound_error_emits_signaling_error():
    client.request_code()
    var received := []
    client.signaling_error.connect(func(reason): received.append(reason))
    ws.emit_packet({"type": "error", "reason": "unknown_code"})
    client.pump()
    assert_eq(received, ["unknown_code"])

func test_inbound_unknown_type_is_ignored():
    client.request_code()
    var fired = [false]
    client.code_issued.connect(func(_c): fired[0] = true)
    ws.emit_packet({"type": "banana"})
    client.pump()
    assert_false(fired[0])

func test_pump_drains_multiple_packets_in_one_call():
    client.request_code()
    var codes := []
    client.code_issued.connect(func(c): codes.append(c))
    ws.emit_packet({"type": "code", "code": "AAA111"})
    ws.emit_packet({"type": "code", "code": "BBB222"})
    client.pump()
    assert_eq(codes, ["AAA111", "BBB222"])
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

Add to `_dispatch_inbound`:
```gdscript
        "error":
            signaling_error.emit(msg.get("reason", "unknown"))
```

- [ ] **Step 4: Run, watch pass**

Expected: 75/75 pass.

- [ ] **Step 5: Commit**

```
feat(client): SignalingClient handles error packets; unknown types ignored

Inbound {type:"error", reason} dispatches to signaling_error.
Unknown types are silently ignored (forward compat). pump() drains all
queued packets in one call.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 3: WebRTCTransport

### Task 7: `WebRTCTransport` (wraps WebRTCMultiplayerPeer)

WebRTC integration is intricate; this task ships the full file plus a minimal smoke test. Real verification is the integration smoke test in Task 11. The plan provides the correct implementation up front.

**Files:**
- Create: `scripts/net/web_rtc_transport.gd`
- Create: `tests/unit/test_web_rtc_transport_smoke.gd`

- [ ] **Step 1: Write the smoke test**

`tests/unit/test_web_rtc_transport_smoke.gd`:
```gdscript
extends GutTest

const WebRTCTransport = preload("res://scripts/net/web_rtc_transport.gd")

func test_instantiates_without_error():
    var t = WebRTCTransport.new()
    assert_not_null(t)

func test_required_signals_declared():
    var t = WebRTCTransport.new()
    assert_true(t.has_signal("peer_joined"))
    assert_true(t.has_signal("peer_left"))
    assert_true(t.has_signal("transport_failed"))
    assert_true(t.has_signal("signal_to_send"))

func test_has_required_methods():
    var t = WebRTCTransport.new()
    assert_true(t.has_method("start_host"))
    assert_true(t.has_method("start_client"))
    assert_true(t.has_method("add_peer"))
    assert_true(t.has_method("close"))
    assert_true(t.has_method("feed_remote_signal"))
    assert_true(t.has_method("pump"))
    assert_true(t.has_method("get_multiplayer_peer"))

func test_feed_remote_signal_with_malformed_payload_does_not_crash():
    var t = WebRTCTransport.new()
    t.start_host()
    # No sdp_type, no ice_candidate — should silently ignore.
    t.feed_remote_signal(2, {"junk": "stuff"})
    assert_true(true)  # No crash = pass.
```

- [ ] **Step 2: Run, watch fail**

Expected: preload failure.

- [ ] **Step 3: Implement**

`scripts/net/web_rtc_transport.gd`:
```gdscript
# Wraps Godot 4.6's WebRTCMultiplayerPeer + per-peer WebRTCPeerConnection
# objects. Honors transport_interface.gd's signal contract plus signal_to_send
# for outbound SDP/ICE delivery (consumed by SignalingClient via NetSessionMain).
#
# Lifecycle:
#   1. start_host() creates the server-side multiplayer peer (peer_id=1).
#      start_client(local_peer_id) creates the client-side peer with the id
#      the signaling server assigned (must be >= 2; see Task 1).
#   2. add_peer(remote_id) creates a WebRTCPeerConnection for that remote.
#      Host calls create_offer() (host initiates); joiner waits for offer
#      via feed_remote_signal().
#   3. SDP and ICE flow out via signal_to_send(to_peer, payload).
#   4. SDP and ICE arrive via feed_remote_signal(from_peer, payload).
#   5. When connection reaches CONNECTED, emits peer_joined(remote_id).
extends RefCounted

const NetConfig = preload("res://scripts/net/net_config.gd")

signal peer_joined(id: int)
signal peer_left(id: int)
signal transport_failed(reason: String)
signal signal_to_send(to_peer: int, payload: Dictionary)

const _ICE_SERVERS := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]}

var _multiplayer_peer  # WebRTCMultiplayerPeer
var _connections: Dictionary = {}        # remote_peer_id -> WebRTCPeerConnection
var _join_emitted: Dictionary = {}       # remote_peer_id -> bool (dedupe peer_joined)
var _is_host: bool = false
var _local_peer_id: int = 0

func _init() -> void:
    _multiplayer_peer = WebRTCMultiplayerPeer.new()

func get_multiplayer_peer():
    return _multiplayer_peer

func start_host() -> void:
    _is_host = true
    _local_peer_id = NetConfig.HOST_PEER_ID
    _multiplayer_peer.create_server()

func start_client(local_peer_id: int) -> void:
    if local_peer_id < 2:
        transport_failed.emit("invalid_local_peer_id:%d" % local_peer_id)
        return
    _is_host = false
    _local_peer_id = local_peer_id
    _multiplayer_peer.create_client(local_peer_id)

func add_peer(remote_id: int) -> void:
    if _connections.has(remote_id):
        return
    var conn := WebRTCPeerConnection.new()
    var err := conn.initialize(_ICE_SERVERS)
    if err != OK:
        transport_failed.emit("ice_init_failed:%d" % err)
        return
    conn.session_description_created.connect(_on_sdp_created.bind(remote_id))
    conn.ice_candidate_created.connect(_on_ice_created.bind(remote_id))
    _connections[remote_id] = conn
    _multiplayer_peer.add_peer(conn, remote_id)
    if _is_host:
        conn.create_offer()
    # Else (joiner): wait for host's offer via feed_remote_signal.

func feed_remote_signal(from_peer: int, payload: Dictionary) -> void:
    if not _connections.has(from_peer):
        # Joiner receiving host's first offer — create the conn lazily.
        add_peer(from_peer)
    if not _connections.has(from_peer):
        return  # add_peer failed; transport_failed already emitted.
    var conn = _connections[from_peer]
    if payload.has("sdp_type"):
        var t: String = payload["sdp_type"]
        var sdp: String = payload.get("sdp", "")
        conn.set_remote_description(t, sdp)
        if t == "offer":
            conn.create_answer()
    elif payload.has("ice_candidate"):
        var ic: Dictionary = payload["ice_candidate"]
        var media: String = ic.get("media", "")
        var index: int = int(ic.get("index", 0))
        var cand_name: String = ic.get("name", "")
        conn.add_ice_candidate(media, index, cand_name)
    # else: malformed payload, ignore.

func close() -> void:
    for id in _connections.keys():
        var c = _connections[id]
        if c != null:
            c.close()
    _connections.clear()
    _join_emitted.clear()
    if _multiplayer_peer != null:
        _multiplayer_peer.close()

# Called every tick by the autoload. Detects newly-CONNECTED connections
# and emits peer_joined exactly once per peer.
#
# Note: We don't call _multiplayer_peer.poll() here because the autoload
# assigns this peer to MultiplayerAPI, which polls it every frame.
func pump() -> void:
    for id in _connections.keys():
        var c = _connections[id]
        if c == null:
            continue
        var s := c.get_connection_state()
        if s == WebRTCPeerConnection.STATE_CONNECTED and not _join_emitted.get(id, false):
            _join_emitted[id] = true
            peer_joined.emit(id)

func _on_sdp_created(type: String, sdp: String, remote_id: int) -> void:
    if not _connections.has(remote_id):
        return
    _connections[remote_id].set_local_description(type, sdp)
    signal_to_send.emit(remote_id, {"sdp_type": type, "sdp": sdp})

func _on_ice_created(media: String, index: int, cand_name: String, remote_id: int) -> void:
    signal_to_send.emit(remote_id, {"ice_candidate": {"media": media, "index": index, "name": cand_name}})
```

- [ ] **Step 4: Run, watch pass**

Expected: 79/79 pass (75 prior + 4 new).

- [ ] **Step 5: Commit**

```
feat(client): WebRTCTransport wrapping WebRTCMultiplayerPeer

Honors transport_interface signal contract (peer_joined, peer_left,
transport_failed) plus signal_to_send for outbound SDP/ICE.

start_client takes the assigned local_peer_id from the signaling
server (Task 1's protocol extension; Godot requires peer_id >= 2 at
WebRTCMultiplayerPeer.create_client time).

Per-peer connections indexed by remote peer_id. Host initiates offers;
joiners wait. ICE/SDP flows via signal_to_send. pump() emits
peer_joined exactly once per peer on the CONNECTED transition.

WebRTC internals are exercised end-to-end by the integration test
in Task 11; per-peer SDP/ICE unit tests would require deep mocking
of Godot's WebRTC subsystem and are not valuable for MVP.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 4: NetSession integration glue

### Task 8: NetSession peer_id_assigned handling (joiner side)

The joiner can't call `WebRTCTransport.start_client(peer_id)` until the signaling server tells it the assigned id (via Task 1's `joined` message → SignalingClient's `peer_id_assigned` signal → NetSession). Modify `join_session` to defer `start_client`, and add a handler.

**Files:**
- Modify: `scripts/net/net_session.gd`
- Modify: `tests/unit/test_net_session_host_join.gd` (update existing test + add new one)

- [ ] **Step 1: Update tests**

In `tests/unit/test_net_session_host_join.gd`, modify `test_join_session_connects_to_code` and add new tests:
```gdscript
func test_join_session_does_not_start_client_until_peer_id_assigned():
    session.join_session("ABC234")
    assert_eq(signaling.connect_to_code_calls.size(), 1)
    assert_false(transport.is_hosting)
    # Note: FakeTransport currently has no record of start_client being called.
    # We rely on the absence of any side-effect at this stage.
    assert_eq(session.local_peer_id, 0, "no local id assigned yet")

func test_peer_id_assigned_sets_local_id_and_starts_client():
    session.join_session("ABC234")
    signaling.emit_peer_id_assigned(2)
    assert_eq(session.local_peer_id, 2)
    # FakeTransport doesn't record start_client args. Add a probe in the next sub-step.
```

For the second assertion, we need `FakeTransport.start_client` to record the peer_id. Update `tests/fakes/fake_transport.gd`:
```gdscript
var start_client_calls: Array = []  # array of peer_ids

func start_client(local_peer_id: int = 0) -> void:
    is_hosting = false
    start_client_calls.append(local_peer_id)
```

Then in the test:
```gdscript
func test_peer_id_assigned_sets_local_id_and_starts_client():
    session.join_session("ABC234")
    signaling.emit_peer_id_assigned(2)
    assert_eq(session.local_peer_id, 2)
    assert_eq(transport.start_client_calls, [2])
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/net/net_session.gd`:

Update `_connect_signals()` to add:
```gdscript
_signaling.peer_id_assigned.connect(_on_peer_id_assigned)
```

Replace `join_session` body:
```gdscript
func join_session(code_input: String) -> void:
    is_host = false
    # Don't call _transport.start_client() yet — we don't know our peer_id.
    # The signaling server will reply with {type:"joined", peerId} which
    # fires peer_id_assigned, and _on_peer_id_assigned will do start_client.
    _signaling.connect_to_code(code_input)
```

Add the new handler (place near `_on_code_issued`):
```gdscript
func _on_peer_id_assigned(peer_id: int) -> void:
    if is_host:
        return  # Host already assigned 1 in host_session().
    local_peer_id = peer_id
    _transport.start_client(peer_id)
```

- [ ] **Step 4: Run, watch pass**

Expected: 81/81 pass (79 prior + 2 new). The old `test_join_session_connects_to_code` test should still pass since `connect_to_code` is still called.

- [ ] **Step 5: Commit**

```
feat(client): NetSession defers start_client until peer_id_assigned

join_session no longer calls transport.start_client() because the joiner
doesn't know its peer_id yet. SignalingClient.peer_id_assigned (Task 4)
delivers the server-assigned id; NetSession's _on_peer_id_assigned
handler sets local_peer_id and calls transport.start_client(peer_id).

FakeTransport.start_client now records its peer_id arg.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 9: NetSession Timer wiring (real grace timeout)

**Files:**
- Create: `tests/fakes/fake_timer.gd`
- Modify: `scripts/net/net_session.gd`
- Create: `tests/unit/test_net_session_timer.gd`

- [ ] **Step 1: Create FakeTimer**

`tests/fakes/fake_timer.gd`:
```gdscript
# Test double for Godot's Timer node. Synchronous: emit_timeout() fires
# the timeout signal immediately.
extends RefCounted

signal timeout()

var wait_time: float = 0.0
var one_shot: bool = true
var start_calls: int = 0
var stop_calls: int = 0
var running: bool = false

func start(time: float = -1.0) -> void:
    if time > 0.0:
        wait_time = time
    start_calls += 1
    running = true

func stop() -> void:
    stop_calls += 1
    running = false

func emit_timeout() -> void:
    running = false
    timeout.emit()
```

- [ ] **Step 2: Write the failing tests**

`tests/unit/test_net_session_timer.gd`:
```gdscript
extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")
const FakeTimer = preload("res://tests/fakes/fake_timer.gd")

var transport
var signaling
var timer
var session

func before_each():
    transport = FakeTransport.new()
    signaling = FakeSignalingClient.new()
    timer = FakeTimer.new()
    session = NetSession.new(transport, signaling, timer)
    session.host_session()
    signaling.emit_code_issued("ABC234")
    transport.emit_peer_joined(2)
    session.receive_player_info(2, "Maya", 3)

func test_peer_left_starts_grace_timer():
    transport.emit_peer_left(2)
    assert_eq(timer.start_calls, 1)
    assert_true(timer.running)

func test_reconnect_within_grace_stops_timer():
    var tok = session.players[1].reconnect_token
    transport.emit_peer_left(2)
    assert_true(timer.running)
    signaling.emit_peer_arriving(4, tok)
    assert_false(timer.running)
    assert_eq(timer.stop_calls, 1)

func test_timer_timeout_invokes_grace_resolution():
    transport.emit_peer_left(2)
    assert_eq(session.players.size(), 2)
    timer.emit_timeout()
    assert_eq(session.players.size(), 1, "disconnected slot removed")
    assert_eq(session.state, NetSessionState.State.LOBBY)

func test_constructor_without_timer_still_works():
    # Legacy tests construct NetSession.new(transport, signaling). Should
    # still work; _on_peer_left becomes a no-op for timer management.
    var t = FakeTransport.new()
    var s = FakeSignalingClient.new()
    var sess = NetSession.new(t, s)
    sess.host_session()
    s.emit_code_issued("AAAAAA")
    t.emit_peer_joined(2)
    t.emit_peer_left(2)  # should not crash
    sess._on_grace_timeout()  # legacy test pattern
    assert_true(true)
```

- [ ] **Step 3: Run, watch fail**

- [ ] **Step 4: Implement**

In `scripts/net/net_session.gd`:

Add `_timer` field near the other deps:
```gdscript
var _timer  # injectable Timer-like; null when running legacy 2-arg tests
```

Update `_init` to accept 3rd arg:
```gdscript
func _init(transport, signaling_client, timer = null):
    _transport = transport
    _signaling = signaling_client
    _timer = timer
    _connect_signals()
    if _timer != null:
        _timer.timeout.connect(_on_grace_timeout)
```

Update `_on_peer_left` to start the timer:
```gdscript
func _on_peer_left(peer_id: int) -> void:
    var slot = _find_slot(peer_id)
    if slot == null:
        return
    slot.connected = false
    if state != NetSessionState.State.PAUSED:
        pre_pause_state = state
        _set_state(NetSessionState.State.PAUSED)
        if _timer != null:
            _timer.start(NetConfig.RECONNECT_GRACE_SEC)
    _emit_player_list_changed()
```

(`_emit_player_list_changed` is the helper from Task 10; for now it's just `players_changed.emit()`.)

Update `_on_peer_arriving` to stop the timer on successful reconnect:
```gdscript
func _on_peer_arriving(joiner_id: int, reconnect_token: String) -> void:
    if not is_host:
        return
    if reconnect_token != "":
        var slot = _find_disconnected_by_token(reconnect_token)
        if slot != null:
            slot.peer_id = joiner_id
            slot.connected = true
            slot.reconnect_token = _generate_token()
            if state == NetSessionState.State.PAUSED:
                _set_state(pre_pause_state)
                if _timer != null:
                    _timer.stop()
            _emit_player_list_changed()
            return
    _transport.add_peer(joiner_id)
```

- [ ] **Step 5: Run, watch pass**

Expected: 85/85 pass (81 prior + 4 new).

- [ ] **Step 6: Commit**

```
feat(client): NetSession real Timer wiring with backward-compat

Constructor accepts an optional 3rd arg: a Timer-like object with start /
stop / timeout signal. _on_peer_left starts it when entering PAUSED;
_on_peer_arriving stops it on a successful reconnect. Legacy 2-arg
constructor (timer=null) still works for the existing tests.

Production wiring (Task 11 autoload) passes a real Godot Timer.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 10: NetSession client snapshot RPCs (welcome + sync_player_list)

When a joiner's WebRTC connection completes, the host informs them of the current player list via a welcome RPC. Subsequent list changes broadcast via `sync_player_list`. Plan B's tests used `client.state = LOBBY` to bypass this; Plan C makes it real.

**Files:**
- Modify: `scripts/net/net_session.gd`
- Create: `tests/unit/test_net_session_snapshot.gd`

- [ ] **Step 1: Write tests**

`tests/unit/test_net_session_snapshot.gd`:
```gdscript
extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")

func _build_welcome_payload():
    var s = PlayerSlot.new()
    s.peer_id = 1; s.is_host = true; s.seat_index = 0; s.name = "Host"
    return {
        "code": "ABC234",
        "players": [s.to_dict()],
    }

func test_rpc_receive_welcome_populates_client_state():
    var t = FakeTransport.new()
    var sig = FakeSignalingClient.new()
    var sess = NetSession.new(t, sig)
    sess.join_session("ABC234")
    sig.emit_peer_id_assigned(2)  # so local_peer_id is set first
    sess.rpc_receive_welcome(_build_welcome_payload())
    assert_eq(sess.local_peer_id, 2)
    assert_eq(sess.code, "ABC234")
    assert_eq(sess.players.size(), 1)
    assert_true(sess.players[0].is_host)
    assert_eq(sess.state, NetSessionState.State.LOBBY)

func test_rpc_receive_welcome_emits_players_changed():
    var t = FakeTransport.new()
    var sig = FakeSignalingClient.new()
    var sess = NetSession.new(t, sig)
    sess.join_session("ABC234")
    sig.emit_peer_id_assigned(2)
    var fired = [false]
    sess.players_changed.connect(func(): fired[0] = true)
    sess.rpc_receive_welcome(_build_welcome_payload())
    assert_true(fired[0])

func test_rpc_sync_player_list_replaces_players():
    var t = FakeTransport.new()
    var sig = FakeSignalingClient.new()
    var sess = NetSession.new(t, sig)
    sess.join_session("ABC234")
    sig.emit_peer_id_assigned(2)
    sess.rpc_receive_welcome(_build_welcome_payload())
    var s2 = PlayerSlot.new()
    s2.peer_id = 2; s2.seat_index = 1; s2.name = "Maya"
    sess.rpc_sync_player_list([
        sess.players[0].to_dict(),
        s2.to_dict(),
    ])
    assert_eq(sess.players.size(), 2)
    assert_eq(sess.players[1].name, "Maya")

func test_host_emits_welcome_via_signal_on_peer_joined():
    var t = FakeTransport.new()
    var sig = FakeSignalingClient.new()
    var sess = NetSession.new(t, sig)
    sess.host_session()
    sig.emit_code_issued("ABC234")
    var welcomes := []
    sess.send_welcome_to.connect(func(target_peer, payload): welcomes.append([target_peer, payload]))
    t.emit_peer_joined(2)
    assert_eq(welcomes.size(), 1)
    assert_eq(welcomes[0][0], 2)
    assert_eq(welcomes[0][1].code, "ABC234")
    assert_eq(welcomes[0][1].players.size(), 2, "host + new joiner")
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/net/net_session.gd`:

Add signals near the others:
```gdscript
signal send_welcome_to(target_peer_id: int, payload: Dictionary)
signal sync_player_list_to_all(serialized_players: Array)
```

Add the RPC-equivalent methods (place after `receive_player_info`):
```gdscript
func rpc_receive_welcome(payload: Dictionary) -> void:
    if is_host:
        return  # Host doesn't receive welcomes.
    code = payload.get("code", "")
    var raw_players: Array = payload.get("players", [])
    players = []
    for d in raw_players:
        players.append(PlayerSlot.from_dict(d))
    _set_state(NetSessionState.State.LOBBY)
    players_changed.emit()

func rpc_sync_player_list(serialized_players: Array) -> void:
    players = []
    for d in serialized_players:
        players.append(PlayerSlot.from_dict(d))
    players_changed.emit()
```

Add the helper that bundles `players_changed` + host-only broadcast:
```gdscript
func _emit_player_list_changed() -> void:
    players_changed.emit()
    if is_host:
        sync_player_list_to_all.emit(_serialize_players())

func _serialize_players() -> Array:
    var out: Array = []
    for p in players:
        out.append(p.to_dict())
    return out
```

Update `_on_peer_joined` to emit welcome + use the helper:
```gdscript
func _on_peer_joined(peer_id: int) -> void:
    if not is_host:
        return
    if players.size() >= NetConfig.MAX_PLAYERS:
        return
    var slot = PlayerSlot.new()
    slot.peer_id = peer_id
    slot.seat_index = players.size()
    slot.connected = true
    slot.reconnect_token = _generate_token()
    players.append(slot)
    var welcome := {"code": code, "players": _serialize_players()}
    send_welcome_to.emit(peer_id, welcome)
    _emit_player_list_changed()
```

**Refactor:** replace every `players_changed.emit()` call in the rest of the file (in `receive_player_info`, `receive_set_ready`, `receive_set_color`, `kick`, `_on_peer_left`, `_on_peer_arriving`, `_on_grace_timeout`, `leave_session`) with `_emit_player_list_changed()`, EXCEPT inside `rpc_receive_welcome` and `rpc_sync_player_list` (which are the *receivers* of broadcasts and must not re-broadcast).

- [ ] **Step 4: Run, watch pass**

Expected: 89/89 pass (85 prior + 4 new).

- [ ] **Step 5: Commit**

```
feat(client): NetSession welcome + sync_player_list RPCs for client snapshot

Host emits send_welcome_to(target, payload) on peer_joined with the
current player list and session code. The autoload (Task 11) routes
this to a Godot RPC to the new joiner. Joiner's rpc_receive_welcome
populates state and transitions to LOBBY.

Host also emits sync_player_list_to_all on every list mutation, routed
to a broadcast RPC. _emit_player_list_changed helper centralizes both
emits; receiver-side RPCs do NOT re-emit (avoids broadcast loop).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 5: Autoload + integration test

### Task 11: `NetSessionMain` autoload

**Files:**
- Create: `scripts/net/net_session_main.gd`
- Modify: `project.godot`

- [ ] **Step 1: Implement the autoload**

`scripts/net/net_session_main.gd`:
```gdscript
# Autoload Node that bootstraps production NetSession with real
# SignalingClient, WebRTCTransport, and a Timer child. Exposed globally
# as `NetSessionMain`. Consumers access state via NetSessionMain.session.
extends Node

const _NetSession = preload("res://scripts/net/net_session.gd")
const _SignalingClient = preload("res://scripts/net/signaling_client.gd")
const _WebRTCTransport = preload("res://scripts/net/web_rtc_transport.gd")
const _NetConfig = preload("res://scripts/net/net_config.gd")

var session  # _NetSession
var _signaling  # _SignalingClient
var _transport  # _WebRTCTransport
var _timer: Timer

func _ready() -> void:
    _signaling = _SignalingClient.new()
    _transport = _WebRTCTransport.new()
    _timer = Timer.new()
    _timer.one_shot = true
    _timer.wait_time = _NetConfig.RECONNECT_GRACE_SEC
    add_child(_timer)

    session = _NetSession.new(_transport, _signaling, _timer)

    # SDP/ICE bridge.
    _signaling.signal_received.connect(_transport.feed_remote_signal)
    _transport.signal_to_send.connect(_signaling.send_signal)

    # Wire MultiplayerAPI so Godot RPCs work once peers connect.
    multiplayer.multiplayer_peer = _transport.get_multiplayer_peer()

    # Route NetSession's welcome / sync emissions to actual RPCs.
    session.send_welcome_to.connect(_send_welcome)
    session.sync_player_list_to_all.connect(_broadcast_player_list)

func _process(_delta: float) -> void:
    if _signaling != null:
        _signaling.pump()
    if _transport != null:
        _transport.pump()

func _send_welcome(target_peer_id: int, payload: Dictionary) -> void:
    rpc_id(target_peer_id, "_rpc_receive_welcome", payload)

func _broadcast_player_list(serialized_players: Array) -> void:
    rpc("_rpc_sync_player_list", serialized_players)

@rpc("any_peer", "reliable", "call_remote")
func _rpc_receive_welcome(payload: Dictionary) -> void:
    session.rpc_receive_welcome(payload)

@rpc("any_peer", "reliable", "call_remote")
func _rpc_sync_player_list(serialized_players: Array) -> void:
    session.rpc_sync_player_list(serialized_players)
```

- [ ] **Step 2: Register the autoload in `project.godot`**

Append (or merge into existing `[autoload]` section):
```
[autoload]

NetSessionMain="*res://scripts/net/net_session_main.gd"
```

The leading `*` makes the script callable as a singleton (Godot 4.6 syntax).

- [ ] **Step 3: Run unit tests to ensure no regression**

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
```

Expected: 89/89 pass. The autoload runs at boot but doesn't interfere with test instances of NetSession (which construct their own deps).

- [ ] **Step 4: Commit**

```
feat(client): NetSessionMain autoload + production wiring

Autoload Node bootstraps real SignalingClient, WebRTCTransport, and a
Timer child; constructs the inner NetSession with all three. Bridges
SignalingClient.signal_received ↔ WebRTCTransport.feed_remote_signal.
Wires MultiplayerAPI to the WebRTCMultiplayerPeer so RPCs work.

NetSession.send_welcome_to → rpc_id(_rpc_receive_welcome) to the joiner.
NetSession.sync_player_list_to_all → rpc(_rpc_sync_player_list) broadcast.

_process drains the signaling WebSocket and WebRTC peer once per frame.

Registered in project.godot as singleton NetSessionMain.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 12: Two-instance integration smoke test

End-to-end: two NetSession instances connect via a locally-running signaling server, complete WebRTC handshake, exchange welcome RPCs, both end up in LOBBY with 2 player slots.

**Files:**
- Create: `tests/integration/test_two_instance_handshake.gd`

**Prerequisite:** Plan A's signaling server running on `ws://localhost:8080`. Start with `cd server; node index.js`.

- [ ] **Step 1: Write the integration test**

`tests/integration/test_two_instance_handshake.gd`:
```gdscript
extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const SignalingClient = preload("res://scripts/net/signaling_client.gd")
const WebRTCTransport = preload("res://scripts/net/web_rtc_transport.gd")
const NetConfig = preload("res://scripts/net/net_config.gd")

const HANDSHAKE_BUDGET := 15.0  # seconds
const PUMP_INTERVAL_MS := 50

func _signaling_server_reachable() -> bool:
    var ws := WebSocketPeer.new()
    ws.connect_to_url(NetConfig.SIGNALING_URL)
    var deadline := Time.get_ticks_msec() + 1500
    while Time.get_ticks_msec() < deadline:
        ws.poll()
        var state := ws.get_ready_state()
        if state == WebSocketPeer.STATE_OPEN:
            ws.close()
            return true
        if state == WebSocketPeer.STATE_CLOSED:
            return false
        OS.delay_msec(30)
    ws.close()
    return false

func _build_session() -> Dictionary:
    var sig := SignalingClient.new()
    var tx := WebRTCTransport.new()
    var sess := NetSession.new(tx, sig)
    # Plan C autoload normally bridges SDP/ICE. In this in-test scenario
    # (no autoload), we wire it manually.
    sig.signal_received.connect(tx.feed_remote_signal)
    tx.signal_to_send.connect(sig.send_signal)
    return {"sig": sig, "tx": tx, "sess": sess}

func _pump(instances: Array) -> void:
    for inst in instances:
        inst.sig.pump()
        inst.tx.pump()

func _wait_until(condition: Callable, instances: Array, budget_sec: float) -> bool:
    var deadline := Time.get_ticks_msec() + int(budget_sec * 1000)
    while Time.get_ticks_msec() < deadline:
        _pump(instances)
        if condition.call():
            return true
        OS.delay_msec(PUMP_INTERVAL_MS)
    return false

func test_two_instance_handshake_completes_via_real_signaling():
    if not _signaling_server_reachable():
        pending("Signaling server not running on %s — start with 'cd server; node index.js' and re-run" % NetConfig.SIGNALING_URL)
        return

    var host = _build_session()
    var joiner = _build_session()

    # Manually wire welcome RPC since autoload isn't running.
    # In production, NetSessionMain's _send_welcome -> rpc_id to the joiner.
    # Here, when host emits send_welcome_to, we directly call joiner.sess.rpc_receive_welcome.
    host.sess.send_welcome_to.connect(func(_target, payload): joiner.sess.rpc_receive_welcome(payload))

    # Host starts.
    host.sess.host_session()
    var host_code := [""]
    host.sig.code_issued.connect(func(c): host_code[0] = c)

    var got_code := _wait_until(
        func() -> bool: return host_code[0] != "",
        [host, joiner],
        HANDSHAKE_BUDGET
    )
    assert_true(got_code, "host should receive a code")

    # Joiner joins.
    joiner.sess.join_session(host_code[0])

    # Wait for joiner to receive peer_id and complete WebRTC handshake;
    # then for host to fire peer_joined; then for welcome RPC to populate
    # joiner's player list to size 2.
    var ok := _wait_until(
        func() -> bool: return host.sess.players.size() == 2 and joiner.sess.players.size() == 2,
        [host, joiner],
        HANDSHAKE_BUDGET
    )
    assert_true(ok, "both instances should end with 2 player slots")
    assert_eq(joiner.sess.state, 1, "joiner in LOBBY state (NetSessionState.LOBBY=1)")
    assert_eq(joiner.sess.local_peer_id, 2, "joiner has peer_id 2 from signaling")

    host.sess.leave_session()
    joiner.sess.leave_session()
```

- [ ] **Step 2: Start signaling server in a separate terminal**

```
cd server
node index.js
```

Expected: `signaling server listening on :8080`.

- [ ] **Step 3: Run the integration test**

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/integration -gexit
```

Expected outcomes:
- **Green:** Test passes. Both instances end with 2 player slots, joiner in LOBBY with peer_id 2.
- **Yellow:** Signaling server unreachable. Start it and re-run.
- **Red:** Debug. Common causes:
  - WebRTC handshake stuck — verify SDP/ICE messages are flowing in both directions. Add temporary `print()` calls in `WebRTCTransport._on_sdp_created` and `WebRTCTransport.feed_remote_signal` to trace.
  - peer_joined never fires — check `WebRTCPeerConnection.STATE_CONNECTED` is being reached; STUN server may be unreachable.
  - Welcome RPC not delivered — verify the in-test bridge fires (the host's `send_welcome_to` connection above).
  - Timeout — raise `HANDSHAKE_BUDGET` or check the STUN reachability.

If after 3 rounds of debugging the test still fails, report BLOCKED with what was tried.

- [ ] **Step 4: Verify unit tests still pass**

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
```

Expected: 89/89 unit tests pass (no regression from any integration-debugging changes).

- [ ] **Step 5: Tag the milestone**

```
git tag godot-network-v0.1
```

- [ ] **Step 6: Commit**

```
test(client): integration handshake — two instances via real signaling

End-to-end: two NetSession instances (host + joiner) connect to a running
localhost:8080 signaling server, exchange SDP/ICE via real WebRTCMultiplayerPeer,
and both end up in LOBBY with 2 player slots once the welcome RPC routes
through. Joiner's local_peer_id is 2 (from signaling). Skips cleanly if
the signaling server is not reachable.

This is the first proof that all of SignalingClient, WebRTCTransport,
and NetSession compose correctly in production. Unit tests cover
protocol-level behavior; this test covers the full orchestration.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Done

When all checkboxes above are checked, Plan C's deliverables are complete:

1. Plan A's signaling server extended with the `joined` message; backward-compatible with existing clients (they'd just ignore it).
2. `SignalingClient` and `WebRTCTransport` honor Plan B's signal contracts. Production code works against the real signaling server and real WebRTC.
3. `NetSession` integrates with both via the `NetSessionMain` autoload. Real Timer wired for the 30 s grace timeout. Client welcome / sync_player_list RPCs replace Plan B's test-only direct state mutation.
4. 89 unit tests + 1 integration test pass headlessly.
5. Sub-project #1B's "headless networking" capability is fully working: two Godot instances host/join via the signaling server and exchange RPCs end-to-end.

**Next step:** Invoke `superpowers:writing-plans` again to produce Plan D — the lobby UI scenes (MainMenu, Lobby, PlaceholderMatch), CLI flags (`--host-locally`, `--join-code=`), and the spec §9.3 manual playtest checklist. Plan D consumes the `NetSessionMain` autoload from this plan.
