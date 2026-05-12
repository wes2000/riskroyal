# Match Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the headless logic layer of sub-project #2 — data classes (`MatchPhase`, `MatchPlayer`, `MatchState`, `EventContext`, `EventResult`, `MatchConfig`), the `EventNode` base class + `TestEvent` stub, `NetSession.return_to_lobby()` extension, and the `MatchController` that drives the 9-phase per-event state machine across a 5-event Quick Clash. Fully GUT-testable with `MockEvent` fakes; no visible UI in this plan.

**Architecture:** `MatchController` (RefCounted-extending Node) owns `MatchState` and advances through the 9-phase state machine per event. Host-authoritative continuation from sub-project #1: host runs the simulation, broadcasts state via RPC, clients mirror. Events are scenes that satisfy the `EventNode` contract; this plan ships only the `TestEvent` stub. The companion plan (Plan B) will add the visible HUD scenes that observe `MatchController` signals.

**Tech Stack:** Godot 4.6 GDScript, GUT testing framework, RefCounted data classes, signal-driven architecture. No real network in unit tests (everything runs against `MockEvent` + existing `FakeTransport`/`FakeSignalingClient`).

**Parent spec:** [`docs/superpowers/specs/2026-05-11-match-loop-and-economy-design.md`](../specs/2026-05-11-match-loop-and-economy-design.md). Re-read §5 (Architecture), §6 (Components), §7 (Data Flow), and §11 (Contract Summary) before starting.

**Companion plan (future):** A separate `2026-05-11-match-ui-and-integration.md` will be written after this plan is fully implemented. That plan adds the visible HUD scenes (`PlayerPanel`, `ResolutionOverlay`, `MatchEndOverlay`, `MatchScene`), the Lobby → Match scene transition, the two-instance integration smoke test, and the manual playtest checklist.

---

## File Structure

```
scripts/
  match/
    match_phase.gd            # Task 1: phase enum
    match_player.gd           # Task 2: per-player match record
    match_state.gd            # Task 2: authoritative state
    match_config.gd           # Task 4: constants
    match_controller.gd       # Tasks 7-13: the brain
  events/
    event_node.gd             # Task 5: base class
    event_context.gd          # Task 3: passed into events
    event_result.gd           # Task 3: returned from events
    test_event/
      test_event.gd           # Task 5: stub event
      test_event.tscn         # Task 5: stub scene
  net/
    net_session.gd            # Task 6: add return_to_lobby()
tests/
  fakes/
    mock_event.gd             # Task 7: EventNode fake for MatchController tests
  unit/
    test_match_phase.gd
    test_match_player.gd
    test_match_state.gd
    test_event_context.gd
    test_event_result.gd
    test_match_config.gd
    test_event_node.gd
    test_test_event.gd
    test_net_session_return_to_lobby.gd
    test_match_controller_skeleton.gd
    test_match_controller_phases.gd
    test_match_controller_ante.gd
    test_match_controller_event_run.gd
    test_match_controller_resolution.gd
    test_match_controller_end.gd
    test_match_controller_disconnect.gd
```

**Per-file responsibility:**

- `match_phase.gd` — enum container; not instantiated. `enum Phase { HOUSE_REVEAL, ANTE, EVENT_SELECTION, BET_LOADOUT, MAIN_EVENT, RESOLUTION, BOUNTY_HEAT_UPDATE, SHOP, HOUSE_TWIST, MATCH_END }`.
- `match_player.gd` — RefCounted data class: peer_id, seat_index, name, color_index, chips, crowns, heat, is_active_this_event. `to_dict()` / `from_dict()`.
- `match_state.gd` — RefCounted data class: event_index, phase, players, current_event_id, current_result, rng_seed, rng (seeded `RandomNumberGenerator`). `to_dict()` / `from_dict()` (rng is not serialized; reseeded on receive).
- `match_config.gd` — Object subclass with constants (starting chips by player count, ante schedule, heat max, event pool, etc.).
- `event_node.gd` — base class extending Node. Defines virtual `_run(context)` plus `event_complete` and `event_progress` signals.
- `event_context.gd` / `event_result.gd` — RefCounted data classes consumed/produced by events.
- `test_event/test_event.gd` + `.tscn` — minimal event implementation that verifies the contract.
- `match_controller.gd` — the brain. Owns state, advances phases, applies event results, broadcasts via RPC. Single file, but grown across Tasks 7-13.
- `mock_event.gd` — test double for `EventNode`. Synchronous `_run`; emits `event_complete` on a test-driven helper call.
- `net_session.gd` — minimal extension: add `return_to_lobby()` host-only public method.

## Conventions

- **TDD strictly:** failing test → run-fail → minimum implementation → run-pass → commit. Same discipline as Plans A-D from sub-project #1.
- **Commit prefixes:** `feat(client):`, `test(client):`, `chore(client):`, `refactor(client):`. The `(client)` scope matches prior Godot work.
- **Tabs for indentation in `.gd` files.** No `class_name` registration — keep `preload(...)` discipline.
- **Avoid apostrophes in PowerShell here-string commit message bodies.** When PS mangles, fall back to `git commit -F <tempfile>`.
- **GUT test runner:**
  ```
  godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
  ```
- **Test session injection:** `MatchController` accepts `is_host` and `multiplayer_node` constructor args so unit tests can construct it without an autoload context. RPC methods become no-ops when `multiplayer_node == null`.
- **Co-author footer on every commit:**
  ```
  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  ```
- **Baseline test count:** 128 unit + 1 integration after sub-project #1. Plan A tasks should bring unit tests to ~155+.
- **Forward-compatible phase assertions:** `_set_phase()` calls `_enter_phase_behavior()` synchronously, and later tasks wire more handlers (ANTE in Task 9, EVENT_SELECTION/MAIN_EVENT in Task 10, RESOLUTION in Task 11, BOUNTY_HEAT_UPDATE/MATCH_END in Task 12). This means a phase transition triggered in an earlier task may chain through several phases once those handlers exist. **When writing tests that drive `_advance_phase()` or `_set_phase()` past MAIN_EVENT, do not assert a specific stopping phase unless that phase has a no-op handler.** Use `assert_ne(phase, prev_phase)` or check observable side-effects (result stored, signal fired) instead. This convention is followed in Tasks 10 and 13 below.

---

## Phase 1: Data Classes

### Task 1: `MatchPhase` enum

Single Object subclass holding the phase enum used by `MatchState.phase` and downstream signals.

**Files:**
- Create: `scripts/match/match_phase.gd`
- Create: `tests/unit/test_match_phase.gd`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_match_phase.gd`:
```gdscript
extends GutTest

const MatchPhase = preload("res://scripts/match/match_phase.gd")

func test_phase_enum_values():
    assert_eq(MatchPhase.Phase.HOUSE_REVEAL, 0)
    assert_eq(MatchPhase.Phase.ANTE, 1)
    assert_eq(MatchPhase.Phase.EVENT_SELECTION, 2)
    assert_eq(MatchPhase.Phase.BET_LOADOUT, 3)
    assert_eq(MatchPhase.Phase.MAIN_EVENT, 4)
    assert_eq(MatchPhase.Phase.RESOLUTION, 5)
    assert_eq(MatchPhase.Phase.BOUNTY_HEAT_UPDATE, 6)
    assert_eq(MatchPhase.Phase.SHOP, 7)
    assert_eq(MatchPhase.Phase.HOUSE_TWIST, 8)
    assert_eq(MatchPhase.Phase.MATCH_END, 9)

func test_phase_name_returns_string():
    assert_eq(MatchPhase.name_for(MatchPhase.Phase.ANTE), "ANTE")
    assert_eq(MatchPhase.name_for(MatchPhase.Phase.MAIN_EVENT), "MAIN_EVENT")
    assert_eq(MatchPhase.name_for(-1), "UNKNOWN")
```

- [ ] **Step 2: Run, watch fail**

Run the GUT test command. Expected: preload failure for `match_phase.gd`.

- [ ] **Step 3: Implement**

Create `scripts/match/` directory if it doesn't exist.

`scripts/match/match_phase.gd`:
```gdscript
# Phase enum for the per-event 9-phase state machine.
# See docs/superpowers/specs/2026-05-11-match-loop-and-economy-design.md §5.5.
extends Object

enum Phase {
    HOUSE_REVEAL,
    ANTE,
    EVENT_SELECTION,
    BET_LOADOUT,
    MAIN_EVENT,
    RESOLUTION,
    BOUNTY_HEAT_UPDATE,
    SHOP,
    HOUSE_TWIST,
    MATCH_END,
}

static func name_for(phase: int) -> String:
    match phase:
        Phase.HOUSE_REVEAL: return "HOUSE_REVEAL"
        Phase.ANTE: return "ANTE"
        Phase.EVENT_SELECTION: return "EVENT_SELECTION"
        Phase.BET_LOADOUT: return "BET_LOADOUT"
        Phase.MAIN_EVENT: return "MAIN_EVENT"
        Phase.RESOLUTION: return "RESOLUTION"
        Phase.BOUNTY_HEAT_UPDATE: return "BOUNTY_HEAT_UPDATE"
        Phase.SHOP: return "SHOP"
        Phase.HOUSE_TWIST: return "HOUSE_TWIST"
        Phase.MATCH_END: return "MATCH_END"
        _: return "UNKNOWN"
