# Godot NetSession Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Godot 4.6 client-side core logic for the Risk Royal lobby: data classes (`PlayerSlot`, `MatchStart`), test doubles (`FakeTransport`, `FakeSignalingClient`), and `NetSession` autoload covering host/join, player list management, lobby actions (ready/color/kick), match start, and disconnect/pause/reconnect — all unit-tested via GUT against fakes, with no real network or UI.

**Architecture:** Layered. Data classes are plain refcounted resources. `NetSession` is the single source of truth, depending only on injected `Transport` and `SignalingClient` interfaces. Tests substitute the real implementations with fakes that emit the same signals. Real WebRTC and WebSocket are wired up in the next plan (Plan C); this plan validates all NetSession logic against well-controlled fakes.

**Tech Stack:** Godot 4.6 (desktop), GDScript, GUT (Godot Unit Test) addon. No real network. No UI. Headless `godot --headless ... gut_cmdln.gd` test runs.

**Parent spec:** [`docs/superpowers/specs/2026-05-10-networking-lobby-foundation-design.md`](../specs/2026-05-10-networking-lobby-foundation-design.md). All decisions trace back to spec §5 (architecture), §6 (components), §7 (data flow). The protocol contract the future SignalingClient will speak against is documented in [Plan A's protocol-additions table](2026-05-10-signaling-server.md) plus spec §6.1.

**Companion plan (future):** `2026-05-11-godot-lobby-ui-and-real-network.md` will be written after this plan is fully implemented. That plan wires `NetSession` to a real `SignalingClient` + `WebRTCTransport`, adds lobby UI scenes, and runs the spec §9.3 manual playtest checklist.

---

## File Structure

All paths are relative to the project root (`c:\Users\whann\Desktop\Games\RocketMan`).

```
addons/
  gut/                                 # installed in Task 1
scripts/
  data/
    player_slot.gd                     # Task 2: PlayerSlot data class
    match_start.gd                     # Task 3: MatchStart data class
    net_session_state.gd               # Task 4: state enum (separate file for testability)
  net/
    net_config.gd                      # Task 4: SIGNALING_URL, STUN_SERVERS constants
    transport_interface.gd             # Task 5: contract documented as a "virtual" base script
    signaling_client_interface.gd      # Task 5: same idea for signaling
    net_session.gd                     # Tasks 6-12: the brain
tests/
  fakes/
    fake_transport.gd                  # Task 5: emits same signals as real WebRTCTransport
    fake_signaling_client.gd           # Task 5: emits same signals as real SignalingClient
  unit/
    test_player_slot.gd                # Task 2
    test_match_start.gd                # Task 3
    test_net_session_state.gd          # Task 4
    test_net_session_host_join.gd      # Task 6
    test_net_session_players.gd        # Task 7
    test_net_session_actions.gd        # Task 8
    test_net_session_match_start.gd    # Task 9
    test_net_session_disconnect.gd     # Task 10
    test_net_session_reconnect.gd      # Task 11
    test_net_session_timeout.gd        # Task 12
project.godot                          # Task 1: enable GUT plugin
```

**Responsibility per file:**

- `player_slot.gd` / `match_start.gd` — pure data. `to_dict()` / `from_dict(d)` for RPC transport. No logic.
- `net_session_state.gd` — `enum State { IDLE, LOBBY, MATCH, PAUSED }`. Constants only.
- `net_config.gd` — `SIGNALING_URL`, `STUN_SERVERS`, `MAX_PLAYERS = 8`, `RECONNECT_GRACE_SEC = 30`. Constants only.
- `transport_interface.gd` / `signaling_client_interface.gd` — documentation of the signal contract. The fakes and the future real implementations both honor this contract. No runtime instantiation in this plan.
- `fake_transport.gd` / `fake_signaling_client.gd` — minimal stubs that emit signals when their test helper methods are called. Used by every `test_net_session_*.gd` file.
- `net_session.gd` — the autoload. Grows across Tasks 6–12, each task adding one capability.

## Conventions

- **TDD strictly:** failing test → run and watch it fail → minimum implementation → run and watch it pass → commit. Same discipline as Plan A.
- **Commit prefixes:** `feat(client):`, `test(client):`, `chore(client):`, `docs(client):`, `refactor(client):`. The `(client)` scope distinguishes from Plan A's `(server)` commits.
- **No real network in this plan.** Everything tests through fakes. Real `WebRTCMultiplayerPeer` and `WebSocketPeer` are Plan C.
- **No `class_name` global registration** for these scripts during this plan. Use `preload()` in tests and consumers. Once Plan C ships the autoload registration, the public types can be exposed via `class_name`. Avoids global namespace pollution while we're churning interfaces.
- **GUT command line:** All tests run via
  ```
  godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
  ```
- **Co-author footer** on every commit:
  ```
  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  ```
- **Godot path notation:** Godot likes forward slashes even on Windows in `res://` paths and `tres`/`tscn` files. Use `res://scripts/data/player_slot.gd`, not backslashes.

## Protocol contract the future SignalingClient will speak (for reference only)

Plan B doesn't talk to a real signaling server, but `FakeSignalingClient` mimics the same surface. The contract Plan C will implement:

- **Outgoing from client:** `{type:"host"}`, `{type:"join", code, reconnect_token?}`, `{type:"signal", to, payload}`, `{type:"connected", peerId?}`, `{type:"start_match"}`.
- **Incoming to client:** `{type:"code", code}`, `{type:"joiner", joinerId, reconnect_token?}`, `{type:"signal", from, payload}`, `{type:"joiner_left", joinerId}`, `{type:"host_left"}`, `{type:"match_started"}`, `{type:"error", reason}`.

In Plan B, `FakeSignalingClient` exposes test helpers like `emit_code(code)`, `emit_joiner_arrival(id)`, `emit_host_left()` so tests drive these events directly.

---

## Phase 1: Tooling & Data Classes

### Task 1: Install GUT and enable the plugin

GUT (Godot Unit Test) is the de facto testing framework for Godot. We commit it under `addons/gut/` like any other addon.

**Files:**
- Create: `addons/gut/` (downloaded from GitHub release)
- Modify: `project.godot` (add `gut` to enabled plugins)
- Create: `tests/unit/test_smoke.gd`

- [ ] **Step 1: Download GUT 9.x release**

From the project root, in PowerShell:
```powershell
$url = 'https://github.com/bitwes/Gut/archive/refs/tags/v9.4.0.zip'
$tmp = 'gut.zip'
Invoke-WebRequest -Uri $url -OutFile $tmp
Expand-Archive -Path $tmp -DestinationPath . -Force
Move-Item -Path "Gut-9.4.0\addons\gut" -Destination "addons\gut" -Force
Remove-Item -Recurse -Force "Gut-9.4.0"
Remove-Item $tmp
```

If a different stable v9.x is available, use it; the public CLI API has been stable across v9.x.

- [ ] **Step 2: Enable GUT plugin in `project.godot`**

Open `project.godot` in a text editor. Add (or append to) an `[editor_plugins]` section:
```
[editor_plugins]
enabled=PackedStringArray("res://addons/gut/plugin.cfg")
```

If `[editor_plugins]` already exists (from the `godot_ai` addon), merge by adding GUT's plugin.cfg to the existing `PackedStringArray`. Typical result:
```
enabled=PackedStringArray("res://addons/godot_ai/plugin.cfg", "res://addons/gut/plugin.cfg")
```

- [ ] **Step 3: Create a smoke test**

`tests/unit/test_smoke.gd`:
```gdscript
extends GutTest

func test_two_plus_two():
    assert_eq(2 + 2, 4, "math broken")
```

- [ ] **Step 4: Run the smoke test from the command line**

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
```

Expected output near the end:
```
Tests              1
Passing            1
Failing            0
```

If the binary isn't on PATH, use the full path (e.g., `"C:\Program Files\Godot\Godot_v4.6-stable_win64.exe"`).

- [ ] **Step 5: Commit**

```powershell
git add addons/gut project.godot tests/unit/test_smoke.gd
git commit -m @'
chore(client): install GUT 9.x testing framework

Adds the addon under addons/gut/ (committed alongside godot_ai), enables it
via project.godot's editor_plugins list, and verifies a smoke test runs
headless via gut_cmdln.gd. All Plan B tests will hang off this runner.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
```

---

### Task 2: `PlayerSlot` data class

**Files:**
- Create: `scripts/data/player_slot.gd`
- Create: `tests/unit/test_player_slot.gd`

The slot is plain data: `peer_id`, `name`, `color_index`, `ready`, `is_host`, `connected`, `seat_index`, `reconnect_token`. Plus `to_dict()` / `from_dict(d)` for RPC marshalling.

- [ ] **Step 1: Write the failing test**

`tests/unit/test_player_slot.gd`:
```gdscript
extends GutTest

const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func test_defaults():
    var s = PlayerSlot.new()
    assert_eq(s.peer_id, 0)
    assert_eq(s.name, "")
    assert_eq(s.color_index, -1)
    assert_false(s.ready)
    assert_false(s.is_host)
    assert_true(s.connected)
    assert_eq(s.seat_index, -1)
    assert_eq(s.reconnect_token, "")

func test_to_dict_round_trip():
    var s = PlayerSlot.new()
    s.peer_id = 2
    s.name = "Maya"
    s.color_index = 3
    s.ready = true
    s.is_host = false
    s.connected = true
    s.seat_index = 1
    s.reconnect_token = "abc123"
    var d = s.to_dict()
    assert_eq(d.peer_id, 2)
    var s2 = PlayerSlot.from_dict(d)
    assert_eq(s2.peer_id, 2)
    assert_eq(s2.name, "Maya")
    assert_eq(s2.color_index, 3)
    assert_true(s2.ready)
    assert_eq(s2.seat_index, 1)
    assert_eq(s2.reconnect_token, "abc123")

func test_from_dict_handles_missing_fields():
    var s = PlayerSlot.from_dict({ "peer_id": 5, "name": "Solo" })
    assert_eq(s.peer_id, 5)
    assert_eq(s.name, "Solo")
    # Unspecified fields fall back to defaults.
    assert_eq(s.color_index, -1)
    assert_false(s.ready)
```

- [ ] **Step 2: Run, watch fail**

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
```

Expected: `test_player_slot.gd` errors with "could not preload" or similar.

- [ ] **Step 3: Implement**

`scripts/data/player_slot.gd`:
```gdscript
extends RefCounted

var peer_id: int = 0
var name: String = ""
var color_index: int = -1
var ready: bool = false
var is_host: bool = false
var connected: bool = true
var seat_index: int = -1
var reconnect_token: String = ""

func to_dict() -> Dictionary:
    return {
        "peer_id": peer_id,
        "name": name,
        "color_index": color_index,
        "ready": ready,
        "is_host": is_host,
        "connected": connected,
        "seat_index": seat_index,
        "reconnect_token": reconnect_token,
    }

static func from_dict(d: Dictionary) -> RefCounted:
    var s = load("res://scripts/data/player_slot.gd").new()
    s.peer_id = d.get("peer_id", 0)
    s.name = d.get("name", "")
    s.color_index = d.get("color_index", -1)
    s.ready = d.get("ready", false)
    s.is_host = d.get("is_host", false)
    s.connected = d.get("connected", true)
    s.seat_index = d.get("seat_index", -1)
    s.reconnect_token = d.get("reconnect_token", "")
    return s
```

Note: `static func from_dict` returns `RefCounted` (the base class of this script) rather than the specific class because GDScript can't self-reference inside a static method without `class_name`, which this plan deliberately avoids. Callers preload the script and treat the return as a `PlayerSlot`-shaped object. The `load(...)` lookup is cached.

- [ ] **Step 4: Run, watch pass**

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
```

Expected: 4 tests pass total (1 smoke + 3 PlayerSlot).

- [ ] **Step 5: Commit**

```powershell
git add scripts/data/player_slot.gd tests/unit/test_player_slot.gd
git commit -m @'
feat(client): add PlayerSlot data class

Pure refcounted data with to_dict / from_dict for RPC marshalling.
Fields: peer_id, name, color_index, ready, is_host, connected,
seat_index, reconnect_token. from_dict tolerates missing fields by
falling back to defaults.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
```

---

### Task 3: `MatchStart` data class

**Files:**
- Create: `scripts/data/match_start.gd`
- Create: `tests/unit/test_match_start.gd`

`MatchStart` is the handoff payload from lobby → match scene. Fields: `seats: Array[PlayerSlot]`, `host_peer_id: int`, `rng_seed: int`, `mode: String`, `rules: Dictionary`.

- [ ] **Step 1: Write the failing test**

`tests/unit/test_match_start.gd`:
```gdscript
extends GutTest

const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_seat(peer_id: int, name: String, seat: int) -> Object:
    var s = PlayerSlot.new()
    s.peer_id = peer_id
    s.name = name
    s.seat_index = seat
    return s

func test_defaults():
    var m = MatchStart.new()
    assert_eq(m.seats.size(), 0)
    assert_eq(m.host_peer_id, 0)
    assert_eq(m.rng_seed, 0)
    assert_eq(m.mode, "quick_clash")
    assert_eq(m.rules, {})

func test_to_dict_round_trip():
    var m = MatchStart.new()
    m.seats = [_build_seat(1, "Host", 0), _build_seat(2, "Joiner", 1)]
    m.host_peer_id = 1
    m.rng_seed = 0xDEADBEEF
    m.mode = "quick_clash"
    m.rules = { "no_sabotage": true }

    var d = m.to_dict()
    assert_eq(d.host_peer_id, 1)
    assert_eq(d.rng_seed, 0xDEADBEEF)
    assert_eq(d.seats.size(), 2)
    assert_eq(d.seats[0].name, "Host")

    var m2 = MatchStart.from_dict(d)
    assert_eq(m2.host_peer_id, 1)
    assert_eq(m2.rng_seed, 0xDEADBEEF)
    assert_eq(m2.seats.size(), 2)
    assert_eq(m2.seats[1].name, "Joiner")
    assert_eq(m2.rules, { "no_sabotage": true })
```

- [ ] **Step 2: Run, watch fail**

Run gut. Expected: preload failure for match_start.gd.

- [ ] **Step 3: Implement**

`scripts/data/match_start.gd`:
```gdscript
extends RefCounted

const PlayerSlot = preload("res://scripts/data/player_slot.gd")

var seats: Array = []
var host_peer_id: int = 0
var rng_seed: int = 0
var mode: String = "quick_clash"
var rules: Dictionary = {}

func to_dict() -> Dictionary:
    var seat_dicts: Array = []
    for s in seats:
        seat_dicts.append(s.to_dict())
    return {
        "seats": seat_dicts,
        "host_peer_id": host_peer_id,
        "rng_seed": rng_seed,
        "mode": mode,
        "rules": rules,
    }

static func from_dict(d: Dictionary) -> RefCounted:
    var m = load("res://scripts/data/match_start.gd").new()
    var raw_seats: Array = d.get("seats", [])
    m.seats = []
    for seat_dict in raw_seats:
        m.seats.append(PlayerSlot.from_dict(seat_dict))
    m.host_peer_id = d.get("host_peer_id", 0)
    m.rng_seed = d.get("rng_seed", 0)
    m.mode = d.get("mode", "quick_clash")
    m.rules = d.get("rules", {})
    return m
```

- [ ] **Step 4: Run, watch pass**

Expected: 6 tests pass total (1 smoke + 3 PlayerSlot + 2 MatchStart).

- [ ] **Step 5: Commit**

```powershell
git add scripts/data/match_start.gd tests/unit/test_match_start.gd
git commit -m @'
feat(client): add MatchStart data class

Handoff payload from lobby to match scene. Composes Array[PlayerSlot]
plus host_peer_id, rng_seed, mode, rules. to_dict / from_dict round-trip
through nested PlayerSlot serialization. Default mode is quick_clash;
rules defaults to empty dict so the Plan-C-onwards match scenes can
populate it without breaking compatibility.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
```

---

### Task 4: `NetSessionState` enum + `NetConfig` constants

**Files:**
- Create: `scripts/data/net_session_state.gd`
- Create: `scripts/net/net_config.gd`
- Create: `tests/unit/test_net_session_state.gd`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_net_session_state.gd`:
```gdscript
extends GutTest

const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const NetConfig = preload("res://scripts/net/net_config.gd")

func test_state_enum_values():
    assert_eq(NetSessionState.State.IDLE, 0)
    assert_eq(NetSessionState.State.LOBBY, 1)
    assert_eq(NetSessionState.State.MATCH, 2)
    assert_eq(NetSessionState.State.PAUSED, 3)

func test_net_config_constants():
    assert_eq(NetConfig.MAX_PLAYERS, 8)
    assert_eq(NetConfig.RECONNECT_GRACE_SEC, 30)
    assert_eq(NetConfig.SIGNALING_URL, "ws://localhost:8080")
    assert_eq(NetConfig.STUN_SERVERS, ["stun:stun.l.google.com:19302"])
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

`scripts/data/net_session_state.gd`:
```gdscript
extends Object

enum State {
    IDLE,
    LOBBY,
    MATCH,
    PAUSED,
}
```

`scripts/net/net_config.gd`:
```gdscript
extends Object

const SIGNALING_URL := "ws://localhost:8080"
const STUN_SERVERS: Array = ["stun:stun.l.google.com:19302"]
const MAX_PLAYERS := 8
const RECONNECT_GRACE_SEC := 30
```

- [ ] **Step 4: Run, watch pass**

Expected: 8 tests pass.

- [ ] **Step 5: Commit**

```powershell
git add scripts/data/net_session_state.gd scripts/net/net_config.gd tests/unit/test_net_session_state.gd
git commit -m @'
feat(client): add NetSession state enum and NetConfig constants

State enum: IDLE, LOBBY, MATCH, PAUSED (matches spec section 6.4).
NetConfig: SIGNALING_URL (localhost dev default), STUN_SERVERS for ICE,
MAX_PLAYERS=8, RECONNECT_GRACE_SEC=30. Single source of truth for
network configuration; Plan C will override SIGNALING_URL for production.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
```

---

## Phase 2: Test Doubles

### Task 5: `FakeTransport` and `FakeSignalingClient`

Both fakes implement the same signal contract that the real implementations will. NetSession will be wired to these in all unit tests; production code (Plan C) will wire to the real ones.

**Files:**
- Create: `scripts/net/transport_interface.gd`
- Create: `scripts/net/signaling_client_interface.gd`
- Create: `tests/fakes/fake_transport.gd`
- Create: `tests/fakes/fake_signaling_client.gd`

No tests of the fakes themselves — they're test scaffolding.

- [ ] **Step 1: Document the interfaces**

`scripts/net/transport_interface.gd`:
```gdscript
# Documents the signal contract for any Transport implementation.
# Real WebRTCTransport (Plan C) and FakeTransport (tests) both honor this.
#
# Signals:
#   peer_joined(id: int)
#   peer_left(id: int)
#   transport_failed(reason: String)
#
# Methods:
#   start_host() -> void
#   start_client() -> void
#   add_peer(joiner_id: int) -> void
#   close() -> void
#
# Not extended at runtime; serves as living documentation.
extends Object
```

`scripts/net/signaling_client_interface.gd`:
```gdscript
# Documents the signal contract for any SignalingClient implementation.
# Real SignalingClient (Plan C) and FakeSignalingClient (tests) both honor this.
#
# Signals:
#   code_issued(code: String)
#   peer_arriving(joiner_id: int, reconnect_token: String)
#   match_started_ack()
#   host_left()
#   joiner_left(joiner_id: int)
#   signaling_error(reason: String)
#
# Methods:
#   request_code() -> void
#   connect_to_code(code: String, reconnect_token: String) -> void
#   send_signal(to: int, payload: Dictionary) -> void
#   notify_connected(peer_id: int) -> void
#   send_start_match() -> void
#   close() -> void
#
# Not extended at runtime; serves as living documentation.
extends Object
```

- [ ] **Step 2: Implement FakeTransport**

`tests/fakes/fake_transport.gd`:
```gdscript
# Test double for the future WebRTCTransport.
# Tests drive it by calling emit_* helpers directly.
extends RefCounted

signal peer_joined(id: int)
signal peer_left(id: int)
signal transport_failed(reason: String)

var is_hosting: bool = false
var add_peer_calls: Array = []
var closed: bool = false

func start_host() -> void:
    is_hosting = true

func start_client() -> void:
    is_hosting = false

func add_peer(joiner_id: int) -> void:
    add_peer_calls.append(joiner_id)

func close() -> void:
    closed = true

# --- test helpers ---

func emit_peer_joined(id: int) -> void:
    peer_joined.emit(id)

func emit_peer_left(id: int) -> void:
    peer_left.emit(id)

func emit_transport_failed(reason: String) -> void:
    transport_failed.emit(reason)
```

- [ ] **Step 3: Implement FakeSignalingClient**

`tests/fakes/fake_signaling_client.gd`:
```gdscript
# Test double for the future SignalingClient.
# Tests drive it by calling emit_* helpers directly.
extends RefCounted

signal code_issued(code: String)
signal peer_arriving(joiner_id: int, reconnect_token: String)
signal match_started_ack()
signal host_left()
signal joiner_left(joiner_id: int)
signal signaling_error(reason: String)

var request_code_calls: int = 0
var connect_to_code_calls: Array = []
var send_signal_calls: Array = []
var notify_connected_calls: Array = []
var send_start_match_calls: int = 0
var closed: bool = false

func request_code() -> void:
    request_code_calls += 1

func connect_to_code(code: String, reconnect_token: String = "") -> void:
    connect_to_code_calls.append({"code": code, "reconnect_token": reconnect_token})

func send_signal(to: int, payload: Dictionary) -> void:
    send_signal_calls.append({"to": to, "payload": payload})

func notify_connected(peer_id: int = 0) -> void:
    notify_connected_calls.append(peer_id)

func send_start_match() -> void:
    send_start_match_calls += 1

func close() -> void:
    closed = true

# --- test helpers ---

func emit_code_issued(code: String) -> void:
    code_issued.emit(code)

func emit_peer_arriving(joiner_id: int, reconnect_token: String = "") -> void:
    peer_arriving.emit(joiner_id, reconnect_token)

func emit_match_started_ack() -> void:
    match_started_ack.emit()

func emit_host_left() -> void:
    host_left.emit()

func emit_joiner_left(joiner_id: int) -> void:
    joiner_left.emit(joiner_id)

func emit_signaling_error(reason: String) -> void:
    signaling_error.emit(reason)
```

- [ ] **Step 4: Verify GUT still runs cleanly (no new tests, but no parse errors)**

Run gut. Expected: 8 tests pass, no parse failures.

- [ ] **Step 5: Commit**

```powershell
git add scripts/net/transport_interface.gd scripts/net/signaling_client_interface.gd tests/fakes/
git commit -m @'
test(client): add transport and signaling test doubles

FakeTransport and FakeSignalingClient honor the same signal contract as
the future real implementations, exposing test helpers (emit_* methods)
to drive NetSession's reactions deterministically. Interface files
document the contract for both the fakes and Plan C's real classes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
```

---

## Phase 3: NetSession (the brain)

`NetSession` will grow across Tasks 6–12. Each task adds one capability with its own test file. The constructor takes injected dependencies so tests can substitute fakes:

```gdscript
NetSession.new(transport, signaling_client)
```

In production (Plan C), the autoload wraps real implementations. In tests, fakes are passed directly.

### Task 6: NetSession skeleton — host/join/leave

**Files:**
- Create: `scripts/net/net_session.gd`
- Create: `tests/unit/test_net_session_host_join.gd`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_net_session_host_join.gd`:
```gdscript
extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")

var transport
var signaling
var session

func before_each():
    transport = FakeTransport.new()
    signaling = FakeSignalingClient.new()
    session = NetSession.new(transport, signaling)

func test_initial_state():
    assert_eq(session.state, NetSessionState.State.IDLE)
    assert_false(session.is_host)
    assert_eq(session.local_peer_id, 0)
    assert_eq(session.players.size(), 0)
    assert_eq(session.code, "")

func test_host_session_requests_code_and_starts_transport():
    session.host_session()
    assert_eq(signaling.request_code_calls, 1)
    assert_true(transport.is_hosting)
    assert_true(session.is_host)
    assert_eq(session.state, NetSessionState.State.IDLE,
        "stays idle until code issued")

func test_code_issued_moves_to_lobby_and_creates_host_slot():
    session.host_session()
    signaling.emit_code_issued("ABC234")
    assert_eq(session.state, NetSessionState.State.LOBBY)
    assert_eq(session.code, "ABC234")
    assert_eq(session.local_peer_id, 1)
    assert_eq(session.players.size(), 1)
    assert_true(session.players[0].is_host)
    assert_eq(session.players[0].peer_id, 1)
    assert_eq(session.players[0].seat_index, 0)

func test_join_session_connects_to_code():
    session.join_session("ABC234")
    assert_eq(signaling.connect_to_code_calls.size(), 1)
    assert_eq(signaling.connect_to_code_calls[0].code, "ABC234")
    assert_false(session.is_host)

func test_leave_session_closes_transport_and_signaling():
    session.host_session()
    signaling.emit_code_issued("ABC234")
    session.leave_session()
    assert_true(transport.closed)
    assert_true(signaling.closed)
    assert_eq(session.state, NetSessionState.State.IDLE)
    assert_eq(session.players.size(), 0)
    assert_eq(session.code, "")
```

- [ ] **Step 2: Run, watch fail**

Expected: preload failure for `net_session.gd`.

- [ ] **Step 3: Implement minimum**

`scripts/net/net_session.gd`:
```gdscript
extends RefCounted

const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

signal players_changed()
signal state_changed(new_state: int)
signal session_ended(reason: String)

var _transport
var _signaling
var state: int = NetSessionState.State.IDLE
var is_host: bool = false
var local_peer_id: int = 0
var code: String = ""
var players: Array = []

func _init(transport, signaling_client):
    _transport = transport
    _signaling = signaling_client
    _connect_signals()

func _connect_signals() -> void:
    _signaling.code_issued.connect(_on_code_issued)

func host_session() -> void:
    is_host = true
    local_peer_id = 1
    _transport.start_host()
    _signaling.request_code()

func join_session(code_input: String) -> void:
    is_host = false
    _transport.start_client()
    _signaling.connect_to_code(code_input)

func leave_session() -> void:
    _transport.close()
    _signaling.close()
    players = []
    code = ""
    is_host = false
    local_peer_id = 0
    _set_state(NetSessionState.State.IDLE)

func _on_code_issued(new_code: String) -> void:
    code = new_code
    var host_slot = PlayerSlot.new()
    host_slot.peer_id = 1
    host_slot.is_host = true
    host_slot.seat_index = 0
    players = [host_slot]
    _set_state(NetSessionState.State.LOBBY)
    players_changed.emit()

func _set_state(new_state: int) -> void:
    if state == new_state:
        return
    state = new_state
    state_changed.emit(state)
```

- [ ] **Step 4: Run, watch pass**

Expected: 13 tests pass (8 prior + 5 new).

- [ ] **Step 5: Commit**

```powershell
git add scripts/net/net_session.gd tests/unit/test_net_session_host_join.gd
git commit -m @'
feat(client): NetSession host/join/leave skeleton

State transitions IDLE -> LOBBY on host_session+code_issued; IDLE on
leave_session. host_session requests a code from signaling and starts
the host transport. join_session connects to a code. local_peer_id is 1
for the host; joiners assigned in later tasks. Host slot auto-populated
at seat 0 on code issuance. Dependencies (transport, signaling) injected
via constructor; production wiring is Plan C.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
```

---

### Task 7: NetSession player list management

This task handles peer joins: a new peer arrives via transport's `peer_joined` signal, gets a provisional `PlayerSlot`, then submits name+color via the (simulated) RPC path. Host validates and broadcasts.

For Plan B, the "RPC" is a direct method call on `NetSession` (`receive_player_info(peer_id, name, color)`). Plan C will wire this to actual Godot RPC. The fake test setup calls it directly.

**Files:**
- Modify: `scripts/net/net_session.gd`
- Create: `tests/unit/test_net_session_players.gd`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_net_session_players.gd`:
```gdscript
extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")

var transport
var signaling
var session

func before_each():
    transport = FakeTransport.new()
    signaling = FakeSignalingClient.new()
    session = NetSession.new(transport, signaling)
    session.host_session()
    signaling.emit_code_issued("ABC234")

func _find_slot(peer_id: int):
    for s in session.players:
        if s.peer_id == peer_id:
            return s
    return null

func test_peer_join_creates_provisional_slot():
    transport.emit_peer_joined(2)
    assert_eq(session.players.size(), 2)
    var s = _find_slot(2)
    assert_not_null(s)
    assert_eq(s.name, "")
    assert_eq(s.color_index, -1)
    assert_eq(s.seat_index, 1)
    assert_true(s.connected)
    assert_false(s.is_host)
    assert_ne(s.reconnect_token, "", "host issues a reconnect token")

func test_receive_player_info_updates_slot():
    transport.emit_peer_joined(2)
    session.receive_player_info(2, "Maya", 3)
    var s = _find_slot(2)
    assert_eq(s.name, "Maya")
    assert_eq(s.color_index, 3)

func test_receive_player_info_rejects_duplicate_color():
    transport.emit_peer_joined(2)
    transport.emit_peer_joined(3)
    var ok1 = session.receive_player_info(2, "Maya", 3)
    var ok2 = session.receive_player_info(3, "Sam", 3)
    assert_true(ok1)
    assert_false(ok2)
    assert_eq(_find_slot(3).color_index, -1, "rejected slot keeps default")

func test_receive_player_info_rejects_unknown_peer():
    var ok = session.receive_player_info(99, "Ghost", 1)
    assert_false(ok)

func test_receive_player_info_truncates_long_name():
    transport.emit_peer_joined(2)
    var long_name = "x".repeat(50)
    session.receive_player_info(2, long_name, 1)
    var s = _find_slot(2)
    assert_eq(s.name.length(), 16)

func test_receive_player_info_replaces_empty_name():
    transport.emit_peer_joined(2)
    session.receive_player_info(2, "", 1)
    var s = _find_slot(2)
    assert_eq(s.name, "Player 2")

func test_peer_join_emits_players_changed():
    var emitted = []
    session.players_changed.connect(func(): emitted.append(true))
    transport.emit_peer_joined(2)
    assert_eq(emitted.size(), 1)
```

- [ ] **Step 2: Run, watch fail**

Expected: tests fail (no `peer_joined` handler, no `receive_player_info`, no reconnect_token assignment).

- [ ] **Step 3: Implement**

In `scripts/net/net_session.gd`, add to `_connect_signals()`:
```gdscript
_transport.peer_joined.connect(_on_peer_joined)
```

Add methods:
```gdscript
const NetConfig = preload("res://scripts/net/net_config.gd")

func _on_peer_joined(peer_id: int) -> void:
    if not is_host:
        return  # joiners see peer events too but the host owns the list
    var slot = PlayerSlot.new()
    slot.peer_id = peer_id
    slot.seat_index = players.size()
    slot.connected = true
    slot.reconnect_token = _generate_token()
    players.append(slot)
    players_changed.emit()

func receive_player_info(peer_id: int, name: String, color_index: int) -> bool:
    var slot = _find_slot(peer_id)
    if slot == null:
        return false
    # validate color collision (skip the requesting slot itself if it had one)
    for other in players:
        if other.peer_id != peer_id and other.color_index == color_index and color_index >= 0:
            return false
    var normalized = _normalize_name(name, slot.seat_index + 1)
    slot.name = normalized
    slot.color_index = color_index
    players_changed.emit()
    return true

func _find_slot(peer_id: int):
    for s in players:
        if s.peer_id == peer_id:
            return s
    return null

func _normalize_name(name: String, fallback_index: int) -> String:
    var trimmed = name.strip_edges().substr(0, 16)
    if trimmed.is_empty():
        return "Player %d" % fallback_index
    return trimmed

func _generate_token() -> String:
    return "%016x" % [randi() | (randi() << 32)]
```

- [ ] **Step 4: Run, watch pass**

Expected: 20 tests pass (13 prior + 7 new).

- [ ] **Step 5: Commit**

```powershell
git add scripts/net/net_session.gd tests/unit/test_net_session_players.gd
git commit -m @'
feat(client): NetSession peer_joined handling and receive_player_info

On peer_joined, host creates a provisional PlayerSlot with a random
reconnect_token and the next seat_index. receive_player_info validates
unique color and normalizes name (16-char max, empty -> "Player N").
Returns bool indicating accept/reject; in Plan C the host RPC layer
will use the return value to either rebroadcast or notify the requester
to revert.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
```

---

### Task 8: NetSession lobby actions — set_ready, set_color, kick

These are intent RPCs: a client (including the host) calls them, which routes to host validation and rebroadcast.

For Plan B, both sides are simulated in-process. Tests call `session.set_ready(true)` as the local user, then verify state. Where validation is host-side, we test through `session.receive_set_ready(peer_id, value)` (the simulated RPC arrival on the host) to verify acceptance/rejection logic.

**Files:**
- Modify: `scripts/net/net_session.gd`
- Create: `tests/unit/test_net_session_actions.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_net_session_actions.gd`:
```gdscript
extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")

var transport
var signaling
var session

func before_each():
    transport = FakeTransport.new()
    signaling = FakeSignalingClient.new()
    session = NetSession.new(transport, signaling)
    session.host_session()
    signaling.emit_code_issued("ABC234")
    transport.emit_peer_joined(2)
    transport.emit_peer_joined(3)

func _slot(peer_id: int):
    for s in session.players:
        if s.peer_id == peer_id:
            return s
    return null

func test_host_can_set_own_ready():
    var ok = session.receive_set_ready(1, true)
    assert_true(ok)
    assert_true(_slot(1).ready)

func test_set_ready_rejects_unknown_peer():
    var ok = session.receive_set_ready(99, true)
    assert_false(ok)

func test_set_ready_rejects_outside_lobby_state():
    session._set_state(NetSessionState.State.MATCH)
    var ok = session.receive_set_ready(1, true)
    assert_false(ok)

func test_set_color_changes_color():
    var ok = session.receive_set_color(2, 5)
    assert_true(ok)
    assert_eq(_slot(2).color_index, 5)

func test_set_color_rejects_duplicate():
    session.receive_set_color(2, 5)
    var ok = session.receive_set_color(3, 5)
    assert_false(ok)
    assert_eq(_slot(3).color_index, -1)

func test_kick_removes_slot_when_host_calls():
    var ok = session.kick(2)
    assert_true(ok)
    assert_null(_slot(2))

func test_kick_rejects_when_not_host():
    var joiner_session = NetSession.new(FakeTransport.new(), FakeSignalingClient.new())
    joiner_session.join_session("ABC234")
    var ok = joiner_session.kick(2)
    assert_false(ok)

func test_kick_calls_transport_disconnect():
    # In Plan C, kick will trigger transport.disconnect_peer(peer_id).
    # FakeTransport tracks any such call.
    session.kick(2)
    # For Plan B we just verify the slot is removed and player_changed emits;
    # the transport disconnect side-effect is wired up in Plan C.
    assert_null(_slot(2))

func test_actions_emit_players_changed():
    var emitted = 0
    session.players_changed.connect(func(): emitted += 1)
    session.receive_set_ready(2, true)
    session.receive_set_color(2, 5)
    session.kick(3)
    assert_eq(emitted, 3)
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/net/net_session.gd`, add:
```gdscript
func receive_set_ready(peer_id: int, value: bool) -> bool:
    if state != NetSessionState.State.LOBBY:
        return false
    var slot = _find_slot(peer_id)
    if slot == null:
        return false
    slot.ready = value
    players_changed.emit()
    return true

func receive_set_color(peer_id: int, color_index: int) -> bool:
    if state != NetSessionState.State.LOBBY:
        return false
    var slot = _find_slot(peer_id)
    if slot == null:
        return false
    for other in players:
        if other.peer_id != peer_id and other.color_index == color_index and color_index >= 0:
            return false
    slot.color_index = color_index
    players_changed.emit()
    return true

func kick(peer_id: int) -> bool:
    if not is_host:
        return false
    if state != NetSessionState.State.LOBBY:
        return false
    var slot = _find_slot(peer_id)
    if slot == null:
        return false
    players.erase(slot)
    # Reassign seat indices to remain contiguous.
    for i in players.size():
        players[i].seat_index = i
    players_changed.emit()
    return true
```

- [ ] **Step 4: Run, watch pass**

Expected: 29 tests pass (20 prior + 9 new).

- [ ] **Step 5: Commit**

```powershell
git add scripts/net/net_session.gd tests/unit/test_net_session_actions.gd
git commit -m @'
feat(client): NetSession lobby actions (set_ready, set_color, kick)

Host-side validators reject outside LOBBY state and unknown peers.
set_color rejects duplicate colors. kick is host-only, removes the slot
and renumbers seat indices contiguously. All actions emit players_changed
on accept; rejection returns false without mutation. Wire-up of the
actual RPC layer (set_ready/set_color called by joiners) is Plan C.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
```

---

### Task 9: NetSession `start_match`

**Files:**
- Modify: `scripts/net/net_session.gd`
- Create: `tests/unit/test_net_session_match_start.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_net_session_match_start.gd`:
```gdscript
extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")

var transport
var signaling
var session

func before_each():
    transport = FakeTransport.new()
    signaling = FakeSignalingClient.new()
    session = NetSession.new(transport, signaling)
    session.host_session()
    signaling.emit_code_issued("ABC234")
    transport.emit_peer_joined(2)
    session.receive_player_info(2, "Maya", 3)
    session.receive_set_ready(1, true)
    session.receive_set_ready(2, true)

func test_start_match_requires_host():
    var joiner = NetSession.new(FakeTransport.new(), FakeSignalingClient.new())
    joiner.join_session("ABC234")
    var ok = joiner.start_match()
    assert_false(ok)

func test_start_match_requires_min_two_players():
    var solo = NetSession.new(FakeTransport.new(), FakeSignalingClient.new())
    solo.host_session()
    solo._signaling.emit_code_issued("SOLOAA")
    solo.receive_set_ready(1, true)
    assert_false(solo.start_match())

func test_start_match_requires_all_ready():
    session.receive_set_ready(2, false)
    assert_false(session.start_match())

func test_start_match_emits_match_starting_with_correct_payload():
    var emitted_payloads = []
    session.match_starting.connect(func(ms): emitted_payloads.append(ms))
    var ok = session.start_match()
    assert_true(ok)
    assert_eq(emitted_payloads.size(), 1)
    var ms = emitted_payloads[0]
    assert_eq(ms.host_peer_id, 1)
    assert_eq(ms.seats.size(), 2)
    assert_ne(ms.rng_seed, 0, "seed should be non-zero (vanishingly unlikely to be 0)")
    assert_eq(ms.mode, "quick_clash")

func test_start_match_transitions_to_match_state():
    session.start_match()
    assert_eq(session.state, NetSessionState.State.MATCH)

func test_start_match_calls_signaling_send_start_match():
    session.start_match()
    assert_eq(signaling.send_start_match_calls, 1)
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/net/net_session.gd`, add the `match_starting` signal near the top:
```gdscript
signal match_starting(match_start)
```

And the method:
```gdscript
const MatchStart = preload("res://scripts/data/match_start.gd")

func start_match() -> bool:
    if not is_host:
        return false
    if state != NetSessionState.State.LOBBY:
        return false
    if players.size() < 2:
        return false
    for p in players:
        if not p.ready:
            return false

    var ms = MatchStart.new()
    ms.seats = players.duplicate()
    ms.host_peer_id = 1
    ms.rng_seed = randi() | (randi() << 32)
    ms.mode = "quick_clash"
    ms.rules = {}

    _signaling.send_start_match()
    _set_state(NetSessionState.State.MATCH)
    match_starting.emit(ms)
    return true
```

- [ ] **Step 4: Run, watch pass**

Expected: 35 tests pass (29 prior + 6 new).

- [ ] **Step 5: Commit**

```powershell
git add scripts/net/net_session.gd tests/unit/test_net_session_match_start.gd
git commit -m @'
feat(client): NetSession start_match builds MatchStart and emits signal

Host-only, requires LOBBY state, >= 2 players, and every player ready.
Builds MatchStart from current players plus a fresh 64-bit RNG seed;
notifies signaling server via send_start_match (locks the lobby for
in_progress filtering per Plan A protocol additions); transitions state
to MATCH; emits match_starting for the future scene-loader to consume.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
```

---

### Task 10: NetSession disconnect → pause

On `peer_left` from transport, mark the slot disconnected, save the current state into `pre_pause_state`, transition to PAUSED, and start a 30s timer. The timer firing leads to Task 12's resume-without-player behavior; this task only tests the pause-down transition.

**Files:**
- Modify: `scripts/net/net_session.gd`
- Create: `tests/unit/test_net_session_disconnect.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_net_session_disconnect.gd`:
```gdscript
extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")

var transport
var signaling
var session

func before_each():
    transport = FakeTransport.new()
    signaling = FakeSignalingClient.new()
    session = NetSession.new(transport, signaling)
    session.host_session()
    signaling.emit_code_issued("ABC234")
    transport.emit_peer_joined(2)

func _slot(peer_id: int):
    for s in session.players:
        if s.peer_id == peer_id:
            return s
    return null

func test_peer_left_marks_slot_disconnected():
    transport.emit_peer_left(2)
    var s = _slot(2)
    assert_not_null(s, "slot retained for grace period")
    assert_false(s.connected)

func test_peer_left_pauses_session_and_records_pre_pause_state():
    transport.emit_peer_left(2)
    assert_eq(session.state, NetSessionState.State.PAUSED)
    assert_eq(session.pre_pause_state, NetSessionState.State.LOBBY)

func test_peer_left_in_match_state_pauses_and_records():
    session._set_state(NetSessionState.State.MATCH)
    transport.emit_peer_left(2)
    assert_eq(session.state, NetSessionState.State.PAUSED)
    assert_eq(session.pre_pause_state, NetSessionState.State.MATCH)

func test_host_left_signal_pauses_clients():
    var client = NetSession.new(FakeTransport.new(), FakeSignalingClient.new())
    client.join_session("ABC234")
    # Simulate client's local state being post-handshake by manually setting fields.
    client.state = NetSessionState.State.LOBBY
    client._signaling.emit_host_left()
    assert_eq(client.state, NetSessionState.State.PAUSED)

func test_peer_left_emits_state_changed():
    var emitted = []
    session.state_changed.connect(func(s): emitted.append(s))
    transport.emit_peer_left(2)
    assert_true(emitted.has(NetSessionState.State.PAUSED))
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/net/net_session.gd`, add `pre_pause_state` property:
```gdscript
var pre_pause_state: int = NetSessionState.State.IDLE
```

Update `_connect_signals`:
```gdscript
_transport.peer_left.connect(_on_peer_left)
_signaling.host_left.connect(_on_host_left)
```

Add handlers:
```gdscript
func _on_peer_left(peer_id: int) -> void:
    var slot = _find_slot(peer_id)
    if slot != null:
        slot.connected = false
    if state != NetSessionState.State.PAUSED:
        pre_pause_state = state
        _set_state(NetSessionState.State.PAUSED)
    players_changed.emit()

func _on_host_left() -> void:
    if state == NetSessionState.State.IDLE:
        return
    pre_pause_state = state
    _set_state(NetSessionState.State.PAUSED)
```

- [ ] **Step 4: Run, watch pass**

Expected: 40 tests pass (35 prior + 5 new).

- [ ] **Step 5: Commit**

```powershell
git add scripts/net/net_session.gd tests/unit/test_net_session_disconnect.gd
git commit -m @'
feat(client): NetSession disconnect -> pause with pre_pause_state

Both peer_left (any side) and signaling host_left (client side) transition
the session to PAUSED, remembering the prior state for later resumption.
The disconnected peer's slot is marked connected=false but retained for
the grace period (Task 12 will remove on timeout). state_changed and
players_changed fire on the transition.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
```

---

### Task 11: NetSession reconnect-token matching

When a previously disconnected peer reappears via `peer_arriving(joiner_id, reconnect_token)`, the host matches the token to a slot whose `connected=false`. Match → update peer_id, set connected=true, transition state back to `pre_pause_state`. No match → it's a fresh joiner; falls through to normal join.

**Files:**
- Modify: `scripts/net/net_session.gd`
- Create: `tests/unit/test_net_session_reconnect.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_net_session_reconnect.gd`:
```gdscript
extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")

var transport
var signaling
var session

func before_each():
    transport = FakeTransport.new()
    signaling = FakeSignalingClient.new()
    session = NetSession.new(transport, signaling)
    session.host_session()
    signaling.emit_code_issued("ABC234")
    transport.emit_peer_joined(2)
    session.receive_player_info(2, "Maya", 3)

func _slot_by_peer(peer_id: int):
    for s in session.players:
        if s.peer_id == peer_id:
            return s
    return null

func test_reconnect_with_matching_token_restores_slot():
    var original_token = _slot_by_peer(2).reconnect_token
    var original_name = _slot_by_peer(2).name
    transport.emit_peer_left(2)
    assert_false(_slot_by_peer(2).connected)
    assert_eq(session.state, NetSessionState.State.PAUSED)

    # Reconnect with the token, new peer_id 4 from signaling
    signaling.emit_peer_arriving(4, original_token)

    # Slot is now under peer_id 4, retaining name/color
    assert_null(_slot_by_peer(2), "old peer_id should be gone")
    var restored = _slot_by_peer(4)
    assert_not_null(restored)
    assert_eq(restored.name, original_name)
    assert_eq(restored.color_index, 3)
    assert_true(restored.connected)
    assert_eq(session.state, NetSessionState.State.LOBBY,
        "back to pre_pause_state")

func test_reconnect_with_wrong_token_treated_as_new_join():
    transport.emit_peer_left(2)
    signaling.emit_peer_arriving(4, "wrong-token")
    # Not a reconnect — host should call transport.add_peer to begin SDP for a new join
    assert_eq(transport.add_peer_calls, [4])
    # Original slot is still in disconnected state
    assert_false(_slot_by_peer(2).connected)

func test_reconnect_when_no_disconnected_slots_is_normal_join():
    signaling.emit_peer_arriving(5, "abc")
    assert_eq(transport.add_peer_calls, [5])
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/net/net_session.gd`, update `_connect_signals()`:
```gdscript
_signaling.peer_arriving.connect(_on_peer_arriving)
```

Add handler:
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
            players_changed.emit()
            return
    # Not a recognized reconnect → normal new-join SDP path
    _transport.add_peer(joiner_id)

func _find_disconnected_by_token(token: String):
    for s in players:
        if not s.connected and s.reconnect_token == token:
            return s
    return null
```

- [ ] **Step 4: Run, watch pass**

Expected: 43 tests pass (40 prior + 3 new).

- [ ] **Step 5: Commit**

```powershell
git add scripts/net/net_session.gd tests/unit/test_net_session_reconnect.gd
git commit -m @'
feat(client): NetSession reconnect-token matching

When peer_arriving carries a token matching a disconnected slot, the host
updates the slot in place (new peer_id, mark connected, rotate the
reconnect_token to prevent replay) and resumes from pre_pause_state.
Unmatched token or no token -> normal new-join flow via transport.add_peer.
Downstream consumers should reference PlayerSlot objects or re-lookup via
players_changed, not cache raw peer_ids across PAUSED transitions
(matches the warning in spec section 7.5).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
```

---

### Task 12: NetSession 30s timeout → resume without player

When a peer disconnects, a 30-second timer starts. If the timer fires before reconnect, the slot is removed and the session resumes from `pre_pause_state`. If the disconnected player was the host (clients receive `host_left`), the timer firing transitions to IDLE with `session_ended("host_lost")`.

Plan B's tests inject a fake clock to drive the timer synchronously. The implementation uses a closure-injectable timer rather than a hard-coded `Timer` node so it's testable. In Plan C, we'll wire this to a real `Timer` node.

**Files:**
- Modify: `scripts/net/net_session.gd`
- Create: `tests/unit/test_net_session_timeout.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_net_session_timeout.gd`:
```gdscript
extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")

var transport
var signaling
var session

func before_each():
    transport = FakeTransport.new()
    signaling = FakeSignalingClient.new()
    session = NetSession.new(transport, signaling)
    session.host_session()
    signaling.emit_code_issued("ABC234")
    transport.emit_peer_joined(2)
    session.receive_player_info(2, "Maya", 3)

func _slot(peer_id: int):
    for s in session.players:
        if s.peer_id == peer_id:
            return s
    return null

func test_grace_timeout_removes_disconnected_slot_and_resumes():
    transport.emit_peer_left(2)
    assert_eq(session.state, NetSessionState.State.PAUSED)

    # Synchronously fire the grace timer
    session._on_grace_timeout()

    assert_null(_slot(2), "slot removed after timeout")
    assert_eq(session.state, NetSessionState.State.LOBBY)
    assert_eq(session.players.size(), 1)

func test_grace_timeout_with_no_disconnected_slots_is_noop():
    # If somehow the timer fires when nothing is disconnected, do nothing.
    var initial = session.players.size()
    session._on_grace_timeout()
    assert_eq(session.players.size(), initial)
    assert_eq(session.state, NetSessionState.State.LOBBY)

func test_grace_timeout_on_client_after_host_left_ends_session():
    var client = NetSession.new(FakeTransport.new(), FakeSignalingClient.new())
    client.join_session("ABC234")
    client.state = NetSessionState.State.LOBBY
    client._signaling.emit_host_left()
    assert_eq(client.state, NetSessionState.State.PAUSED)

    var ended_reasons = []
    client.session_ended.connect(func(r): ended_reasons.append(r))
    client._on_grace_timeout()

    assert_eq(client.state, NetSessionState.State.IDLE)
    assert_eq(ended_reasons, ["host_lost"])
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/net/net_session.gd`, add the timeout handler:
```gdscript
func _on_grace_timeout() -> void:
    if state != NetSessionState.State.PAUSED:
        return

    if is_host:
        # Remove disconnected slots and resume from pre_pause_state.
        var to_remove = []
        for s in players:
            if not s.connected:
                to_remove.append(s)
        if to_remove.is_empty():
            _set_state(pre_pause_state)
            return
        for s in to_remove:
            players.erase(s)
        for i in players.size():
            players[i].seat_index = i
        _set_state(pre_pause_state)
        players_changed.emit()
    else:
        # Client lost host -> end session.
        leave_session()
        session_ended.emit("host_lost")
```

Update `_on_peer_left` to schedule the timeout (in Plan B, we expose this as a method that tests call; Plan C will use a real Godot Timer). Add nothing else here; tests drive `_on_grace_timeout()` directly. In Plan C, `_on_peer_left` will start a 30s Timer that calls `_on_grace_timeout()` on `timeout`.

- [ ] **Step 4: Run, watch pass**

Expected: 46 tests pass (43 prior + 3 new).

- [ ] **Step 5: Commit**

```powershell
git add scripts/net/net_session.gd tests/unit/test_net_session_timeout.gd
git commit -m @'
feat(client): NetSession grace-period timeout resolution

_on_grace_timeout: on host side, remove any still-disconnected slots and
resume from pre_pause_state. On client side, fire session_ended("host_lost")
and reset to IDLE. Tests drive the handler synchronously; Plan C will wire
a real Timer to invoke it 30s after disconnect.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
```

---

## Phase 4: Verification

### Task 13: Full test run + coverage check

- [ ] **Step 1: Run the full test suite**

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
```

Expected: 46 tests pass, 0 fail. Run-time should be well under 5 seconds (no real I/O).

- [ ] **Step 2: Self-review the NetSession surface**

Open `scripts/net/net_session.gd` and verify every public method has at least one test:

| Method | Test file |
|---|---|
| `host_session()` | test_net_session_host_join.gd |
| `join_session(code)` | test_net_session_host_join.gd |
| `leave_session()` | test_net_session_host_join.gd |
| `receive_player_info(peer, name, color)` | test_net_session_players.gd |
| `receive_set_ready(peer, value)` | test_net_session_actions.gd |
| `receive_set_color(peer, color)` | test_net_session_actions.gd |
| `kick(peer)` | test_net_session_actions.gd |
| `start_match()` | test_net_session_match_start.gd |
| `_on_peer_left` (via transport.emit_peer_left) | test_net_session_disconnect.gd |
| `_on_host_left` (via signaling.emit_host_left) | test_net_session_disconnect.gd |
| `_on_peer_arriving` (via signaling.emit_peer_arriving) | test_net_session_reconnect.gd |
| `_on_grace_timeout()` | test_net_session_timeout.gd |

If anything is missing, add a test before commit.

- [ ] **Step 3: Tag the milestone**

```
git tag godot-netsession-v0.1
```

- [ ] **Step 4: Final commit (only if cleanup needed)**

Skip if nothing to commit.

---

## Done

When all checkboxes above are checked, this plan's deliverables are complete:

1. `scripts/data/` and `scripts/net/` modules implement the NetSession layer of the design.
2. 46 GUT unit tests cover every public behavior using fakes (no real network).
3. Headless `godot --headless ... gut_cmdln.gd` runs all tests in seconds.
4. The codebase is ready for Plan C to add: real `SignalingClient` (WebSocket against the running signaling server), real `WebRTCTransport`, lobby UI scenes, and the manual playtest checklist.

**Next step:** Invoke `superpowers:writing-plans` again to produce `2026-05-11-godot-lobby-ui-and-real-network.md`, which consumes NetSession's interface as-is and wires it to real Godot networking + UI.