```

- [ ] **Step 4: Run, watch pass**

Expected: 130/130 tests pass (128 prior + 2 new).

- [ ] **Step 5: Commit**

```
feat(client): MatchPhase enum + name_for helper

Phase enum for the per-event 9-phase state machine per design doc
section 4.2. name_for returns the string name; used by HUD phase
indicator (Plan B) and by log/debug surfaces.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 2: `MatchPlayer` + `MatchState` data classes

**Files:**
- Create: `scripts/match/match_player.gd`
- Create: `scripts/match/match_state.gd`
- Create: `tests/unit/test_match_player.gd`
- Create: `tests/unit/test_match_state.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_player.gd`:
```gdscript
extends GutTest

const MatchPlayer = preload("res://scripts/match/match_player.gd")

func test_defaults():
    var p = MatchPlayer.new()
    assert_eq(p.peer_id, 0)
    assert_eq(p.seat_index, -1)
    assert_eq(p.name, "")
    assert_eq(p.color_index, -1)
    assert_eq(p.chips, 0)
    assert_eq(p.crowns, 0)
    assert_eq(p.heat, 0)
    assert_true(p.is_active_this_event)

func test_round_trip():
    var p = MatchPlayer.new()
    p.peer_id = 2
    p.seat_index = 1
    p.name = "Maya"
    p.color_index = 3
    p.chips = 600
    p.crowns = 2
    p.heat = 5
    p.is_active_this_event = false
    var d = p.to_dict()
    var p2 = MatchPlayer.from_dict(d)
    assert_eq(p2.peer_id, 2)
    assert_eq(p2.chips, 600)
    assert_eq(p2.crowns, 2)
    assert_eq(p2.heat, 5)
    assert_false(p2.is_active_this_event)

func test_from_dict_tolerates_missing_fields():
    var p = MatchPlayer.from_dict({"peer_id": 5})
    assert_eq(p.peer_id, 5)
    assert_eq(p.chips, 0)
    assert_true(p.is_active_this_event)
```

`tests/unit/test_match_state.gd`:
```gdscript
extends GutTest

const MatchState = preload("res://scripts/match/match_state.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")

func test_defaults():
    var s = MatchState.new()
    assert_eq(s.event_index, 0)
    assert_eq(s.phase, MatchPhase.Phase.HOUSE_REVEAL)
    assert_eq(s.players.size(), 0)
    assert_eq(s.current_event_id, "")
    assert_null(s.current_result)
    assert_eq(s.rng_seed, 0)

func test_seed_rng_seeds_random_number_generator():
    var s = MatchState.new()
    s.rng_seed = 0xDEADBEEF
    s.seed_rng()
    assert_not_null(s.rng)
    var first = s.rng.randi()
    var s2 = MatchState.new()
    s2.rng_seed = 0xDEADBEEF
    s2.seed_rng()
    assert_eq(s2.rng.randi(), first, "same seed should produce same sequence")

func test_find_player_returns_match_player():
    var s = MatchState.new()
    var p = MatchPlayer.new()
    p.peer_id = 2
    s.players = [p]
    assert_eq(s.find_player(2), p)
    assert_null(s.find_player(99))

func test_round_trip_includes_players():
    var s = MatchState.new()
    s.event_index = 2
    s.phase = MatchPhase.Phase.RESOLUTION
    s.rng_seed = 0xABCD
    var p = MatchPlayer.new()
    p.peer_id = 1; p.name = "Host"; p.chips = 500
    s.players = [p]
    var d = s.to_dict()
    var s2 = MatchState.from_dict(d)
    assert_eq(s2.event_index, 2)
    assert_eq(s2.phase, MatchPhase.Phase.RESOLUTION)
    assert_eq(s2.rng_seed, 0xABCD)
    assert_eq(s2.players.size(), 1)
    assert_eq(s2.players[0].chips, 500)
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

`scripts/match/match_player.gd`:
```gdscript
# Per-player match-time state. Distinct from PlayerSlot (lobby identity).
# Built at match start by copying name/color/peer_id from PlayerSlot and
# initializing economy fields per MatchConfig.STARTING_CHIPS_BY_PLAYER_COUNT.
extends RefCounted

var peer_id: int = 0
var seat_index: int = -1
var name: String = ""
var color_index: int = -1
var chips: int = 0
var crowns: int = 0
var heat: int = 0
var is_active_this_event: bool = true

func to_dict() -> Dictionary:
    return {
        "peer_id": peer_id,
        "seat_index": seat_index,
        "name": name,
        "color_index": color_index,
        "chips": chips,
        "crowns": crowns,
        "heat": heat,
        "is_active_this_event": is_active_this_event,
    }

static func from_dict(d: Dictionary) -> RefCounted:
    var p = load("res://scripts/match/match_player.gd").new()
    p.peer_id = d.get("peer_id", 0)
    p.seat_index = d.get("seat_index", -1)
    p.name = d.get("name", "")
    p.color_index = d.get("color_index", -1)
    p.chips = d.get("chips", 0)
    p.crowns = d.get("crowns", 0)
    p.heat = d.get("heat", 0)
    p.is_active_this_event = d.get("is_active_this_event", true)
    return p
```

`scripts/match/match_state.gd`:
```gdscript
# Authoritative per-match state. Owned by host's MatchController; mirrored
# on clients via RPC. Field-level mutation is host-only.
extends RefCounted

const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

var event_index: int = 0
var phase: int = MatchPhase.Phase.HOUSE_REVEAL
var players: Array = []
var current_event_id: String = ""
var current_result = null  # EventResult or null
var rng_seed: int = 0
var rng: RandomNumberGenerator = null

func seed_rng() -> void:
    rng = RandomNumberGenerator.new()
    rng.seed = rng_seed

func find_player(peer_id: int):
    for p in players:
        if p.peer_id == peer_id:
            return p
    return null

func active_players() -> Array:
    var out: Array = []
    for p in players:
        if p.is_active_this_event:
            out.append(p)
    return out

func to_dict() -> Dictionary:
    var player_dicts: Array = []
    for p in players:
        player_dicts.append(p.to_dict())
    return {
        "event_index": event_index,
        "phase": phase,
        "players": player_dicts,
        "current_event_id": current_event_id,
        "rng_seed": rng_seed,
    }

static func from_dict(d: Dictionary) -> RefCounted:
    var s = load("res://scripts/match/match_state.gd").new()
    s.event_index = d.get("event_index", 0)
    s.phase = d.get("phase", MatchPhase.Phase.HOUSE_REVEAL)
    s.current_event_id = d.get("current_event_id", "")
    s.rng_seed = d.get("rng_seed", 0)
    s.players = []
    for raw in d.get("players", []):
        s.players.append(MatchPlayer.from_dict(raw))
    return s
```

- [ ] **Step 4: Run, watch pass**

Expected: 137/137 tests pass (130 prior + 7 new).

- [ ] **Step 5: Commit**

```
feat(client): MatchPlayer and MatchState data classes

MatchPlayer: per-player chips/crowns/heat/is_active_this_event plus
identity fields. MatchState: event_index, phase, players, current event,
RNG. Both RefCounted, both serializable via to_dict/from_dict with the
established missing-key tolerance pattern from sub-project 1.
MatchState exposes seed_rng (re-creates the RandomNumberGenerator with
rng_seed) and find_player / active_players helpers.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 3: `EventContext` + `EventResult` data classes

**Files:**
- Create: `scripts/events/event_context.gd`
- Create: `scripts/events/event_result.gd`
- Create: `tests/unit/test_event_context.gd`
- Create: `tests/unit/test_event_result.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_event_context.gd`:
```gdscript
extends GutTest

const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func test_defaults():
    var c = EventContext.new()
    assert_eq(c.players.size(), 0)
    assert_eq(c.event_index, 0)
    assert_eq(c.rng_seed, 0)
    assert_eq(c.wagers, {})

func test_round_trip():
    var c = EventContext.new()
    var p = MatchPlayer.new()
    p.peer_id = 2; p.name = "Maya"
    c.players = [p]
    c.event_index = 3
    c.rng_seed = 0xCAFE
    c.wagers = {2: 50}
    var d = c.to_dict()
    var c2 = EventContext.from_dict(d)
    assert_eq(c2.event_index, 3)
    assert_eq(c2.rng_seed, 0xCAFE)
    assert_eq(c2.wagers, {2: 50})
    assert_eq(c2.players.size(), 1)
    assert_eq(c2.players[0].name, "Maya")
```

`tests/unit/test_event_result.gd`:
```gdscript
extends GutTest

const EventResult = preload("res://scripts/events/event_result.gd")

func test_defaults():
    var r = EventResult.new()
    assert_eq(r.event_id, "")
    assert_eq(r.per_player, {})
    assert_eq(r.painful_reveal, {})

func test_delta_for_returns_zero_for_missing_peer():
    var r = EventResult.new()
    assert_eq(r.chip_delta_for(99), 0)
    assert_eq(r.crown_delta_for(99), 0)
    assert_eq(r.heat_delta_for(99), 0)
    assert_false(r.bust_for(99))

func test_delta_for_returns_dict_values():
    var r = EventResult.new()
    r.per_player = {
        2: {"chip_delta": 100, "crown_delta": 1, "heat_delta": 2, "bust": false, "cash_out_at": 3.5},
    }
    assert_eq(r.chip_delta_for(2), 100)
    assert_eq(r.crown_delta_for(2), 1)
    assert_eq(r.heat_delta_for(2), 2)
    assert_false(r.bust_for(2))

func test_round_trip():
    var r = EventResult.new()
    r.event_id = "test_event"
    r.per_player = {
        1: {"chip_delta": 0, "crown_delta": 1, "heat_delta": 1, "bust": false, "cash_out_at": 0.0},
        2: {"chip_delta": -50, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0},
    }
    r.painful_reveal = {"winner": 1, "crash_at": 1.85}
    var d = r.to_dict()
    var r2 = EventResult.from_dict(d)
    assert_eq(r2.event_id, "test_event")
    assert_eq(r2.crown_delta_for(1), 1)
    assert_true(r2.bust_for(2))
    assert_eq(r2.painful_reveal.winner, 1)
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

`scripts/events/event_context.gd`:
```gdscript
# Data passed into an event's _run(context) method. Built by MatchController
# from the active players, the current event index, a derived per-event seed,
# and the wager dictionary (MVP: flat ante per active player).
extends RefCounted

const MatchPlayer = preload("res://scripts/match/match_player.gd")

var players: Array = []
var event_index: int = 0
var rng_seed: int = 0
var wagers: Dictionary = {}

func to_dict() -> Dictionary:
    var player_dicts: Array = []
    for p in players:
        player_dicts.append(p.to_dict())
    return {
        "players": player_dicts,
        "event_index": event_index,
        "rng_seed": rng_seed,
        "wagers": wagers,
    }

static func from_dict(d: Dictionary) -> RefCounted:
    var c = load("res://scripts/events/event_context.gd").new()
    c.event_index = d.get("event_index", 0)
    c.rng_seed = d.get("rng_seed", 0)
    c.wagers = d.get("wagers", {})
    c.players = []
    for raw in d.get("players", []):
        c.players.append(MatchPlayer.from_dict(raw))
    return c
```

`scripts/events/event_result.gd`:
```gdscript
# Data returned from an event via event_complete(result). Per-player deltas
# describe the event's economic outcome; painful_reveal is opaque UI payload
# for the ResolutionOverlay (Plan B).
extends RefCounted

var event_id: String = ""
var per_player: Dictionary = {}
var painful_reveal: Dictionary = {}

func chip_delta_for(peer_id: int) -> int:
    var entry = per_player.get(peer_id, null)
    if entry == null:
        return 0
    return int(entry.get("chip_delta", 0))

func crown_delta_for(peer_id: int) -> int:
    var entry = per_player.get(peer_id, null)
    if entry == null:
        return 0
    return int(entry.get("crown_delta", 0))

func heat_delta_for(peer_id: int) -> int:
    var entry = per_player.get(peer_id, null)
    if entry == null:
        return 0
    return int(entry.get("heat_delta", 0))

func bust_for(peer_id: int) -> bool:
    var entry = per_player.get(peer_id, null)
    if entry == null:
        return false
    return bool(entry.get("bust", false))

func to_dict() -> Dictionary:
    return {
        "event_id": event_id,
        "per_player": per_player.duplicate(true),
        "painful_reveal": painful_reveal.duplicate(true),
    }

static func from_dict(d: Dictionary) -> RefCounted:
    var r = load("res://scripts/events/event_result.gd").new()
    r.event_id = d.get("event_id", "")
    r.per_player = d.get("per_player", {}).duplicate(true)
    r.painful_reveal = d.get("painful_reveal", {}).duplicate(true)
    return r
```

- [ ] **Step 4: Run, watch pass**

Expected: 144/144 tests pass (137 prior + 7 new).

- [ ] **Step 5: Commit**

```
feat(client): EventContext and EventResult data classes

Event-interface payload types per spec section 6.1 and 11. EventContext
carries (active_players, event_index, derived_rng_seed, wagers) into
event._run; EventResult carries per-player chip/crown/heat deltas plus
opaque painful_reveal back out. Both RefCounted with to_dict/from_dict.
Helpers chip_delta_for / crown_delta_for / heat_delta_for / bust_for
return zero/false for missing peer entries (defensive default).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 4: `MatchConfig` constants

**Files:**
- Create: `scripts/match/match_config.gd`
- Create: `tests/unit/test_match_config.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_config.gd`:
```gdscript
extends GutTest

const MatchConfig = preload("res://scripts/match/match_config.gd")

func test_starting_chips_per_player_count():
    assert_eq(MatchConfig.STARTING_CHIPS_BY_PLAYER_COUNT[2], 800)
    assert_eq(MatchConfig.STARTING_CHIPS_BY_PLAYER_COUNT[4], 700)
    assert_eq(MatchConfig.STARTING_CHIPS_BY_PLAYER_COUNT[6], 600)
    assert_eq(MatchConfig.STARTING_CHIPS_BY_PLAYER_COUNT[8], 500)

func test_ante_schedule():
    assert_eq(MatchConfig.ANTE_BY_EVENT_INDEX, [25, 25, 25, 50, 100])

func test_heat_max():
    assert_eq(MatchConfig.HEAT_MAX, 10)

func test_event_pool_contains_test_event():
    assert_true(MatchConfig.EVENT_POOL.has("res://scripts/events/test_event/test_event.tscn"))

func test_quick_clash_event_count():
    assert_eq(MatchConfig.QUICK_CLASH_EVENT_COUNT, 5)

func test_resolution_step_delay_ms():
    assert_eq(MatchConfig.RESOLUTION_STEP_DELAY_MS, 600)

func test_event_timeout_sec():
    assert_eq(MatchConfig.EVENT_TIMEOUT_SEC, 120)

func test_starting_chips_for_lookup_helper():
    assert_eq(MatchConfig.starting_chips_for_player_count(4), 700)
    assert_eq(MatchConfig.starting_chips_for_player_count(8), 500)
    # Falls back to 500 for unsupported counts (e.g. > 8 or < 2)
    assert_eq(MatchConfig.starting_chips_for_player_count(99), 500)
    assert_eq(MatchConfig.starting_chips_for_player_count(1), 500)
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

`scripts/match/match_config.gd`:
```gdscript
# Match-level constants. See spec section 6.2.
extends Object

const STARTING_CHIPS_BY_PLAYER_COUNT: Dictionary = {
    2: 800,
    3: 700,
    4: 700,
    5: 600,
    6: 600,
    7: 500,
    8: 500,
}

const ANTE_BY_EVENT_INDEX: Array = [25, 25, 25, 50, 100]

const HEAT_MAX: int = 10

const EVENT_POOL: Array = [
    "res://scripts/events/test_event/test_event.tscn",
]

const QUICK_CLASH_EVENT_COUNT: int = 5

const RESOLUTION_STEP_DELAY_MS: int = 600

const EVENT_TIMEOUT_SEC: int = 120

static func starting_chips_for_player_count(count: int) -> int:
    return STARTING_CHIPS_BY_PLAYER_COUNT.get(count, 500)
```

- [ ] **Step 4: Run, watch pass**

Expected: 152/152 tests pass (144 prior + 8 new).

- [ ] **Step 5: Commit**

```
feat(client): MatchConfig constants for match-level economy and pacing

Constants per design doc section 5.1 (starting chips per player count),
section 4.2.2 (ante schedule by event index), section 5.3 (heat max),
section 24.2 (Quick Clash 5-event count). Event pool seeded with only
the TestEvent path; future sub-projects append. RESOLUTION_STEP_DELAY_MS
controls the per-substep pacing during phase 6. starting_chips_for_player_count
helper falls back to 500 chips for out-of-table counts.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 2: Event Interface

### Task 5: `EventNode` base class + `TestEvent` stub

**Files:**
- Create: `scripts/events/event_node.gd`
- Create: `scripts/events/test_event/test_event.gd`
- Create: `scripts/events/test_event/test_event.tscn`
- Create: `tests/unit/test_event_node.gd`
- Create: `tests/unit/test_test_event.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_event_node.gd`:
```gdscript
extends GutTest

const EventNode = preload("res://scripts/events/event_node.gd")

func test_base_class_declares_signals():
    var n = EventNode.new()
    assert_true(n.has_signal("event_complete"))
    assert_true(n.has_signal("event_progress"))

func test_base_class_has_virtual_methods():
    var n = EventNode.new()
    assert_true(n.has_method("_run"))
    assert_true(n.has_method("get_event_id"))

func test_base_get_event_id_returns_base():
    var n = EventNode.new()
    assert_eq(n.get_event_id(), "base")
```

`tests/unit/test_test_event.gd`:
```gdscript
extends GutTest

const TestEvent = preload("res://scripts/events/test_event/test_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_context(player_count: int, seed_value: int) -> RefCounted:
    var ctx = EventContext.new()
    for i in player_count:
        var p = MatchPlayer.new()
        p.peer_id = i + 1
        p.name = "P%d" % (i + 1)
        ctx.players.append(p)
    ctx.event_index = 0
    ctx.rng_seed = seed_value
    return ctx

func test_get_event_id():
    var e = TestEvent.new()
    assert_eq(e.get_event_id(), "test_event")

func test_run_emits_event_complete():
    var e = TestEvent.new()
    e.auto_complete_ms = 0  # synchronous
    var results: Array = []
    e.event_complete.connect(func(r): results.append(r))
    e._run(_make_context(2, 0xABCD))
    assert_eq(results.size(), 1)

func test_result_is_deterministic_with_seed():
    var e1 = TestEvent.new()
    e1.auto_complete_ms = 0
    var r1: Array = [null]
    e1.event_complete.connect(func(r): r1[0] = r)
    e1._run(_make_context(3, 0xCAFE))

    var e2 = TestEvent.new()
    e2.auto_complete_ms = 0
    var r2: Array = [null]
    e2.event_complete.connect(func(r): r2[0] = r)
    e2._run(_make_context(3, 0xCAFE))

    # Same seed -> same winner.
    var winners1: Array = []
    var winners2: Array = []
    for pid in r1[0].per_player:
        if r1[0].crown_delta_for(pid) > 0:
            winners1.append(pid)
    for pid in r2[0].per_player:
        if r2[0].crown_delta_for(pid) > 0:
            winners2.append(pid)
    assert_eq(winners1, winners2, "same seed should pick same winner")

func test_result_awards_one_crown_to_one_player():
    var e = TestEvent.new()
    e.auto_complete_ms = 0
    var r: Array = [null]
    e.event_complete.connect(func(result): r[0] = result)
    e._run(_make_context(4, 0xFFFF))
    var total_crowns := 0
    for pid in r[0].per_player:
        total_crowns += r[0].crown_delta_for(pid)
    assert_eq(total_crowns, 1, "exactly one player gets a Crown")

func test_painful_reveal_names_winner():
    var e = TestEvent.new()
    e.auto_complete_ms = 0
    var r: Array = [null]
    e.event_complete.connect(func(result): r[0] = result)
    e._run(_make_context(2, 0x1234))
    assert_true(r[0].painful_reveal.has("winner_peer_id"))
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement `EventNode` base**

`scripts/events/event_node.gd`:
```gdscript
# Base class for all events. Subclasses override _run and get_event_id and
# emit event_complete exactly once per run.
#
# Contract documented in spec section 6.3 and section 11.
extends Node

signal event_complete(result)
signal event_progress(payload: Dictionary)

# Subclasses override.
func _run(_context) -> void:
    push_error("EventNode._run must be overridden")

func get_event_id() -> String:
    return "base"
```

- [ ] **Step 4: Implement `TestEvent`**

Create `scripts/events/test_event/` directory.

`scripts/events/test_event/test_event.gd`:
```gdscript
# Stub event used by sub-project #2 to verify the EventNode contract and let
# the match loop run 5 events back-to-back without depending on real game
# logic. Awards 1 Crown and +1 Heat to a deterministic winner.
extends "res://scripts/events/event_node.gd"

const EventResult = preload("res://scripts/events/event_result.gd")

var auto_complete_ms: int = 0  # if > 0, completes after this delay via timer

func get_event_id() -> String:
    return "test_event"

func _run(context) -> void:
    if auto_complete_ms > 0:
        await get_tree().create_timer(auto_complete_ms / 1000.0).timeout
    var result = _compute_result(context)
    event_complete.emit(result)

func _compute_result(context):
    var rng = RandomNumberGenerator.new()
    rng.seed = context.rng_seed
    var n = context.players.size()
    var result = EventResult.new()
    result.event_id = get_event_id()
    if n == 0:
        return result
    var winner_index = rng.randi() % n
    var winner = context.players[winner_index]
    for p in context.players:
        var entry = {"chip_delta": 0, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 0.0}
        if p.peer_id == winner.peer_id:
            entry["crown_delta"] = 1
            entry["heat_delta"] = 1
        result.per_player[p.peer_id] = entry
    result.painful_reveal = {"winner_peer_id": winner.peer_id, "winner_name": winner.name}
    return result
```

- [ ] **Step 5: Implement `TestEvent` scene**

`scripts/events/test_event/test_event.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/events/test_event/test_event.gd" id="1"]

[node name="TestEvent" type="Node"]
script = ExtResource("1")
```

(Minimal — TestEvent doesn't need any UI nodes in #2; Plan B adds optional in-event UI.)

- [ ] **Step 6: Run, watch pass**

Expected: 160/160 tests pass (152 prior + 8 new).

- [ ] **Step 7: Commit**

```
feat(client): EventNode base class + TestEvent stub

EventNode defines the standard contract: event_complete and event_progress
signals plus virtual _run and get_event_id methods. Per spec section 6.3
and 11, all real events (Rocket Clash, etc., in sub-project #3 onwards)
extend this base.

TestEvent is the stub used in sub-project #2 to verify the contract. It
runs synchronously or after auto_complete_ms delay, picks a deterministic
winner using context.rng_seed, awards 1 Crown and +1 Heat, and exposes
the winner in painful_reveal for the ResolutionOverlay (Plan B).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 6: `NetSession.return_to_lobby()` extension

**Files:**
- Modify: `scripts/net/net_session.gd`
- Create: `tests/unit/test_net_session_return_to_lobby.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_net_session_return_to_lobby.gd`:
```gdscript
extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")

func _host_session():
    var t = FakeTransport.new()
    var s = FakeSignalingClient.new()
    var session = NetSession.new(t, s)
    session.host_session()
    s.emit_code_issued("ABC234")
    return session

func test_return_to_lobby_requires_host():
    var t = FakeTransport.new()
    var s = FakeSignalingClient.new()
    var joiner = NetSession.new(t, s)
    joiner.join_session("ABC234")
    joiner.state = NetSessionState.State.MATCH
    joiner.return_to_lobby()
    assert_eq(joiner.state, NetSessionState.State.MATCH, "joiner should not transition")

func test_return_to_lobby_requires_match_state():
    var session = _host_session()
    # state is LOBBY after host_session + emit_code_issued
    session.return_to_lobby()
    assert_eq(session.state, NetSessionState.State.LOBBY, "no-op when not in MATCH")

func test_return_to_lobby_transitions_match_to_lobby():
    var session = _host_session()
    session.state = NetSessionState.State.MATCH  # simulate post-start_match
    session.return_to_lobby()
    assert_eq(session.state, NetSessionState.State.LOBBY)

func test_return_to_lobby_emits_state_changed():
    var session = _host_session()
    session.state = NetSessionState.State.MATCH
    var states: Array = []
    session.state_changed.connect(func(s): states.append(s))
    session.return_to_lobby()
    assert_true(NetSessionState.State.LOBBY in states)
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/net/net_session.gd`, add this method (place near other public state-transition methods like `start_match`):
```gdscript
func return_to_lobby() -> void:
    if not is_host:
        return
    if state != NetSessionState.State.MATCH:
        return
    _set_state(NetSessionState.State.LOBBY)
```

- [ ] **Step 4: Run, watch pass**

Expected: 164/164 tests pass (160 prior + 4 new).

- [ ] **Step 5: Commit**

```
feat(client): NetSession.return_to_lobby for post-match flow

Host-only public method that transitions state from MATCH back to LOBBY,
required by sub-project 2 MatchEndOverlay return-to-lobby button. Asserts
is_host and state == MATCH; silent no-op otherwise. Clients observe via
state_changed signal as usual.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 3: `MatchController` — the brain

`MatchController` grows across Tasks 7–13. Each task adds one capability with its own test file. The constructor takes `is_host: bool` and an optional `multiplayer_node` so unit tests can construct it without an autoload context (RPC calls become no-ops when `multiplayer_node == null`).

### Task 7: `MatchController` skeleton + start_match

**Files:**
- Create: `scripts/match/match_controller.gd`
- Create: `tests/fakes/mock_event.gd`
- Create: `tests/unit/test_match_controller_skeleton.gd`

- [ ] **Step 1: Write `MockEvent` test fake**

`tests/fakes/mock_event.gd`:
```gdscript
# Synchronous EventNode fake. Tests call emit_complete(result) to drive
# event_complete instead of waiting on real timers / button presses.
extends "res://scripts/events/event_node.gd"

var run_calls: Array = []  # array of contexts
var event_id_value: String = "mock_event"

func get_event_id() -> String:
    return event_id_value

func _run(context) -> void:
    run_calls.append(context)
    # Test drives completion explicitly via emit_complete.

func emit_complete(result) -> void:
    event_complete.emit(result)
```

- [ ] **Step 2: Write the failing tests**

`tests/unit/test_match_controller_skeleton.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start(player_count: int) -> RefCounted:
    var ms = MatchStart.new()
    for i in player_count:
        var s = PlayerSlot.new()
        s.peer_id = i + 1
        s.seat_index = i
        s.name = "P%d" % (i + 1)
        s.color_index = i
        s.is_host = (i == 0)
        ms.seats.append(s)
    ms.host_peer_id = 1
    ms.rng_seed = 0xCAFEBABE
    ms.mode = "quick_clash"
    return ms

func test_initial_state():
    var c = MatchController.new(true, null)
    assert_eq(c.state.event_index, 0)
    assert_eq(c.state.phase, MatchPhase.Phase.HOUSE_REVEAL)
    assert_eq(c.state.players.size(), 0)
    assert_true(c.is_host)

func test_start_match_builds_players_from_seats():
    var c = MatchController.new(true, null)
    c.start_match(_build_match_start(3))
    assert_eq(c.state.players.size(), 3)
    assert_eq(c.state.players[0].peer_id, 1)
    assert_eq(c.state.players[0].name, "P1")
    assert_eq(c.state.players[1].name, "P2")

func test_start_match_initializes_chips_from_player_count():
    var c = MatchController.new(true, null)
    c.start_match(_build_match_start(4))
    for p in c.state.players:
        assert_eq(p.chips, 700, "4 players -> 700 starting chips per MatchConfig")

func test_start_match_initializes_chips_for_two_players():
    var c = MatchController.new(true, null)
    c.start_match(_build_match_start(2))
    for p in c.state.players:
        assert_eq(p.chips, 800)

func test_start_match_seeds_rng():
    var c = MatchController.new(true, null)
    c.start_match(_build_match_start(2))
    assert_not_null(c.state.rng)
    assert_eq(c.state.rng_seed, 0xCAFEBABE)

func test_start_match_emits_phase_changed_signal():
    var c = MatchController.new(true, null)
    var phases: Array = []
    c.phase_changed.connect(func(p): phases.append(p))
    c.start_match(_build_match_start(2))
    assert_true(MatchPhase.Phase.HOUSE_REVEAL in phases)
```

- [ ] **Step 3: Run, watch fail**

- [ ] **Step 4: Implement minimum**

`scripts/match/match_controller.gd`:
```gdscript
# Owns MatchState and drives the per-event 9-phase state machine.
# Host-authoritative: only the host mutates state and broadcasts via RPC.
# See spec sections 5 and 6.5 for the full design.
extends Node

const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")

signal phase_changed(new_phase: int)
signal event_starting(event_id: String, event_index: int)
signal resolution_step(step_name: String, payload: Dictionary)
signal match_ended(rankings: Array)
signal player_resources_changed(peer_id: int)

var state: MatchState
var is_host: bool = false
var _multiplayer_node = null  # for RPC routing in production; null in unit tests

func _init(p_is_host: bool = false, multiplayer_node = null) -> void:
    is_host = p_is_host
    _multiplayer_node = multiplayer_node
    state = MatchState.new()

func start_match(match_start) -> void:
    if not is_host:
        return
    # Build MatchPlayer records from MatchStart seats.
    state.players = []
    var player_count = match_start.seats.size()
    var starting_chips = MatchConfig.starting_chips_for_player_count(player_count)
    for seat in match_start.seats:
        var mp = MatchPlayer.new()
        mp.peer_id = seat.peer_id
        mp.seat_index = seat.seat_index
        mp.name = seat.name
        mp.color_index = seat.color_index
        mp.chips = starting_chips
        state.players.append(mp)
    state.rng_seed = match_start.rng_seed
    state.seed_rng()
    state.event_index = 0
    _set_phase(MatchPhase.Phase.HOUSE_REVEAL)

func _set_phase(new_phase: int) -> void:
    state.phase = new_phase
    phase_changed.emit(new_phase)
```

- [ ] **Step 5: Run, watch pass**

Expected: 170/170 tests pass (164 prior + 6 new).

- [ ] **Step 6: Commit**

```
feat(client): MatchController skeleton with start_match

Node-based controller owning MatchState. Constructor takes is_host plus
an optional multiplayer_node for RPC routing (null in unit tests).
start_match (host-only) builds MatchPlayer records from MatchStart seats
with starting chips per MatchConfig, seeds the RNG, and emits phase_changed.

5 signals declared up front (phase_changed, event_starting, resolution_step,
match_ended, player_resources_changed) so downstream subscribers can wire
up before later tasks fill in the emit sites.

MockEvent test fake added for the upcoming MAIN_EVENT phase tests.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 8: `MatchController` no-op phase transitions

The 9-phase state machine needs an internal `_advance_phase()` driver. This task wires the no-op transitions (HOUSE_REVEAL → ANTE, BET_LOADOUT → MAIN_EVENT, SHOP → HOUSE_TWIST, etc.) with stubbed behaviors. Real phase logic (ANTE deduction, MAIN_EVENT runs) comes in Tasks 9-12.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_phases.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_controller_phases.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start(player_count: int) -> RefCounted:
    var ms = MatchStart.new()
    for i in player_count:
        var s = PlayerSlot.new()
        s.peer_id = i + 1
        s.seat_index = i
        s.name = "P%d" % (i + 1)
        ms.seats.append(s)
    ms.host_peer_id = 1
    ms.rng_seed = 1
    return ms

func _new_controller() -> MatchController:
    var c = MatchController.new(true, null)
    c.start_match(_build_match_start(2))
    return c

func test_house_reveal_advances_to_ante():
    var c = _new_controller()
    c._advance_phase()
    assert_eq(c.state.phase, MatchPhase.Phase.ANTE)

func test_bet_loadout_advances_to_main_event():
    var c = _new_controller()
    c.state.phase = MatchPhase.Phase.BET_LOADOUT
    c._advance_phase()
    assert_eq(c.state.phase, MatchPhase.Phase.MAIN_EVENT)

func test_shop_advances_to_house_twist():
    var c = _new_controller()
    c.state.phase = MatchPhase.Phase.SHOP
    c._advance_phase()
    assert_eq(c.state.phase, MatchPhase.Phase.HOUSE_TWIST)

func test_house_twist_increments_event_and_returns_to_house_reveal():
    var c = _new_controller()
    c.state.phase = MatchPhase.Phase.HOUSE_TWIST
    c.state.event_index = 2
    c._advance_phase()
    assert_eq(c.state.event_index, 3)
    assert_eq(c.state.phase, MatchPhase.Phase.HOUSE_REVEAL)

func test_house_twist_on_final_event_transitions_to_match_end():
    var c = _new_controller()
    c.state.phase = MatchPhase.Phase.HOUSE_TWIST
    c.state.event_index = 4  # last event in Quick Clash
    c._advance_phase()
    assert_eq(c.state.event_index, 4, "event_index does not increment past last")
    assert_eq(c.state.phase, MatchPhase.Phase.MATCH_END)

func test_advance_phase_emits_phase_changed():
    var c = _new_controller()
    var phases: Array = []
    c.phase_changed.connect(func(p): phases.append(p))
    c._advance_phase()
    assert_true(MatchPhase.Phase.ANTE in phases)
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/match/match_controller.gd`, add `_advance_phase` method:

```gdscript
# Internal: advance the phase machine. Each phase decides what to do next.
# Real phase behavior (ANTE deduction, EVENT_SELECTION pick, MAIN_EVENT run,
# RESOLUTION pipeline) is filled in by Tasks 9-12.
func _advance_phase() -> void:
    var next_phase: int
    match state.phase:
        MatchPhase.Phase.HOUSE_REVEAL:
            next_phase = MatchPhase.Phase.ANTE
        MatchPhase.Phase.ANTE:
            next_phase = MatchPhase.Phase.EVENT_SELECTION
        MatchPhase.Phase.EVENT_SELECTION:
            next_phase = MatchPhase.Phase.BET_LOADOUT
        MatchPhase.Phase.BET_LOADOUT:
            next_phase = MatchPhase.Phase.MAIN_EVENT
        MatchPhase.Phase.MAIN_EVENT:
            next_phase = MatchPhase.Phase.RESOLUTION
        MatchPhase.Phase.RESOLUTION:
            next_phase = MatchPhase.Phase.BOUNTY_HEAT_UPDATE
        MatchPhase.Phase.BOUNTY_HEAT_UPDATE:
            next_phase = MatchPhase.Phase.SHOP
        MatchPhase.Phase.SHOP:
            next_phase = MatchPhase.Phase.HOUSE_TWIST
        MatchPhase.Phase.HOUSE_TWIST:
            if state.event_index < MatchConfig.QUICK_CLASH_EVENT_COUNT - 1:
                state.event_index += 1
                next_phase = MatchPhase.Phase.HOUSE_REVEAL
            else:
                next_phase = MatchPhase.Phase.MATCH_END
        _:
            return  # MATCH_END or unknown: do nothing
    _set_phase(next_phase)
```

- [ ] **Step 4: Run, watch pass**

Expected: 176/176 tests pass (170 prior + 6 new).

- [ ] **Step 5: Commit**

```
feat(client): MatchController phase-advance state machine

_advance_phase walks the 9-phase per-event cycle plus the event-index
increment / MATCH_END terminal. Phases without real MVP behavior simply
advance (HOUSE_REVEAL, BET_LOADOUT, SHOP, HOUSE_TWIST). Real behavior for
ANTE (Task 9), EVENT_SELECTION + MAIN_EVENT (Task 10), and RESOLUTION
(Task 11) fills in across the next tasks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 9: ANTE phase logic

Real behavior for the ANTE phase: deduct ante from each player's chips. Players who can't afford it sit out the event (`is_active_this_event = false`).

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_ante.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_controller_ante.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start(player_count: int) -> RefCounted:
    var ms = MatchStart.new()
    for i in player_count:
        var s = PlayerSlot.new()
        s.peer_id = i + 1
        s.seat_index = i
        s.name = "P%d" % (i + 1)
        ms.seats.append(s)
    ms.host_peer_id = 1
    ms.rng_seed = 1
    return ms

func _new_controller(player_count: int = 2) -> MatchController:
    var c = MatchController.new(true, null)
    c.start_match(_build_match_start(player_count))
    return c

func test_ante_deducts_chips_for_event_0():
    var c = _new_controller(2)  # 800 starting chips
    c.state.phase = MatchPhase.Phase.ANTE
    c._enter_phase_behavior()
    var ante = MatchConfig.ANTE_BY_EVENT_INDEX[0]
    for p in c.state.players:
        assert_eq(p.chips, 800 - ante, "ante deducted for event 0")
        assert_true(p.is_active_this_event)

func test_ante_uses_event_index_for_amount():
    var c = _new_controller(2)
    c.state.event_index = 4  # final event, ante 100
    c.state.phase = MatchPhase.Phase.ANTE
    c._enter_phase_behavior()
    var ante = MatchConfig.ANTE_BY_EVENT_INDEX[4]
    for p in c.state.players:
        assert_eq(p.chips, 800 - ante)

func test_ante_player_with_insufficient_chips_sits_out():
    var c = _new_controller(2)
    c.state.event_index = 4  # ante 100
    c.state.players[0].chips = 50  # not enough
    c.state.phase = MatchPhase.Phase.ANTE
    c._enter_phase_behavior()
    assert_eq(c.state.players[0].chips, 50, "no deduction")
    assert_false(c.state.players[0].is_active_this_event)
    assert_eq(c.state.players[1].chips, 800 - 100, "other player paid")
    assert_true(c.state.players[1].is_active_this_event)

func test_ante_emits_player_resources_changed_per_paying_player():
    var c = _new_controller(2)
    c.state.phase = MatchPhase.Phase.ANTE
    var changed: Array = []
    c.player_resources_changed.connect(func(pid): changed.append(pid))
    c._enter_phase_behavior()
    assert_eq(changed.size(), 2, "both players paid -> two emissions")
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/match/match_controller.gd`, add `_enter_phase_behavior()` (called when entering a phase that has real MVP behavior). For now, only ANTE has logic:

```gdscript
# Called on host when entering a phase to execute MVP behavior. Phases not
# covered here are no-ops (handled by _advance_phase chaining alone).
func _enter_phase_behavior() -> void:
    if not is_host:
        return
    match state.phase:
        MatchPhase.Phase.ANTE:
            _process_ante_phase()
        _:
            pass

func _process_ante_phase() -> void:
    var ante = MatchConfig.ANTE_BY_EVENT_INDEX[state.event_index]
    for p in state.players:
        if p.chips >= ante:
            p.chips -= ante
            p.is_active_this_event = true
            player_resources_changed.emit(p.peer_id)
        else:
            p.is_active_this_event = false
```

Also update `_set_phase` to call `_enter_phase_behavior` after the signal:
```gdscript
func _set_phase(new_phase: int) -> void:
    state.phase = new_phase
    phase_changed.emit(new_phase)
    _enter_phase_behavior()
```

- [ ] **Step 4: Run, watch pass**

Expected: 180/180 tests pass (176 prior + 4 new).

- [ ] **Step 5: Commit**

```
feat(client): MatchController ANTE phase deducts chips per event_index

_process_ante_phase iterates state.players; deducts ANTE_BY_EVENT_INDEX
amount if the player can afford it (sets is_active_this_event = true and
emits player_resources_changed), otherwise sits them out
(is_active_this_event = false, no deduction). _enter_phase_behavior is
the host-side phase entry hook called from _set_phase; future tasks add
behaviors for EVENT_SELECTION, MAIN_EVENT, RESOLUTION, BOUNTY_HEAT_UPDATE.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 10: EVENT_SELECTION + MAIN_EVENT integration

Host picks an event from the pool and runs it. Uses MockEvent in tests.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_event_run.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_controller_event_run.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MockEvent = preload("res://tests/fakes/mock_event.gd")
const EventResult = preload("res://scripts/events/event_result.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start(player_count: int) -> RefCounted:
    var ms = MatchStart.new()
    for i in player_count:
        var s = PlayerSlot.new()
        s.peer_id = i + 1; s.seat_index = i; s.name = "P%d" % (i + 1)
        ms.seats.append(s)
    ms.host_peer_id = 1; ms.rng_seed = 0xCAFE
    return ms

func _new_controller_with_mock() -> Dictionary:
    var c = MatchController.new(true, null)
    var mock = MockEvent.new()
    # Inject the factory so MatchController uses the mock instead of loading a scene.
    c._event_factory = func(_path): return mock
    c.start_match(_build_match_start(2))
    return {"controller": c, "mock": mock}

func test_event_selection_picks_from_pool():
    var d = _new_controller_with_mock()
    var c = d.controller
    c.state.phase = MatchPhase.Phase.EVENT_SELECTION
    c._enter_phase_behavior()
    assert_eq(c.state.current_event_id, "res://scripts/events/test_event/test_event.tscn")

func test_main_event_instantiates_via_factory_and_calls_run():
    var d = _new_controller_with_mock()
    var c = d.controller
    var mock = d.mock
    c.state.current_event_id = "res://scripts/events/test_event/test_event.tscn"
    c.state.phase = MatchPhase.Phase.MAIN_EVENT
    c._enter_phase_behavior()
    assert_eq(mock.run_calls.size(), 1, "_run called once with context")
    var ctx = mock.run_calls[0]
    assert_eq(ctx.event_index, 0)
    assert_eq(ctx.players.size(), 2)

func test_event_complete_stores_result_and_advances_past_main_event():
    var d = _new_controller_with_mock()
    var c = d.controller
    var mock = d.mock
    c.state.current_event_id = "res://scripts/events/test_event/test_event.tscn"
    c.state.phase = MatchPhase.Phase.MAIN_EVENT
    c._enter_phase_behavior()
    # Now drive event completion.
    var result = EventResult.new()
    result.event_id = "mock_event"
    mock.emit_complete(result)
    # In Task 10, RESOLUTION is still a no-op so phase == RESOLUTION.
    # In Task 11+, the RESOLUTION pipeline runs synchronously and chains
    # through to BOUNTY_HEAT_UPDATE; assert forward-compatibly that phase
    # left MAIN_EVENT and that current_result was stored.
    assert_ne(c.state.phase, MatchPhase.Phase.MAIN_EVENT)
    assert_eq(c.state.current_result, result)

func test_event_starting_signal_fired():
    var d = _new_controller_with_mock()
    var c = d.controller
    var starts: Array = []
    c.event_starting.connect(func(eid, idx): starts.append([eid, idx]))
    c.state.current_event_id = "res://scripts/events/test_event/test_event.tscn"
    c.state.phase = MatchPhase.Phase.MAIN_EVENT
    c._enter_phase_behavior()
    assert_eq(starts.size(), 1)
    assert_eq(starts[0][1], 0)

func test_context_includes_only_active_players():
    var d = _new_controller_with_mock()
    var c = d.controller
    c.state.players[0].is_active_this_event = false  # P1 sat out ante
    c.state.current_event_id = "res://scripts/events/test_event/test_event.tscn"
    c.state.phase = MatchPhase.Phase.MAIN_EVENT
    c._enter_phase_behavior()
    var ctx = d.mock.run_calls[0]
    assert_eq(ctx.players.size(), 1)
    assert_eq(ctx.players[0].peer_id, 2)
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/match/match_controller.gd`:

Add an event-factory hook (testable seam):
```gdscript
const EventContext = preload("res://scripts/events/event_context.gd")

# Factory injected by tests; production code uses _default_event_factory.
# IMPORTANT: do NOT initialize at declaration (`= _default_event_factory`) —
# instance methods aren't bindable at field-init time in GDScript 2.0.
# Assign in _init instead.
var _event_factory: Callable
var _current_event_node = null

func _default_event_factory(path: String):
    var ps = load(path)
    if ps == null:
        return null
    return ps.instantiate()
```

Extend `_init` to bind the default factory (add after the existing `is_host` / `multiplayer_node` assignment from Task 7):
```gdscript
func _init(p_is_host: bool = false, p_multiplayer_node = null) -> void:
    is_host = p_is_host
    multiplayer_node = p_multiplayer_node
    _event_factory = Callable(self, "_default_event_factory")
```

Extend `_enter_phase_behavior` to handle EVENT_SELECTION and MAIN_EVENT:
```gdscript
func _enter_phase_behavior() -> void:
    if not is_host:
        return
    match state.phase:
        MatchPhase.Phase.ANTE:
            _process_ante_phase()
        MatchPhase.Phase.EVENT_SELECTION:
            _process_event_selection()
        MatchPhase.Phase.MAIN_EVENT:
            _process_main_event()
        _:
            pass

func _process_event_selection() -> void:
    var pool = MatchConfig.EVENT_POOL
    var idx = state.rng.randi() % pool.size()
    state.current_event_id = pool[idx]

func _process_main_event() -> void:
    _current_event_node = _event_factory.call(state.current_event_id)
    if _current_event_node == null:
        # Load failed; synthesize empty result and advance.
        var empty_result = preload("res://scripts/events/event_result.gd").new()
        state.current_result = empty_result
        _advance_phase()
        return
    _current_event_node.event_complete.connect(_on_event_complete)
    event_starting.emit(_current_event_node.get_event_id(), state.event_index)
    var context = _build_event_context()
    _current_event_node._run(context)

func _build_event_context():
    var ctx = EventContext.new()
    for p in state.players:
        if p.is_active_this_event:
            ctx.players.append(p)
    ctx.event_index = state.event_index
    ctx.rng_seed = state.rng_seed ^ (state.event_index * 0x9E3779B9)
    var ante = MatchConfig.ANTE_BY_EVENT_INDEX[state.event_index]
    for p in ctx.players:
        ctx.wagers[p.peer_id] = ante
    return ctx

func _on_event_complete(result) -> void:
    state.current_result = result
    if _current_event_node != null:
        _current_event_node.queue_free()
        _current_event_node = null
    _advance_phase()
```

- [ ] **Step 4: Run, watch pass**

Expected: 185/185 tests pass (180 prior + 5 new).

- [ ] **Step 5: Commit**

```
feat(client): MatchController EVENT_SELECTION + MAIN_EVENT integration

EVENT_SELECTION picks a path from MatchConfig.EVENT_POOL via the seeded
RNG and stores it on state.current_event_id.

MAIN_EVENT instantiates the event via the injectable _event_factory
(default loads the .tscn), wires its event_complete signal, emits
event_starting for the HUD, and calls _run with an EventContext built
from active players (is_active_this_event = true). Inactive players
(those who sat out ANTE) are excluded from context.players.

The per-event RNG seed is derived from the match seed XOR event_index
times a constant so each event sees a deterministic but distinct seed.

_on_event_complete frees the event node and advances to RESOLUTION.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 11: RESOLUTION pipeline

The resolution pipeline emits substeps with delays between them. To keep tests synchronous, the per-step delay is injectable.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_resolution.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_controller_resolution.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const EventResult = preload("res://scripts/events/event_result.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start(player_count: int) -> RefCounted:
    var ms = MatchStart.new()
    for i in player_count:
        var s = PlayerSlot.new()
        s.peer_id = i + 1; s.seat_index = i; s.name = "P%d" % (i + 1)
        ms.seats.append(s)
    ms.host_peer_id = 1; ms.rng_seed = 0xCAFE
    return ms

func _new_controller_synchronous() -> MatchController:
    var c = MatchController.new(true, null)
    c.resolution_step_delay_ms_override = 0  # synchronous
    c.start_match(_build_match_start(2))
    return c

func _result_with_chips(p1_delta: int, p2_delta: int) -> RefCounted:
    var r = EventResult.new()
    r.per_player = {
        1: {"chip_delta": p1_delta, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 0.0},
        2: {"chip_delta": p2_delta, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 0.0},
    }
    return r

func test_resolution_emits_substeps_in_order():
    var c = _new_controller_synchronous()
    c.state.current_result = _result_with_chips(0, 0)
    c.state.phase = MatchPhase.Phase.RESOLUTION
    var steps: Array = []
    c.resolution_step.connect(func(name, _payload): steps.append(name))
    c._enter_phase_behavior()
    assert_eq(steps, ["busts", "cash_outs", "chip_changes", "crown_awards", "painful_reveal"])

func test_resolution_applies_chip_deltas():
    var c = _new_controller_synchronous()
    var pre_chips_p1 = c.state.players[0].chips
    var pre_chips_p2 = c.state.players[1].chips
    c.state.current_result = _result_with_chips(100, -50)
    c.state.phase = MatchPhase.Phase.RESOLUTION
    c._enter_phase_behavior()
    assert_eq(c.state.players[0].chips, pre_chips_p1 + 100)
    assert_eq(c.state.players[1].chips, pre_chips_p2 - 50)

func test_resolution_applies_crown_deltas():
    var c = _new_controller_synchronous()
    var r = EventResult.new()
    r.per_player = {
        1: {"chip_delta": 0, "crown_delta": 1, "heat_delta": 0, "bust": false, "cash_out_at": 0.0},
        2: {"chip_delta": 0, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 0.0},
    }
    c.state.current_result = r
    c.state.phase = MatchPhase.Phase.RESOLUTION
    c._enter_phase_behavior()
    assert_eq(c.state.players[0].crowns, 1)
    assert_eq(c.state.players[1].crowns, 0)

func test_resolution_emits_player_resources_changed_per_delta():
    var c = _new_controller_synchronous()
    c.state.current_result = _result_with_chips(10, -10)
    c.state.phase = MatchPhase.Phase.RESOLUTION
    var changed: Array = []
    c.player_resources_changed.connect(func(pid): changed.append(pid))
    c._enter_phase_behavior()
    # 2 chip_changes emissions + 0 crown_awards emissions (deltas were 0) = 2
    assert_eq(changed.size(), 2)

func test_resolution_advances_to_bounty_heat_update():
    var c = _new_controller_synchronous()
    c.state.current_result = _result_with_chips(0, 0)
    c.state.phase = MatchPhase.Phase.RESOLUTION
    c._enter_phase_behavior()
    # Synchronous delay -> immediately advances
    assert_eq(c.state.phase, MatchPhase.Phase.BOUNTY_HEAT_UPDATE)
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/match/match_controller.gd`:

Add the configurable delay seam (introduced now so Plan B can wire pacing without churn; Plan A's pipeline is fully synchronous so the variable is declared but not yet read):
```gdscript
# Test seam: override per-step delay to 0 for synchronous tests.
# Plan A: declared for forward-compat; the synchronous pipeline below
# ignores it. Plan B wires this into a Timer-driven pacing path.
var resolution_step_delay_ms_override: int = -1
```

Extend `_enter_phase_behavior`:
```gdscript
        MatchPhase.Phase.RESOLUTION:
            _process_resolution_phase()
```

Add the pipeline:
```gdscript
func _process_resolution_phase() -> void:
    var result = state.current_result
    if result == null:
        _advance_phase()
        return
    # Sequential substep emission. For tests, delay = 0 advances synchronously.
    _emit_resolution_step("busts", _build_busts_payload(result))
    _emit_resolution_step("cash_outs", _build_cash_outs_payload(result))
    _apply_and_emit("chip_changes", result, "chip_delta")
    _apply_and_emit("crown_awards", result, "crown_delta")
    _emit_resolution_step("painful_reveal", result.painful_reveal)
    _advance_phase()

func _emit_resolution_step(name: String, payload: Dictionary) -> void:
    resolution_step.emit(name, payload)

func _build_busts_payload(result) -> Dictionary:
    var bust_ids: Array = []
    for pid in result.per_player.keys():
        if result.bust_for(pid):
            bust_ids.append(pid)
    return {"bust_peer_ids": bust_ids}

func _build_cash_outs_payload(result) -> Dictionary:
    var co: Dictionary = {}
    for pid in result.per_player.keys():
        var entry = result.per_player[pid]
        co[pid] = entry.get("cash_out_at", 0.0)
    return {"cash_outs": co}

func _apply_and_emit(step_name: String, result, delta_key: String) -> void:
    var deltas: Array = []
    for pid in result.per_player.keys():
        var d = int(result.per_player[pid].get(delta_key, 0))
        if d == 0:
            continue
        var p = state.find_player(pid)
        if p == null:
            continue
        match delta_key:
            "chip_delta":
                p.chips += d
            "crown_delta":
                p.crowns += d
        deltas.append({"peer_id": pid, "delta": d})
        player_resources_changed.emit(pid)
    _emit_resolution_step(step_name, {"deltas": deltas})
```

- [ ] **Step 4: Run, watch pass**

Expected: 190/190 tests pass (185 prior + 5 new).

- [ ] **Step 5: Commit**

```
feat(client): MatchController RESOLUTION substep pipeline

_process_resolution_phase walks the 5 substeps in order: busts, cash_outs,
chip_changes, crown_awards, painful_reveal. Each emits resolution_step
with a payload Dictionary. chip_changes and crown_awards mutate
authoritative state and emit player_resources_changed per affected player.

Test seam resolution_step_delay_ms_override allows synchronous execution
in unit tests; production wiring (Plan B) will use the MatchConfig default
600ms between substeps for theatrical pacing per design 4.2.6.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 12: BOUNTY_HEAT_UPDATE + MATCH_END + rankings

Heat is applied in BOUNTY_HEAT_UPDATE (bounties deferred). MATCH_END computes rankings.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_end.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_controller_end.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")
const EventResult = preload("res://scripts/events/event_result.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start(player_count: int) -> RefCounted:
    var ms = MatchStart.new()
    for i in player_count:
        var s = PlayerSlot.new()
        s.peer_id = i + 1; s.seat_index = i; s.name = "P%d" % (i + 1)
        ms.seats.append(s)
    ms.host_peer_id = 1; ms.rng_seed = 1
    return ms

func _new_controller() -> MatchController:
    var c = MatchController.new(true, null)
    c.start_match(_build_match_start(3))
    return c

func test_bounty_heat_applies_heat_deltas():
    var c = _new_controller()
    var r = EventResult.new()
    r.per_player = {
        1: {"chip_delta": 0, "crown_delta": 0, "heat_delta": 2, "bust": false, "cash_out_at": 0.0},
        2: {"chip_delta": 0, "crown_delta": 0, "heat_delta": -1, "bust": false, "cash_out_at": 0.0},
    }
    c.state.current_result = r
    c.state.phase = MatchPhase.Phase.BOUNTY_HEAT_UPDATE
    c._enter_phase_behavior()
    assert_eq(c.state.players[0].heat, 2)
    assert_eq(c.state.players[1].heat, 0, "heat clamps to 0")

func test_heat_clamps_to_max():
    var c = _new_controller()
    c.state.players[0].heat = 9
    var r = EventResult.new()
    r.per_player = {1: {"chip_delta": 0, "crown_delta": 0, "heat_delta": 5, "bust": false, "cash_out_at": 0.0}}
    c.state.current_result = r
    c.state.phase = MatchPhase.Phase.BOUNTY_HEAT_UPDATE
    c._enter_phase_behavior()
    assert_eq(c.state.players[0].heat, MatchConfig.HEAT_MAX)

func test_match_end_emits_rankings_sorted_by_crowns():
    var c = _new_controller()
    c.state.players[0].crowns = 2
    c.state.players[1].crowns = 5
    c.state.players[2].crowns = 3
    var rankings: Array = []
    c.match_ended.connect(func(r): rankings = r)
    c.state.phase = MatchPhase.Phase.MATCH_END
    c._enter_phase_behavior()
    assert_eq(rankings.size(), 3)
    assert_eq(rankings[0].peer_id, 2)
    assert_eq(rankings[1].peer_id, 3)
    assert_eq(rankings[2].peer_id, 1)

func test_match_end_breaks_ties_by_chips_then_heat():
    var c = _new_controller()
    c.state.players[0].crowns = 3; c.state.players[0].chips = 500; c.state.players[0].heat = 2
    c.state.players[1].crowns = 3; c.state.players[1].chips = 700; c.state.players[1].heat = 1
    c.state.players[2].crowns = 3; c.state.players[2].chips = 700; c.state.players[2].heat = 5
    var rankings: Array = []
    c.match_ended.connect(func(r): rankings = r)
    c.state.phase = MatchPhase.Phase.MATCH_END
    c._enter_phase_behavior()
    # All tied on crowns. chips DESC: P2 and P3 tied at 700, P1 at 500.
    # heat DESC tiebreak: P3 (5) > P2 (1)
    assert_eq(rankings[0].peer_id, 3)
    assert_eq(rankings[1].peer_id, 2)
    assert_eq(rankings[2].peer_id, 1)
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/match/match_controller.gd`, extend `_enter_phase_behavior`:
```gdscript
        MatchPhase.Phase.BOUNTY_HEAT_UPDATE:
            _process_bounty_heat_update()
        MatchPhase.Phase.MATCH_END:
            _process_match_end()
```

Add handlers:
```gdscript
func _process_bounty_heat_update() -> void:
    var result = state.current_result
    if result == null:
        return
    for pid in result.per_player.keys():
        var d = result.heat_delta_for(pid)
        if d == 0:
            continue
        var p = state.find_player(pid)
        if p == null:
            continue
        p.heat = clamp(p.heat + d, 0, MatchConfig.HEAT_MAX)
        player_resources_changed.emit(pid)

func _process_match_end() -> void:
    var rankings = state.players.duplicate()
    rankings.sort_custom(func(a, b):
        if a.crowns != b.crowns:
            return a.crowns > b.crowns
        if a.chips != b.chips:
            return a.chips > b.chips
        return a.heat > b.heat
    )
    match_ended.emit(rankings)
```

- [ ] **Step 4: Run, watch pass**

Expected: 194/194 tests pass (190 prior + 4 new).

- [ ] **Step 5: Commit**

```
feat(client): MatchController BOUNTY_HEAT_UPDATE and MATCH_END

BOUNTY_HEAT_UPDATE applies heat_delta from current_result, clamped to
[0, MatchConfig.HEAT_MAX]. Emits player_resources_changed per affected
player. Bounty deltas are deferred to sub-project 4 (bounties), so this
task only handles the heat side of the phase.

MATCH_END sorts players by (crowns DESC, chips DESC, heat DESC) per spec
section 4 decisions table tiebreaker rules, emits match_ended(rankings).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 13: Disconnect/pause + event timeout

Two related correctness fixes that don't fit elsewhere: handling `NetSession.state_changed(PAUSED)` mid-match, and watchdog on stuck events.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_disconnect.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_controller_disconnect.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MockEvent = preload("res://tests/fakes/mock_event.gd")
const EventResult = preload("res://scripts/events/event_result.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start(player_count: int) -> RefCounted:
    var ms = MatchStart.new()
    for i in player_count:
        var s = PlayerSlot.new()
        s.peer_id = i + 1; s.seat_index = i; s.name = "P%d" % (i + 1)
        ms.seats.append(s)
    ms.host_peer_id = 1; ms.rng_seed = 1
    return ms

func _new_with_mock() -> Dictionary:
    var c = MatchController.new(true, null)
    var mock = MockEvent.new()
    c._event_factory = func(_path): return mock
    c.start_match(_build_match_start(2))
    return {"controller": c, "mock": mock}

func test_pause_blocks_advance_phase():
    var d = _new_with_mock()
    var c = d.controller
    c.state.phase = MatchPhase.Phase.HOUSE_REVEAL
    c.pause()
    var pre_phase = c.state.phase
    c._advance_phase()
    assert_eq(c.state.phase, pre_phase, "advance_phase should not change phase when paused")

func test_resume_unblocks_advance_phase():
    var d = _new_with_mock()
    var c = d.controller
    c.state.phase = MatchPhase.Phase.HOUSE_REVEAL
    c.pause()
    c.resume()
    c._advance_phase()
    assert_eq(c.state.phase, MatchPhase.Phase.ANTE)

func test_event_timeout_synthesizes_zero_delta_result():
    var d = _new_with_mock()
    var c = d.controller
    c.state.current_event_id = "res://scripts/events/test_event/test_event.tscn"
    c.state.phase = MatchPhase.Phase.MAIN_EVENT
    c._enter_phase_behavior()
    # Don't drive emit_complete; instead fire the watchdog manually.
    c._on_event_timeout()
    # By Task 13, the RESOLUTION pipeline (Task 11) and BOUNTY_HEAT_UPDATE
    # handler (Task 12) are both wired and chain synchronously through
    # _advance_phase. So phase will land past RESOLUTION; just assert we
    # left MAIN_EVENT and that the synthesized empty result was stored.
    assert_ne(c.state.phase, MatchPhase.Phase.MAIN_EVENT)
    assert_not_null(c.state.current_result)
    # All zero deltas
    assert_eq(c.state.current_result.chip_delta_for(1), 0)
    assert_eq(c.state.current_result.crown_delta_for(1), 0)
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/match/match_controller.gd`:

Add a pause flag and methods:
```gdscript
var _paused: bool = false

func pause() -> void:
    _paused = true

func resume() -> void:
    _paused = false
```

Modify `_advance_phase` to short-circuit when paused (add this at the very top of the method):
```gdscript
func _advance_phase() -> void:
    if _paused:
        return
    # ... existing body
```

Add the watchdog handler:
```gdscript
func _on_event_timeout() -> void:
    if _current_event_node == null:
        return
    var empty = preload("res://scripts/events/event_result.gd").new()
    # Build all-zero deltas for active players
    for p in state.players:
        if p.is_active_this_event:
            empty.per_player[p.peer_id] = {"chip_delta": 0, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0}
    state.current_result = empty
    _current_event_node.queue_free()
    _current_event_node = null
    _advance_phase()
```

(The watchdog Timer that calls `_on_event_timeout` after `MatchConfig.EVENT_TIMEOUT_SEC` is wired in Plan B alongside the Timer used for resolution-step pacing.)

- [ ] **Step 4: Run, watch pass**

Expected: 197/197 tests pass (194 prior + 3 new).

- [ ] **Step 5: Commit**

```
feat(client): MatchController pause/resume + event timeout watchdog

pause/resume gate _advance_phase so a NetSession.state_changed(PAUSED) can
freeze the state machine; resume re-enables it. Plan B's MatchScene wires
these to the NetSession signal.

_on_event_timeout synthesizes an all-bust zero-delta EventResult when an
event has run past MatchConfig.EVENT_TIMEOUT_SEC without emitting
event_complete. Test-callable directly; the Timer node firing it is added
in Plan B (which has scene-tree context).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Done

When all checkboxes above are checked, this plan's deliverables are complete:

1. Data classes (`MatchPhase`, `MatchPlayer`, `MatchState`, `EventContext`, `EventResult`, `MatchConfig`) fully implemented and tested.
2. `EventNode` base class + `TestEvent` stub satisfy the contract.
3. `NetSession.return_to_lobby()` extension lets sub-project #2 transition MATCH → LOBBY.
4. `MatchController` implements every phase handler the engine needs: ante deduction, event selection, event run via `MockEvent`/`TestEvent`, resolution pipeline (5 substeps), bounty/heat update, match_end with rankings, plus pause/resume and event-timeout watchdog. Each handler is unit-tested by directly setting `state.phase` and calling `_enter_phase_behavior()`. Live end-to-end pacing across the no-op phases (HOUSE_REVEAL, BET_LOADOUT, SHOP, HOUSE_TWIST, BOUNTY_HEAT_UPDATE → SHOP) is wired by Plan B's Timer-driven scheduler.
5. ~197 unit tests passing headlessly (up from 128 baseline).
6. The headless engine is shippable as a tested library — Plan B layers the visible HUD, the scheduler that drives the full match loop, and the integration test on top.

**Next step:** Invoke `superpowers:writing-plans` again to produce `2026-05-11-match-ui-and-integration.md`, which consumes this engine to build the `MatchScene` + HUD widgets + Lobby integration + the two-instance integration smoke test.
