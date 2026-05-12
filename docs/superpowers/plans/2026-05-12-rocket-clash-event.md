# Rocket Clash Event Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace sub-project #2's TestEvent with Rocket Clash — a real push-your-luck event with live multiplier, hidden Aviator-style crash, host-authoritative cash-out validation, an upgraded BET_LOADOUT phase that lets players place extra wagers above the ante, and a richer painful_reveal payload. Bundles Plan B's C1 production RPC wiring fix.

**Architecture:** RocketClashEvent extends EventNode and owns its own real-time RPCs (event-level, not MatchController-level). Host computes a hidden crash multiplier from the seeded RNG once, broadcasts start_time + crash_at, all peers compute multiplier(t) locally for display, cash-outs flow client→host with snapshot tolerance validation. BET_LOADOUT becomes a real phase with a 15s wager-input timer and fast-advance when all active peers ready. ResolutionOverlay's painful_reveal formatter is extended with a Rocket Clash branch that falls back to the existing TestEvent format when the payload lacks Rocket-specific keys.

**Tech Stack:** Godot 4.6, GDScript, GUT testing framework, `@rpc("authority", "call_remote", "reliable")` (state-mutating broadcasts) + `@rpc("any_peer", "call_remote", "reliable")` (client→host requests). Uses the existing FakeMultiplayerNode test fake from Plan B for RPC sender tests.

**Parent spec:** [`docs/superpowers/specs/2026-05-12-rocket-clash-event-design.md`](../specs/2026-05-12-rocket-clash-event-design.md). Re-read §5 (Architecture), §6 (Components), §7 (Data Flow), §9 (Testing), and §11 (Contract Summary) before starting.

**Companion plans (already implemented, on main):**
- `2026-05-11-match-engine.md` — sub-project #2 Plan A (headless engine)
- `2026-05-11-match-ui-and-integration.md` — sub-project #2 Plan B (HUD + scheduler + RPC + integration)

**Baseline:** 244 unit + 2 integration after sub-project #2. This plan targets 289 unit + 3 integration after Task 14 (244 baseline + 45 new unit; +1 new integration). Per-task running totals: 247 → 250 → 252 → 256 → 259 → 264 → 269 → 272 → 277 → 281 → 286 → 289 → 289 → 289 unit; integration goes from 2 to 3 in Task 14.

---

## File Structure

```
scripts/
  events/
    event_context.gd                       # MODIFY: add is_host field + round-trip
    rocket_clash/
      rocket_clash_event.gd                # NEW: event scene script + static helpers + RPCs
      rocket_clash_event.tscn              # NEW: scene tree (MultiplierLabel, StatusGrid, CashOutButton)
  match/
    match_controller.gd                    # MODIFY: C1 self-wire, BET_LOADOUT handler, wager RPCs
    match_state.gd                         # MODIFY: add pending_wagers field
    match_config.gd                        # MODIFY: add 3 constants, swap EVENT_POOL
  ui/
    bet_loadout_overlay.gd                 # NEW: wager input widget
    resolution_overlay.gd                  # MODIFY: extend painful_reveal formatter
    match_scene.gd                         # MODIFY: wire bet_loadout_started/finished signals
scenes/
  match_scene.tscn                         # MODIFY: add BetLoadoutSlot container
  ui/
    bet_loadout_overlay.tscn               # NEW: scene tree
tests/
  unit/
    test_match_controller_c1_self_wire.gd                # NEW: Task 1 (3 tests)
    test_match_config_rocket_clash_constants.gd          # NEW: Task 2 (3 tests)
    test_event_context_is_host.gd                        # NEW: Task 3 (2 tests)
    test_rocket_clash_crash_at.gd                        # NEW: Task 4 (4 tests)
    test_rocket_clash_multiplier.gd                      # NEW: Task 5 (3 tests)
    test_rocket_clash_result.gd                          # NEW: Task 6 (5 tests)
    test_rocket_clash_event.gd                           # NEW: Tasks 7-8 (8 tests)
    test_match_controller_wager_pipeline.gd              # NEW: Task 9 (5 tests)
    test_match_controller_bet_loadout.gd                 # NEW: Task 10 (4 tests)
    test_bet_loadout_overlay.gd                          # NEW: Task 11 (3 tests)
    test_resolution_overlay.gd                           # MODIFY: Task 12 (+3 tests for Rocket branch)
    test_lobby_match_scene_transition.gd                 # (untouched; from Plan B)
  integration/
    test_rocket_clash_runs.gd                            # NEW: Task 14
docs/
  PLAYTEST_CHECKLIST.md                                  # MODIFY: append Rocket Clash scenarios
```

**Per-file responsibility:**

- `rocket_clash_event.gd` — extends EventNode. Owns crash math (static `compute_crash_at`, `multiplier_at`, `compute_event_result`), `_run(context)` entry, host-only crash loop in `_process(delta)`, and four event-level RPCs (`_rpc_rocket_launched`, `_rpc_cash_out_requested`, `_rpc_cash_out_confirmed`, `_rpc_cash_out_rejected`).
- `rocket_clash_event.tscn` — Node (with script) → VBox containing MultiplierLabel + StatusGrid (HBox) + CashOutButton.
- `bet_loadout_overlay.gd` — PanelContainer. Listens to `controller.bet_loadout_started`/`bet_loadout_finished`. Shows local-player wager slider, Ready button. Calls `controller.submit_wager(amount)`. Static formatters: `format_wager_summary`, `clamp_wager`.
- `bet_loadout_overlay.tscn` — PanelContainer → VBox containing Label, HSlider, SpinBox, Button "Ready", Label (countdown).
- `match_controller.gd` modifications:
  - **C1 self-wire** in `start_match`: route RPCs via controller's own `self.rpc()`.
  - **BET_LOADOUT handler** `_process_bet_loadout` (async, with timer + fast-advance).
  - **Wager RPCs**: `submit_wager(amount)` public method, `@rpc _rpc_set_wager` receiver, `@rpc _rpc_wager_acknowledged` broadcast.
  - **`_build_event_context` priority**: read `state.pending_wagers` when non-empty.
- `match_state.gd` modification: `var pending_wagers: Dictionary = {}` + round-trip.
- `match_config.gd` modification: 3 new constants + EVENT_POOL swap.
- `resolution_overlay.gd` modification: extend `format_resolution_step("painful_reveal", ...)` branch with Rocket Clash-aware rendering when payload has `crash_at` + `cash_outs_summary`.
- `event_context.gd` modification: `var is_host: bool = false` field + round-trip.
- `match_scene.gd` modification: wire `bet_loadout_started`/`bet_loadout_finished` signals; instantiate BetLoadoutOverlay into new BetLoadoutSlot.
- `match_scene.tscn` modification: add `BetLoadoutSlot` (Container) between EventSlot and ResolutionSlot.

## Conventions

- **TDD strictly:** failing test → run-fail → minimum implementation → run-pass → commit. Same as Plan B.
- **UI tests use static formatters:** widget logic is unit-tested via `format_*` static helpers; scene wiring is verified by the integration test and manual playtest.
- **Test session injection pattern:** UI scripts default `controller`/`session` to `null` in `_ready()`; tests set the property before adding to the tree.
- **RPC test seam:** controllers/events take a `multiplayer_node` constructor arg (or settable property). Pass `null` to no-op, or inject a `FakeMultiplayerNode` (from Plan B) to record `rpc(...)` calls.
- **Event-level RPCs follow MatchController's pattern:** the event uses its own `_send_rpc` helper that routes through `_multiplayer_node` (defaulting to `self` when in-tree).
- **Cash-out validation pattern:** client sends `snapshot_mult`; host compares to `host_current_mult`; tolerance is `CASH_OUT_TOLERANCE = 0.05`.
- **Detached-controller test pattern:** Plan A/B established the `is_inside_tree()` guard. Same pattern for `RocketClashEvent`: when detached, skip Timer/SceneTree-dependent paths.
- **Commit prefixes:** `feat(client):`, `test(client):`, `chore(client):`, `refactor(client):`, `fix(client):`, `docs(client):`. `(client)` scope matches prior work.
- **Tabs for indentation in `.gd` files.** No `class_name` registration; use `preload(...)` discipline.
- **PowerShell here-string apostrophe quirk:** when commit message has apostrophes, fall back to `git commit -F <tempfile>` with `Set-Content -Encoding utf8`.
- **Co-author footer on every commit:**
  ```
  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  ```
- **GUT runner (unit):**
  ```
  godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
  ```
- **GUT runner (integration):**
  ```
  godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/integration -gexit
  ```
- **`godot` is on PATH** — resolves to `C:\Users\whann\Tools\godot-voxel-1.6\godot.exe`.

---

## Phase 1: Foundation

Three small prerequisite tasks. The C1 fix unblocks production RPC routing for everything after; the constants and `is_host` field are needed by the math helpers and event scene in Phases 2–3.

### Task 1: MatchController C1 self-wire fix

Plan B's final review caught a Critical bug: `_multiplayer_node` was being set to `MatchScene` in production, but the `@rpc` receivers live on `MatchController`. Production peer sync was broken; only the FakeMultiplayerNode test path worked. Fix: in `start_match`, self-wire `_multiplayer_node = self` when null and in-tree. Tests with detached controllers stay no-op.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Modify: `scripts/ui/match_scene.gd`
- Create: `tests/unit/test_match_controller_c1_self_wire.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_controller_c1_self_wire.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
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

func test_detached_controller_does_not_self_wire():
    var c = MatchController.new(true, null)
    # Detached — start_match should NOT self-wire because is_inside_tree() is false.
    c.start_match(_build_match_start(2))
    assert_eq(c._multiplayer_node, null, "detached: _multiplayer_node stays null")

func test_in_tree_controller_self_wires_when_null():
    var c = MatchController.new(true, null)
    c.no_op_phase_delay_ms_override = 0
    add_child_autofree(c)
    # In-tree with null injection — start_match should self-wire.
    c.start_match(_build_match_start(2))
    assert_eq(c._multiplayer_node, c, "in-tree: _multiplayer_node self-wires to controller")

func test_explicit_injection_is_preserved():
    var fake_node = Node.new()
    add_child_autofree(fake_node)
    var c = MatchController.new(true, fake_node)
    c.no_op_phase_delay_ms_override = 0
    add_child_autofree(c)
    c.start_match(_build_match_start(2))
    assert_eq(c._multiplayer_node, fake_node, "explicit injection wins over self-wire")
```

- [ ] **Step 2: Run, watch fail**

Run: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit`. Expected: `test_in_tree_controller_self_wires_when_null` fails (assertion `null != controller`).

- [ ] **Step 3: Implement the self-wire**

In `scripts/match/match_controller.gd`, modify `start_match`:

```gdscript
func start_match(match_start) -> void:
    if not is_host:
        return
    # C1 self-wire: route RPCs via this controller's own self.rpc()
    # since the @rpc receiver methods (_rpc_phase_changed, _rpc_apply_deltas,
    # etc.) live on MatchController. MatchScene passes multiplayer_node=null,
    # so without this self-wire the @rpc dispatch would target MatchScene
    # which has no such methods. Detached test controllers skip this so
    # _send_rpc continues to no-op.
    if _multiplayer_node == null and is_inside_tree():
        _multiplayer_node = self
    # ...existing body...
```

In `scripts/ui/match_scene.gd`, the existing `_ready` already passes `self` as the second arg to `MatchController.new`. Change it to `null` so the self-wire takes effect:

```gdscript
controller = MatchController.new(session.is_host, null)
add_child(controller)
```

- [ ] **Step 4: Run, watch pass**

Expected: 247/247 tests pass (244 prior + 3 new).

- [ ] **Step 5: Commit**

```
fix(client): MatchController C1 self-wire fix for production RPCs

Plan B left _multiplayer_node = MatchScene in production, but the @rpc
receivers (_rpc_phase_changed, _rpc_apply_deltas, _rpc_resolution_step,
_rpc_match_ended, _rpc_return_to_lobby) live on MatchController. Godot's
RPC dispatch routes via the target Node's path; MatchScene has no
matching receivers so clients never received broadcasts. Unit tests
passed because they inject FakeMultiplayerNode that records call sites.

Fix: in start_match, if _multiplayer_node is null AND controller is in
the active SceneTree, self-wire _multiplayer_node = self. Detached
test controllers stay null and _send_rpc continues to no-op. Explicit
injection (FakeMultiplayerNode or other) is preserved.

MatchScene now constructs the controller with multiplayer_node=null so
the self-wire engages.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 2: MatchConfig new constants for Rocket Clash + BET_LOADOUT

Three constants the event and BET_LOADOUT phase consume. EVENT_POOL is also updated in Task 13 (when scene wiring is ready); for now keep TestEvent in the pool so existing tests don't regress.

**Files:**
- Modify: `scripts/match/match_config.gd`
- Create: `tests/unit/test_match_config_rocket_clash_constants.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_config_rocket_clash_constants.gd`:
```gdscript
extends GutTest

const MatchConfig = preload("res://scripts/match/match_config.gd")

func test_bet_loadout_timeout_sec():
    assert_eq(MatchConfig.BET_LOADOUT_TIMEOUT_SEC, 15)

func test_rocket_clash_max_wager_factor():
    assert_eq(MatchConfig.ROCKET_CLASH_MAX_WAGER_FACTOR, 1.0)

func test_rocket_growth_rate():
    assert_almost_eq(MatchConfig.ROCKET_GROWTH_RATE, 0.06, 0.001)
```

- [ ] **Step 2: Run, watch fail**

Expected: 3 constant-lookup errors.

- [ ] **Step 3: Implement**

Append to `scripts/match/match_config.gd`:

```gdscript
# BET_LOADOUT phase timeout. Sub-project #3 upgrades BET_LOADOUT from a
# no-op pass-through to a real phase with wager input.
const BET_LOADOUT_TIMEOUT_SEC: int = 15

# Rocket Clash: max extra wager = player.chips × this factor. 1.0 means
# a player can wager up to their full chip stack on top of the ante.
const ROCKET_CLASH_MAX_WAGER_FACTOR: float = 1.0

# Rocket Clash: multiplier(t) = exp(ROCKET_GROWTH_RATE × elapsed_sec).
# 0.06/sec gives 2x at ~12s, 5x at ~27s, 10x at ~38s. Tunable.
const ROCKET_GROWTH_RATE: float = 0.06
```

- [ ] **Step 4: Run, watch pass**

Expected: 250/250 tests pass (247 prior + 3 new).

- [ ] **Step 5: Commit**

```
feat(client): MatchConfig constants for Rocket Clash + BET_LOADOUT

BET_LOADOUT_TIMEOUT_SEC (15s): phase timeout for the upgraded BET_LOADOUT
phase.
ROCKET_CLASH_MAX_WAGER_FACTOR (1.0): max extra wager = chips × factor.
ROCKET_GROWTH_RATE (0.06/sec): exponential multiplier growth rate.
EVENT_POOL swap to Rocket Clash deferred to Task 13 when scene wiring
is ready.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 3: EventContext.is_host field

The Rocket Clash event needs to know whether to run host-only logic (compute crash, broadcast launch, validate cash-outs). Adding `is_host` to EventContext is the contract extension noted in spec §11.

**Files:**
- Modify: `scripts/events/event_context.gd`
- Create: `tests/unit/test_event_context_is_host.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_event_context_is_host.gd`:
```gdscript
extends GutTest

const EventContext = preload("res://scripts/events/event_context.gd")

func test_is_host_default_false():
    var ctx = EventContext.new()
    assert_false(ctx.is_host)

func test_is_host_round_trip():
    var ctx = EventContext.new()
    ctx.is_host = true
    ctx.event_index = 2
    ctx.rng_seed = 0xCAFE
    var d = ctx.to_dict()
    var ctx2 = EventContext.from_dict(d)
    assert_true(ctx2.is_host)
    assert_eq(ctx2.event_index, 2)
    assert_eq(ctx2.rng_seed, 0xCAFE)
```

Plus extend the existing `tests/unit/test_event_context.gd` to verify the new field doesn't break existing tests (Plan A's round-trip should still pass; the new field defaults to false).

- [ ] **Step 2: Run, watch fail**

Expected: `is_host` field missing.

- [ ] **Step 3: Implement**

In `scripts/events/event_context.gd`, add the field next to `event_index`:

```gdscript
var players: Array = []
var event_index: int = 0
var rng_seed: int = 0
var wagers: Dictionary = {}
var is_host: bool = false  # NEW: lets the event run host-only logic
```

Update `to_dict`:
```gdscript
func to_dict() -> Dictionary:
    var player_dicts: Array = []
    for p in players:
        player_dicts.append(p.to_dict())
    return {
        "players": player_dicts,
        "event_index": event_index,
        "rng_seed": rng_seed,
        "wagers": wagers,
        "is_host": is_host,
    }
```

Update `from_dict`:
```gdscript
static func from_dict(d: Dictionary) -> RefCounted:
    var c = load("res://scripts/events/event_context.gd").new()
    c.event_index = d.get("event_index", 0)
    c.rng_seed = d.get("rng_seed", 0)
    c.wagers = d.get("wagers", {})
    c.is_host = d.get("is_host", false)
    c.players = []
    for raw in d.get("players", []):
        c.players.append(MatchPlayer.from_dict(raw))
    return c
```

Update `MatchController._build_event_context` to populate the new field:
```gdscript
func _build_event_context():
    var ctx = EventContext.new()
    for p in state.players:
        if p.is_active_this_event:
            ctx.players.append(p)
    ctx.event_index = state.event_index
    ctx.rng_seed = state.rng_seed ^ (state.event_index * 0x9E3779B9)
    ctx.is_host = is_host  # NEW
    # ...existing wagers fill from MatchConfig ante (will be overridden by Task 9)
    var ante = MatchConfig.ANTE_BY_EVENT_INDEX[state.event_index]
    for p in ctx.players:
        ctx.wagers[p.peer_id] = ante
    return ctx
```

- [ ] **Step 4: Run, watch pass**

Expected: 252/252 tests pass (250 prior + 2 new).

- [ ] **Step 5: Commit**

```
feat(client): EventContext.is_host field for event-level host gating

Real events (sub-project #3 onwards) need to run host-only logic
(compute crash, broadcast launch, validate cash-outs). Adding is_host
to EventContext lets the event check ctx.is_host without poking
MatchController's internals. Spec section 11 contract extension.

MatchController._build_event_context populates ctx.is_host from
self.is_host. Field defaults false; round-trips via to_dict/from_dict.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 2: Static math helpers

Three static methods on RocketClashEvent. Pure-math, no scene tree, no controller. The cleanest possible TDD surface.

### Task 4: `compute_crash_at(rng) -> float` (Aviator formula)

Determines the hidden crash multiplier for one round. Seeded RNG → deterministic. 5% instabust at 1.00x; otherwise `max(1.0, 0.99 / (1 - rng.randf()))`, capped at 100.0.

**Files:**
- Create: `scripts/events/rocket_clash/rocket_clash_event.gd` (skeleton with only `compute_crash_at` for now)
- Create: `tests/unit/test_rocket_clash_crash_at.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_rocket_clash_crash_at.gd`:
```gdscript
extends GutTest

const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")

func _seeded_rng(seed_value: int) -> RandomNumberGenerator:
    var rng = RandomNumberGenerator.new()
    rng.seed = seed_value
    return rng

func test_crash_at_deterministic_with_seed():
    var rng1 = _seeded_rng(0xCAFE)
    var rng2 = _seeded_rng(0xCAFE)
    assert_almost_eq(RocketClashEvent.compute_crash_at(rng1), RocketClashEvent.compute_crash_at(rng2), 0.001, "same seed -> same crash")

func test_crash_at_minimum_1_00():
    # Run 500 samples; verify all are >= 1.0
    var rng = _seeded_rng(1)
    for i in 500:
        var c = RocketClashEvent.compute_crash_at(rng)
        assert_true(c >= 1.0, "crash_at must be >= 1.0 (got %f)" % c)

func test_crash_at_capped_at_100():
    var rng = _seeded_rng(1)
    for i in 500:
        var c = RocketClashEvent.compute_crash_at(rng)
        assert_true(c <= 100.0, "crash_at must be <= 100.0 (got %f)" % c)

func test_crash_at_distribution_has_instabust():
    # Verify ~5% of samples hit exactly 1.0 (the instabust gate).
    var rng = _seeded_rng(0xBEEF)
    var instabust_count = 0
    var total = 2000
    for i in total:
        var c = RocketClashEvent.compute_crash_at(rng)
        if abs(c - 1.0) < 0.001:
            instabust_count += 1
    var instabust_rate = float(instabust_count) / float(total)
    # Tolerance band: 5% ± 2% for n=2000
    assert_true(instabust_rate > 0.03 and instabust_rate < 0.07, "instabust rate %f outside [0.03, 0.07]" % instabust_rate)
```

- [ ] **Step 2: Run, watch fail**

Expected: `RocketClashEvent` preload error (file doesn't exist).

- [ ] **Step 3: Implement skeleton + compute_crash_at**

Create `scripts/events/rocket_clash/rocket_clash_event.gd`:
```gdscript
# Rocket Clash event. Validates the EventNode contract with a real-time
# push-your-luck loop: live multiplier, hidden crash, host-authoritative
# cash-out validation. See docs/superpowers/specs/2026-05-12-rocket-clash
# -event-design.md for the full contract.
extends "res://scripts/events/event_node.gd"

const INSTABUST_PROB: float = 0.05
const MAX_CRASH_AT: float = 100.0
const CASH_OUT_TOLERANCE: float = 0.05

# Static helper: deterministic Aviator-style crash distribution from a
# seeded RNG. 5% instabust at 1.00x; otherwise max(1.0, 0.99 / (1 - r))
# capped at MAX_CRASH_AT. Tested without scene instantiation.
static func compute_crash_at(rng: RandomNumberGenerator) -> float:
    var instabust_roll = rng.randf()
    if instabust_roll < INSTABUST_PROB:
        return 1.0
    var r = rng.randf()
    if r >= 0.99:
        return MAX_CRASH_AT
    var crash = 0.99 / (1.0 - r)
    return max(1.0, min(crash, MAX_CRASH_AT))
```

- [ ] **Step 4: Run, watch pass**

Expected: 256/256 tests pass (252 prior + 4 new).

- [ ] **Step 5: Commit**

```
feat(client): RocketClashEvent.compute_crash_at Aviator-style helper

Static deterministic crash distribution. 5% instabust at 1.00x; otherwise
0.99 / (1 - r) with r ~ U[0,1), clamped to [1.0, 100.0]. Distribution
matches design doc section 10.5 shape: ~37% land 1.00-2.00x, ~20% land 5x+,
~3% land 20x+. RNG comes from EventContext.rng_seed (derived per-event
from match seed XOR event_index in MatchController._build_event_context).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 5: `multiplier_at(elapsed_ms, growth_rate) -> float`

The exponential growth formula computed locally on each peer for display sync. Pure math.

**Files:**
- Modify: `scripts/events/rocket_clash/rocket_clash_event.gd`
- Create: `tests/unit/test_rocket_clash_multiplier.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_rocket_clash_multiplier.gd`:
```gdscript
extends GutTest

const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")

func test_multiplier_at_zero_elapsed():
    assert_almost_eq(RocketClashEvent.multiplier_at(0, 0.06), 1.0, 0.001)

func test_multiplier_at_10_seconds():
    # exp(0.06 * 10) = e^0.6 ≈ 1.8221
    assert_almost_eq(RocketClashEvent.multiplier_at(10_000, 0.06), 1.8221, 0.01)

func test_multiplier_monotonic_increasing():
    var prev = 1.0
    for sec in range(1, 60):
        var m = RocketClashEvent.multiplier_at(sec * 1000, 0.06)
        assert_true(m > prev, "monotonic at %ds: %f vs %f" % [sec, m, prev])
        prev = m
```

- [ ] **Step 2: Run, watch fail**

Expected: `multiplier_at` doesn't exist.

- [ ] **Step 3: Implement**

Append to `scripts/events/rocket_clash/rocket_clash_event.gd`:
```gdscript
# Exponential growth: multiplier(t) = exp(growth_rate × elapsed_sec).
# Used by every peer to compute its local display multiplier from the
# host-broadcast start_time_ms. Pure math, no SceneTree dependency.
static func multiplier_at(elapsed_ms: int, growth_rate: float) -> float:
    var elapsed_sec = float(elapsed_ms) / 1000.0
    return exp(growth_rate * elapsed_sec)
```

- [ ] **Step 4: Run, watch pass**

Expected: 259/259 tests pass (256 prior + 3 new).

- [ ] **Step 5: Commit**

```
feat(client): RocketClashEvent.multiplier_at exponential helper

multiplier(t) = exp(growth_rate × elapsed_sec). With growth_rate=0.06,
the rocket reaches 2x at ~12s, 5x at ~27s, 10x at ~38s — matches the
Aviator-class pacing the design doc implies. Pure-math static helper;
unit tests verify monotonicity and concrete values.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 6: `compute_event_result(context, crash_at, cash_outs, busted_ids) -> EventResult`

Builds the EventResult per spec §6.1: per-player chip_delta (survivors gain `wager × cash_out_at`; busts lose `wager`); crown_delta = 1 for the highest-cash-out survivor; painful_reveal with crash_at + cash_outs_summary including each player's name, cash_out_at, chip_delta, busted flag, wager.

**Files:**
- Modify: `scripts/events/rocket_clash/rocket_clash_event.gd`
- Create: `tests/unit/test_rocket_clash_result.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_rocket_clash_result.gd`:
```gdscript
extends GutTest

const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const EventResult = preload("res://scripts/events/event_result.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(peer_id: int, name: String) -> RefCounted:
    var p = MatchPlayer.new()
    p.peer_id = peer_id
    p.name = name
    p.is_active_this_event = true
    return p

func _make_context(player_count: int, wagers: Dictionary) -> RefCounted:
    var ctx = EventContext.new()
    for i in player_count:
        ctx.players.append(_make_player(i + 1, "P%d" % (i + 1)))
    ctx.event_index = 0
    ctx.wagers = wagers
    return ctx

func test_survivor_chip_delta_is_wager_times_cash_out():
    var ctx = _make_context(2, {1: 100, 2: 100})
    var cash_outs = {1: 2.5, 2: 1.5}
    var busted = []
    var result = RocketClashEvent.compute_event_result(ctx, 3.0, cash_outs, busted)
    assert_eq(result.chip_delta_for(1), 250, "P1 cashed at 2.5x with wager 100 -> +250")
    assert_eq(result.chip_delta_for(2), 150, "P2 cashed at 1.5x with wager 100 -> +150")

func test_bust_chip_delta_is_negative_wager():
    var ctx = _make_context(2, {1: 100, 2: 200})
    var cash_outs = {}
    var busted = [1, 2]
    var result = RocketClashEvent.compute_event_result(ctx, 3.0, cash_outs, busted)
    assert_eq(result.chip_delta_for(1), -100, "bust loses wager")
    assert_eq(result.chip_delta_for(2), -200, "bust loses wager")
    assert_true(result.bust_for(1))
    assert_true(result.bust_for(2))

func test_crown_to_highest_cash_out_survivor():
    var ctx = _make_context(3, {1: 100, 2: 100, 3: 100})
    var cash_outs = {1: 1.2, 2: 2.8, 3: 1.5}
    var busted = []
    var result = RocketClashEvent.compute_event_result(ctx, 3.0, cash_outs, busted)
    assert_eq(result.crown_delta_for(2), 1, "P2 has highest cash-out -> 1 Crown")
    assert_eq(result.crown_delta_for(1), 0)
    assert_eq(result.crown_delta_for(3), 0)

func test_no_crown_when_all_bust():
    var ctx = _make_context(2, {1: 100, 2: 100})
    var cash_outs = {}
    var busted = [1, 2]
    var result = RocketClashEvent.compute_event_result(ctx, 1.5, cash_outs, busted)
    assert_eq(result.crown_delta_for(1), 0)
    assert_eq(result.crown_delta_for(2), 0)

func test_painful_reveal_payload_shape():
    var ctx = _make_context(3, {1: 100, 2: 100, 3: 100})
    var cash_outs = {2: 2.20, 3: 1.45}
    var busted = [1]
    var result = RocketClashEvent.compute_event_result(ctx, 3.42, cash_outs, busted)
    var pr = result.painful_reveal
    assert_almost_eq(pr["crash_at"], 3.42, 0.001)
    assert_eq(pr["winner_peer_id"], 2)
    assert_eq(pr["winner_name"], "P2")
    assert_eq(pr["cash_outs_summary"].size(), 3)
    # Sort cash_outs_summary by peer_id for deterministic asserts
    var entries = pr["cash_outs_summary"]
    entries.sort_custom(func(a, b): return a["peer_id"] < b["peer_id"])
    assert_eq(entries[0]["peer_id"], 1)
    assert_eq(entries[0]["busted"], true)
    assert_eq(entries[0]["chip_delta"], -100)
    assert_eq(entries[1]["peer_id"], 2)
    assert_almost_eq(entries[1]["cash_out_at"], 2.20, 0.001)
    assert_eq(entries[1]["chip_delta"], 220)
    assert_eq(entries[1]["busted"], false)
```

- [ ] **Step 2: Run, watch fail**

Expected: `compute_event_result` doesn't exist.

- [ ] **Step 3: Implement**

Append to `scripts/events/rocket_clash/rocket_clash_event.gd`:
```gdscript
const EventResult = preload("res://scripts/events/event_result.gd")

# Builds the EventResult per spec section 6.1. Survivors:
# chip_delta = wager × cash_out_at; bust: false; cash_out_at recorded.
# Busts: chip_delta = -wager; bust: true; cash_out_at = 0.
# Crown: 1 for the survivor with the highest cash_out_at; 0 otherwise.
# painful_reveal payload: crash_at + winner identity + per-player summary.
static func compute_event_result(context, crash_at: float, cash_outs: Dictionary, busted: Array) -> RefCounted:
    var result = EventResult.new()
    result.event_id = "rocket_clash"
    var summary: Array = []
    var winner_peer_id = 0
    var winner_name = ""
    var winner_cash_out = -1.0
    for player in context.players:
        var pid = player.peer_id
        var wager = int(context.wagers.get(pid, 0))
        var entry: Dictionary = {}
        if busted.has(pid):
            result.per_player[pid] = {
                "chip_delta": -wager,
                "crown_delta": 0,
                "heat_delta": 0,
                "bust": true,
                "cash_out_at": 0.0,
            }
            summary.append({
                "peer_id": pid, "name": player.name, "cash_out_at": 0.0,
                "chip_delta": -wager, "busted": true, "wager": wager,
            })
        else:
            var cash_out_at = float(cash_outs.get(pid, 0.0))
            var chip_delta = int(wager * cash_out_at)
            result.per_player[pid] = {
                "chip_delta": chip_delta,
                "crown_delta": 0,
                "heat_delta": 0,
                "bust": false,
                "cash_out_at": cash_out_at,
            }
            summary.append({
                "peer_id": pid, "name": player.name, "cash_out_at": cash_out_at,
                "chip_delta": chip_delta, "busted": false, "wager": wager,
            })
            if cash_out_at > winner_cash_out:
                winner_cash_out = cash_out_at
                winner_peer_id = pid
                winner_name = player.name
    # Award the Crown to the highest-cash-out survivor (if any survived).
    if winner_peer_id != 0:
        result.per_player[winner_peer_id]["crown_delta"] = 1
        # Mirror into the summary entry so the painful_reveal renderer can flag it.
        for e in summary:
            if e["peer_id"] == winner_peer_id:
                e["chip_delta"] = result.per_player[winner_peer_id]["chip_delta"]
                break
    result.painful_reveal = {
        "crash_at": crash_at,
        "winner_peer_id": winner_peer_id,
        "winner_name": winner_name,
        "cash_outs_summary": summary,
    }
    return result
```

- [ ] **Step 4: Run, watch pass**

Expected: 264/264 tests pass (259 prior + 5 new).

- [ ] **Step 5: Commit**

```
feat(client): RocketClashEvent.compute_event_result static helper

Pure-function result builder. Survivors gain wager × cash_out_at chips;
busts lose their wager. Crown to the survivor with the highest cash_out_at
(no Crown if all bust). painful_reveal payload carries crash_at,
winner_peer_id, winner_name, and a per-player cash_outs_summary that
ResolutionOverlay (Task 12) will render. Pure math — no scene tree.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 3: Rocket Clash event runtime

The scene + RPC pipeline. The math from Phase 2 is the brain; this is the body.

### Task 7: RocketClashEvent scene + `_run` host launch

The runtime entry point. Host computes crash_at + start_time_ms, broadcasts `_rpc_rocket_launched`, then `_process(delta)` ticks the local multiplier display until crash. Clients receive the RPC and start their own display loop.

**Files:**
- Modify: `scripts/events/rocket_clash/rocket_clash_event.gd`
- Create: `scripts/events/rocket_clash/rocket_clash_event.tscn`
- Create: `tests/unit/test_rocket_clash_event.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_rocket_clash_event.gd`:
```gdscript
extends GutTest

const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func _build_context(player_count: int, is_host: bool) -> RefCounted:
    var ctx = EventContext.new()
    for i in player_count:
        var p = MatchPlayer.new()
        p.peer_id = i + 1
        p.name = "P%d" % (i + 1)
        p.is_active_this_event = true
        ctx.players.append(p)
        ctx.wagers[p.peer_id] = 100
    ctx.event_index = 0
    ctx.rng_seed = 0xCAFE
    ctx.is_host = is_host
    return ctx

func _new_host_event() -> Dictionary:
    var fake = FakeMultiplayerNode.new()
    var event = RocketClashEvent.new()
    event._multiplayer_node = fake
    add_child_autofree(event)
    return {"event": event, "fake": fake}

func test_get_event_id():
    var e = RocketClashEvent.new()
    assert_eq(e.get_event_id(), "rocket_clash")

func test_run_on_host_broadcasts_rocket_launched():
    var d = _new_host_event()
    var e = d.event
    e._force_crash_at_override = 2.5
    e._run(_build_context(2, true))
    # Verify _rpc_rocket_launched was broadcast (recorded by FakeMultiplayerNode)
    var found = false
    for call in d.fake.rpc_calls:
        if call.method == "_rpc_rocket_launched":
            found = true
            # Args should be [start_time_ms, crash_at=2.5]
            assert_eq(call.args.size(), 2)
            assert_almost_eq(float(call.args[1]), 2.5, 0.001)
            break
    assert_true(found, "host should broadcast _rpc_rocket_launched")

func test_run_on_client_does_not_broadcast():
    var d = _new_host_event()
    var e = d.event
    e._run(_build_context(2, false))  # is_host = false
    # No rocket_launched broadcast from client
    for call in d.fake.rpc_calls:
        assert_ne(call.method, "_rpc_rocket_launched", "client must not broadcast launch")

func test_force_crash_at_override_used_when_set():
    var d = _new_host_event()
    var e = d.event
    e._force_crash_at_override = 7.5
    e._run(_build_context(2, true))
    assert_almost_eq(e._crash_at, 7.5, 0.001)

func test_force_crash_at_override_falls_back_to_rng():
    var d = _new_host_event()
    var e = d.event
    # Default is -1.0; should use RNG
    e._run(_build_context(2, true))
    assert_true(e._crash_at >= 1.0)
    assert_true(e._crash_at <= 100.0)
```

- [ ] **Step 2: Run, watch fail**

Expected: `_run`, `_force_crash_at_override`, `_multiplayer_node`, `_crash_at` missing.

- [ ] **Step 3: Implement RocketClashEvent runtime**

Update `scripts/events/rocket_clash/rocket_clash_event.gd`:
```gdscript
# (Existing static helpers from Tasks 4-6 stay at top of file.)

# Per-round state
var _crash_at: float = 0.0
var _start_time_ms: int = 0
var _cash_outs: Dictionary = {}
var _active_peers: Array = []
var _is_host: bool = false
var _finished: bool = false
var _rng: RandomNumberGenerator = null

# RPC routing (mirror of MatchController's pattern). Tests inject
# FakeMultiplayerNode; production self-wires via the same pattern.
var _multiplayer_node = null

# Test seams
var _force_crash_at_override: float = -1.0  # negative = use RNG
var _growth_rate_override: float = -1.0     # negative = use MatchConfig

# Scene-tree refs (resolved in _ready)
@onready var _multiplier_label: Label = $VBox/MultiplierLabel if has_node("VBox/MultiplierLabel") else null
@onready var _cash_out_button: Button = $VBox/CashOutButton if has_node("VBox/CashOutButton") else null

const MatchConfig = preload("res://scripts/match/match_config.gd")

func get_event_id() -> String:
    return "rocket_clash"

func _run(context) -> void:
    _is_host = context.is_host
    _active_peers = []
    for p in context.players:
        _active_peers.append(p.peer_id)
    _rng = RandomNumberGenerator.new()
    _rng.seed = context.rng_seed
    if not _is_host:
        return  # client waits for _rpc_rocket_launched
    # Production self-wire: if no injection and we're in tree, route via self.
    if _multiplayer_node == null and is_inside_tree():
        _multiplayer_node = self
    # Compute crash_at deterministically.
    if _force_crash_at_override >= 1.0:
        _crash_at = _force_crash_at_override
    else:
        _crash_at = compute_crash_at(_rng)
    _start_time_ms = Time.get_ticks_msec()
    _send_rpc("_rpc_rocket_launched", [_start_time_ms, _crash_at])
    # Host also processes the rocket locally as if it received the broadcast.
    _on_rocket_launched_local(_start_time_ms, _crash_at)

func _send_rpc(method_name: String, args: Array = []) -> void:
    if _multiplayer_node == null:
        return
    match args.size():
        0: _multiplayer_node.rpc(method_name)
        1: _multiplayer_node.rpc(method_name, args[0])
        2: _multiplayer_node.rpc(method_name, args[0], args[1])
        3: _multiplayer_node.rpc(method_name, args[0], args[1], args[2])

func _on_rocket_launched_local(start_time_ms: int, crash_at: float) -> void:
    _start_time_ms = start_time_ms
    _crash_at = crash_at
    set_process(true)

func _process(_delta: float) -> void:
    if _finished or _start_time_ms == 0:
        return
    var elapsed_ms = Time.get_ticks_msec() - _start_time_ms
    var growth = _growth_rate_override if _growth_rate_override >= 0.0 else MatchConfig.ROCKET_GROWTH_RATE
    var mult = multiplier_at(elapsed_ms, growth)
    if _multiplier_label != null:
        _multiplier_label.text = "%.2fx" % mult
    if _is_host and mult >= _crash_at and not _finished:
        _finish()

func _finish() -> void:
    _finished = true
    set_process(false)
    # Build busted list = active peers who never cashed out
    var busted: Array = []
    for pid in _active_peers:
        if not _cash_outs.has(pid):
            busted.append(pid)
    # Context-equivalent for compute_event_result needs the original players;
    # we reconstruct a minimal view from _active_peers (since the event holds
    # MatchPlayer refs in context.players passed to _run, but we discarded the
    # ref). Workaround: stash context for _finish.
    var result = compute_event_result(_stashed_context, _crash_at, _cash_outs, busted)
    event_complete.emit(result)

# Add at the top with the other state fields:
var _stashed_context = null

# In _run, stash the context before returning (replace earlier `if not _is_host: return`):
```

Update `_run`:
```gdscript
func _run(context) -> void:
    _stashed_context = context
    _is_host = context.is_host
    # ...rest unchanged
```

Add `@rpc` receivers for `_rpc_rocket_launched` (Tasks 8 adds cash-out RPCs):
```gdscript
@rpc("authority", "call_remote", "reliable")
func _rpc_rocket_launched(start_time_ms: int, crash_at: float) -> void:
    _on_rocket_launched_local(start_time_ms, crash_at)
```

Create `scripts/events/rocket_clash/rocket_clash_event.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/events/rocket_clash/rocket_clash_event.gd" id="1"]

[node name="RocketClashEvent" type="Node"]
script = ExtResource("1")

[node name="VBox" type="VBoxContainer" parent="."]

[node name="MultiplierLabel" type="Label" parent="VBox"]
text = "1.00x"

[node name="StatusGrid" type="HBoxContainer" parent="VBox"]

[node name="CashOutButton" type="Button" parent="VBox"]
text = "Cash Out"
```

- [ ] **Step 4: Run, watch pass**

Expected: 269/269 tests pass (264 prior + 5 new).

- [ ] **Step 5: Commit**

```
feat(client): RocketClashEvent scene + host launch flow

Scene tree (Node root → VBox containing MultiplierLabel, StatusGrid,
CashOutButton) extends event_node.gd. Host _run picks crash_at from
RNG (or _force_crash_at_override test seam), captures start_time_ms,
broadcasts _rpc_rocket_launched, and starts the local _process loop
that ticks the multiplier display via the multiplier_at static helper.
Clients await the RPC. Both sides use the same _multiplier_label
update path.

_send_rpc mirror of MatchController pattern with the same Fake
MultiplayerNode test injection. _growth_rate_override test seam lets
unit/integration tests compress timing without affecting production.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 8: Cash-out RPC pipeline

Client → host cash-out request, host validation (tolerance + crash-already-fired + double-click guards), host → all confirm / host → originator reject.

**Files:**
- Modify: `scripts/events/rocket_clash/rocket_clash_event.gd`
- Modify: `tests/unit/test_rocket_clash_event.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_rocket_clash_event.gd`:
```gdscript
func test_cash_out_within_tolerance_accepted():
    var d = _new_host_event()
    var e = d.event
    e._force_crash_at_override = 5.0
    e._run(_build_context(2, true))
    # Manually set host's current multiplier reading to 2.0 by simulating elapsed
    # time. The simplest test path: directly call _rpc_cash_out_requested with a
    # snapshot near what the host sees. Use _force_current_mult_for_testing.
    e._force_current_mult_for_testing = 2.0
    e._rpc_cash_out_requested(2, 2.01)  # within 0.05 tolerance
    var confirmed = false
    for call in d.fake.rpc_calls:
        if call.method == "_rpc_cash_out_confirmed":
            confirmed = true
            assert_eq(call.args[0], 2, "confirmed peer_id")
            assert_almost_eq(float(call.args[1]), 2.0, 0.001, "host's authoritative mult")
            break
    assert_true(confirmed)
    assert_true(e._cash_outs.has(2))

func test_cash_out_out_of_tolerance_rejected():
    var d = _new_host_event()
    var e = d.event
    e._force_crash_at_override = 5.0
    e._run(_build_context(2, true))
    e._force_current_mult_for_testing = 2.0
    e._rpc_cash_out_requested(2, 2.50)  # >0.05 off
    var rejected = false
    for call in d.fake.rpc_calls:
        if call.method == "_rpc_cash_out_rejected":
            rejected = true
            assert_eq(call.args[0], 2)
            break
    assert_true(rejected)
    assert_false(e._cash_outs.has(2))

func test_double_cash_out_silently_dropped():
    var d = _new_host_event()
    var e = d.event
    e._force_crash_at_override = 5.0
    e._run(_build_context(2, true))
    e._force_current_mult_for_testing = 2.0
    e._rpc_cash_out_requested(2, 2.0)  # first: accepted
    var first_count = d.fake.rpc_calls.size()
    e._rpc_cash_out_requested(2, 2.0)  # second: silently dropped
    # No new RPC broadcasts
    assert_eq(d.fake.rpc_calls.size(), first_count, "duplicate cash-out silently dropped")
```

- [ ] **Step 2: Run, watch fail**

Expected: `_rpc_cash_out_requested`, `_force_current_mult_for_testing` missing.

- [ ] **Step 3: Implement**

Add to `scripts/events/rocket_clash/rocket_clash_event.gd`:
```gdscript
# Test seam: force a specific "current multiplier" for cash-out validation
# tests instead of computing from elapsed time. Negative = use real elapsed.
var _force_current_mult_for_testing: float = -1.0

func _current_multiplier_host() -> float:
    if _force_current_mult_for_testing >= 0.0:
        return _force_current_mult_for_testing
    var elapsed_ms = Time.get_ticks_msec() - _start_time_ms
    var growth = _growth_rate_override if _growth_rate_override >= 0.0 else MatchConfig.ROCKET_GROWTH_RATE
    return multiplier_at(elapsed_ms, growth)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_cash_out_requested(peer_id: int, snapshot_mult: float) -> void:
    if not _is_host:
        return  # only host validates
    if _finished:
        # Crash already fired; this cash-out arrived too late.
        _send_rpc_to_peer(peer_id, "_rpc_cash_out_rejected", [peer_id])
        return
    if _cash_outs.has(peer_id):
        # Double-click; silently drop.
        return
    var host_mult = _current_multiplier_host()
    if abs(snapshot_mult - host_mult) > CASH_OUT_TOLERANCE:
        _send_rpc_to_peer(peer_id, "_rpc_cash_out_rejected", [peer_id])
        return
    _cash_outs[peer_id] = host_mult
    _send_rpc("_rpc_cash_out_confirmed", [peer_id, host_mult])

@rpc("authority", "call_remote", "reliable")
func _rpc_cash_out_confirmed(peer_id: int, accepted_mult: float) -> void:
    # Mirrored to all peers for HUD update. Host already updated _cash_outs.
    if not _is_host:
        _cash_outs[peer_id] = accepted_mult

@rpc("authority", "call_remote", "reliable")
func _rpc_cash_out_rejected(_peer_id: int) -> void:
    # Local UI hook only; data already correct on host.
    pass

# Targeted send (for rejecting back to the originator only).
func _send_rpc_to_peer(peer_id: int, method_name: String, args: Array) -> void:
    if _multiplayer_node == null:
        return
    match args.size():
        0: _multiplayer_node.rpc_id(peer_id, method_name)
        1: _multiplayer_node.rpc_id(peer_id, method_name, args[0])
        2: _multiplayer_node.rpc_id(peer_id, method_name, args[0], args[1])
```

Extend FakeMultiplayerNode to support `rpc_id`. In `tests/fakes/fake_multiplayer_node.gd`:
```gdscript
func rpc_id(peer_id: int, method: StringName, p1=null, p2=null, p3=null, p4=null) -> int:
    var args: Array = []
    if p1 != null: args.append(p1)
    if p2 != null: args.append(p2)
    if p3 != null: args.append(p3)
    if p4 != null: args.append(p4)
    rpc_calls.append({"method": String(method), "peer_id": peer_id, "args": args})
    return OK
```

- [ ] **Step 4: Run, watch pass**

Expected: 272/272 tests pass (269 prior + 3 new).

- [ ] **Step 5: Commit**

```
feat(client): RocketClashEvent cash-out RPC pipeline

Three @rpc methods: _rpc_cash_out_requested (any_peer, call_remote;
client→host), _rpc_cash_out_confirmed (authority, call_remote; host→all),
_rpc_cash_out_rejected (authority, call_remote; host→originator). Host
validates per spec section 5.2: rejects if crash already fired, silently
drops duplicates, rejects out-of-tolerance snapshots (> 0.05 off
host's current multiplier).

FakeMultiplayerNode gains rpc_id recording for targeted send testing.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 4: BET_LOADOUT phase upgrade

The phase that was a no-op pass-through is now a real wager-input phase. Two tasks: the wager RPC pipeline (state + RPC handlers), then the phase handler itself (with timer + fast-advance).

### Task 9: MatchState.pending_wagers + wager RPC pipeline

Adds the state field, the `submit_wager` public method, the `@rpc _rpc_set_wager` receiver, the `@rpc _rpc_wager_acknowledged` broadcast, and the `_build_event_context` priority so pending_wagers replaces the ante fallback.

**Files:**
- Modify: `scripts/match/match_state.gd`
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_wager_pipeline.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_controller_wager_pipeline.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func _build_match_start(player_count: int) -> RefCounted:
    var ms = MatchStart.new()
    for i in player_count:
        var s = PlayerSlot.new()
        s.peer_id = i + 1; s.seat_index = i; s.name = "P%d" % (i + 1)
        ms.seats.append(s)
    ms.host_peer_id = 1; ms.rng_seed = 1
    return ms

func _new_host_with_fake() -> Dictionary:
    var fake = FakeMultiplayerNode.new()
    var c = MatchController.new(true, fake)
    c.no_op_phase_delay_ms_override = 0
    c.start_match(_build_match_start(2))
    return {"controller": c, "fake": fake}

func test_pending_wagers_default_empty():
    var s = MatchState.new()
    assert_eq(s.pending_wagers, {})

func test_pending_wagers_round_trip():
    var s = MatchState.new()
    s.pending_wagers = {1: 200, 2: 0}
    var d = s.to_dict()
    var s2 = MatchState.from_dict(d)
    assert_eq(s2.pending_wagers.get(1, -1), 200)
    assert_eq(s2.pending_wagers.get(2, -1), 0)

func test_rpc_set_wager_clamps_to_chips():
    var d = _new_host_with_fake()
    var c = d.controller
    # P1 has 800 chips - 25 ante = 775; player chip lookup uses post-ante chips
    var p1_chips = c.state.players[0].chips
    c._rpc_set_wager(1, p1_chips + 5000)  # over
    assert_eq(c.state.pending_wagers[1], p1_chips, "wager clamped to chip count")

func test_rpc_set_wager_broadcasts_acknowledged():
    var d = _new_host_with_fake()
    d.fake.rpc_calls.clear()
    d.controller._rpc_set_wager(1, 50)
    var found = false
    for call in d.fake.rpc_calls:
        if call.method == "_rpc_wager_acknowledged":
            found = true
            assert_eq(call.args[0], 1)
            assert_eq(call.args[1], 50)
            break
    assert_true(found)

func test_build_event_context_reads_pending_wagers():
    var d = _new_host_with_fake()
    var c = d.controller
    c.state.pending_wagers = {1: 300, 2: 0}
    var ctx = c._build_event_context()
    assert_eq(ctx.wagers.get(1, -1), 300)
    assert_eq(ctx.wagers.get(2, -1), 0)
```

- [ ] **Step 2: Run, watch fail**

Expected: `pending_wagers`, `_rpc_set_wager` missing.

- [ ] **Step 3: Implement**

In `scripts/match/match_state.gd`, add field + round-trip:
```gdscript
var pending_wagers: Dictionary = {}

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
        "pending_wagers": pending_wagers.duplicate(true),
    }

static func from_dict(d: Dictionary) -> RefCounted:
    var s = load("res://scripts/match/match_state.gd").new()
    s.event_index = d.get("event_index", 0)
    s.phase = d.get("phase", MatchPhase.Phase.HOUSE_REVEAL)
    s.current_event_id = d.get("current_event_id", "")
    s.rng_seed = d.get("rng_seed", 0)
    s.pending_wagers = d.get("pending_wagers", {}).duplicate(true)
    s.players = []
    for raw in d.get("players", []):
        s.players.append(MatchPlayer.from_dict(raw))
    return s
```

In `scripts/match/match_controller.gd`, add the wager pipeline (place near _send_rpc):

```gdscript
# Public: called locally by BetLoadoutOverlay's Ready handler.
func submit_wager(amount: int) -> void:
    var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
    _send_rpc("_rpc_set_wager", [my_peer_id, amount])

@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_wager(peer_id: int, amount: int) -> void:
    if not is_host:
        return
    var player = state.find_player(peer_id)
    if player == null:
        return
    var clamped = clamp(amount, 0, player.chips)
    state.pending_wagers[peer_id] = clamped
    _send_rpc("_rpc_wager_acknowledged", [peer_id, clamped])

@rpc("authority", "call_remote", "reliable")
func _rpc_wager_acknowledged(_peer_id: int, _amount: int) -> void:
    # Re-emits a local signal for BetLoadoutOverlay to update readied state.
    wager_acknowledged.emit(_peer_id, _amount)
```

Add the signal near the other signals:
```gdscript
signal wager_acknowledged(peer_id: int, amount: int)
```

Update `_build_event_context` to prioritize `state.pending_wagers`:
```gdscript
func _build_event_context():
    var ctx = EventContext.new()
    for p in state.players:
        if p.is_active_this_event:
            ctx.players.append(p)
    ctx.event_index = state.event_index
    ctx.rng_seed = state.rng_seed ^ (state.event_index * 0x9E3779B9)
    ctx.is_host = is_host
    if not state.pending_wagers.is_empty():
        for p in ctx.players:
            ctx.wagers[p.peer_id] = state.pending_wagers.get(p.peer_id, 0)
    else:
        var ante = MatchConfig.ANTE_BY_EVENT_INDEX[state.event_index]
        for p in ctx.players:
            ctx.wagers[p.peer_id] = ante
    return ctx
```

- [ ] **Step 4: Run, watch pass**

Expected: 277/277 tests pass (272 prior + 5 new).

- [ ] **Step 5: Commit**

```
feat(client): MatchController wager pipeline + state.pending_wagers

MatchState gains a pending_wagers Dictionary field (round-tripped via
to_dict/from_dict). MatchController gains submit_wager(amount), the
@rpc _rpc_set_wager receiver (clamps to chips, broadcasts ack), and
the wager_acknowledged signal that BetLoadoutOverlay subscribes to.

_build_event_context now reads state.pending_wagers when non-empty,
falling back to the existing ante-only behavior so Plan A's tests
continue to pass without changes. Plan B's tests continue to pass
because no test sets pending_wagers.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 10: BET_LOADOUT phase handler

The new `_process_bet_loadout` that emits `bet_loadout_started`, waits for either timer-expiry or "all active peers ready", then emits `bet_loadout_finished`. Wires into `_enter_phase_behavior`.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_bet_loadout.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_controller_bet_loadout.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")
const MockEvent = preload("res://tests/fakes/mock_event.gd")

func _build_match_start(player_count: int) -> RefCounted:
    var ms = MatchStart.new()
    for i in player_count:
        var s = PlayerSlot.new()
        s.peer_id = i + 1; s.seat_index = i; s.name = "P%d" % (i + 1)
        ms.seats.append(s)
    ms.host_peer_id = 1; ms.rng_seed = 1
    return ms

func _new_synchronous_controller() -> MatchController:
    var c = MatchController.new(true, null)
    c.no_op_phase_delay_ms_override = 0
    c.bet_loadout_timeout_sec_override = 0.0
    var mock = MockEvent.new()
    c._event_factory = func(_path): return mock
    c.start_match(_build_match_start(2))
    return c

func test_bet_loadout_emits_started_signal():
    var c = _new_synchronous_controller()
    add_child_autofree(c)
    var started_payload: Array = []
    c.bet_loadout_started.connect(func(active, max_per): started_payload = [active, max_per])
    c.state.phase = MatchPhase.Phase.BET_LOADOUT
    c._enter_phase_behavior()
    await get_tree().process_frame
    assert_eq(started_payload.size(), 2, "bet_loadout_started fired")
    assert_eq(started_payload[0].size(), 2, "two active peers")

func test_bet_loadout_clears_pending_wagers_on_entry():
    var c = _new_synchronous_controller()
    add_child_autofree(c)
    c.state.pending_wagers = {1: 500}  # leftover
    c.state.phase = MatchPhase.Phase.BET_LOADOUT
    c._enter_phase_behavior()
    await get_tree().process_frame
    # After bet_loadout_started, pending_wagers should be cleared so this
    # phase starts fresh
    assert_eq(c.state.pending_wagers, {})

func test_bet_loadout_fast_advances_when_all_ready():
    var c = _new_synchronous_controller()
    c.bet_loadout_timeout_sec_override = 60.0  # slow timer
    add_child_autofree(c)
    var finished = false
    c.bet_loadout_finished.connect(func(): finished = true)
    c.state.phase = MatchPhase.Phase.BET_LOADOUT
    c._enter_phase_behavior()
    await get_tree().process_frame
    # Submit wagers for both active peers
    c._rpc_set_wager(1, 100)
    c._rpc_set_wager(2, 100)
    # Give the polling loop a frame to detect "all ready"
    await get_tree().process_frame
    await get_tree().process_frame
    assert_true(finished, "phase should advance once all active peers submit")

func test_bet_loadout_advances_on_timeout_with_missing_wagers():
    var c = _new_synchronous_controller()
    c.bet_loadout_timeout_sec_override = 0.05  # 50ms
    add_child_autofree(c)
    var finished = false
    c.bet_loadout_finished.connect(func(): finished = true)
    c.state.phase = MatchPhase.Phase.BET_LOADOUT
    c._enter_phase_behavior()
    await get_tree().create_timer(0.2).timeout
    assert_true(finished, "timer expired -> bet_loadout_finished fired")
```

- [ ] **Step 2: Run, watch fail**

Expected: `_process_bet_loadout`, `bet_loadout_started`, `bet_loadout_finished`, `bet_loadout_timeout_sec_override` missing.

- [ ] **Step 3: Implement**

In `scripts/match/match_controller.gd`, add the signals + test seam:
```gdscript
signal bet_loadout_started(active_peer_ids: Array, max_per_player: int)
signal bet_loadout_finished

# Test seam: override BET_LOADOUT phase timeout (mirror of event_timeout pattern)
var bet_loadout_timeout_sec_override: float = -1.0

func _bet_loadout_timeout_sec() -> float:
    if bet_loadout_timeout_sec_override >= 0.0:
        return bet_loadout_timeout_sec_override
    return float(MatchConfig.BET_LOADOUT_TIMEOUT_SEC)
```

Add the handler:
```gdscript
func _process_bet_loadout() -> void:
    if not is_host:
        return
    state.pending_wagers = {}
    var active_peer_ids: Array = []
    var max_per_player: int = 0
    for p in state.players:
        if p.is_active_this_event:
            active_peer_ids.append(p.peer_id)
            max_per_player = max(max_per_player, int(p.chips * MatchConfig.ROCKET_CLASH_MAX_WAGER_FACTOR))
    bet_loadout_started.emit(active_peer_ids, max_per_player)
    var timeout_sec = _bet_loadout_timeout_sec()
    if timeout_sec <= 0.0:
        # Test path: bypass timer entirely
        bet_loadout_finished.emit()
        return
    if not is_inside_tree():
        # Detached controller: no SceneTree to create timer
        bet_loadout_finished.emit()
        return
    var timer = get_tree().create_timer(timeout_sec)
    while timer.time_left > 0.0:
        if _all_active_ready(active_peer_ids):
            break
        await get_tree().process_frame
    bet_loadout_finished.emit()

func _all_active_ready(active_peer_ids: Array) -> bool:
    for pid in active_peer_ids:
        if not state.pending_wagers.has(pid):
            return false
    return true
```

Wire BET_LOADOUT into `_enter_phase_behavior` (replacing the existing no-op):
```gdscript
match state.phase:
    # ...
    MatchPhase.Phase.BET_LOADOUT:
        await _process_bet_loadout()
        await _schedule_advance()
    # ...
```

- [ ] **Step 4: Run, watch pass**

Expected: 281/281 tests pass (277 prior + 4 new).

- [ ] **Step 5: Commit**

```
feat(client): MatchController BET_LOADOUT phase upgrade

_process_bet_loadout (async) clears pending_wagers on entry, emits
bet_loadout_started(active_peer_ids, max_per_player), then polls every
frame for either (a) all active peers ready (fast-advance) or (b)
BET_LOADOUT_TIMEOUT_SEC timer expiry. Emits bet_loadout_finished on
exit. Detached-controller test path and override=0 path short-circuit
synchronously.

The BET_LOADOUT branch in _enter_phase_behavior now awaits
_process_bet_loadout and then _schedule_advance, replacing the prior
no-op pass-through. Plan A's BET_LOADOUT test
(test_bet_loadout_auto_advances_to_main_event) continues to pass
because it sets phase directly and the synchronous test path advances
immediately.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 5: UI widgets

### Task 11: BetLoadoutOverlay widget

The wager-input widget shown during BET_LOADOUT. Static formatter `format_wager_summary` + `clamp_wager` for unit tests; scene wiring exercised in the integration test and playtest.

**Files:**
- Create: `scripts/ui/bet_loadout_overlay.gd`
- Create: `scenes/ui/bet_loadout_overlay.tscn`
- Create: `tests/unit/test_bet_loadout_overlay.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_bet_loadout_overlay.gd`:
```gdscript
extends GutTest

const BetLoadoutOverlay = preload("res://scripts/ui/bet_loadout_overlay.gd")

func test_format_wager_summary_zero():
    assert_eq(BetLoadoutOverlay.format_wager_summary(800, 0), "Wager: 0 (Chips: 800)")

func test_format_wager_summary_partial():
    assert_eq(BetLoadoutOverlay.format_wager_summary(800, 200), "Wager: 200 (Chips: 800)")

func test_clamp_wager_within_range():
    assert_eq(BetLoadoutOverlay.clamp_wager(200, 800, 1.0), 200)

func test_clamp_wager_negative_to_zero():
    assert_eq(BetLoadoutOverlay.clamp_wager(-50, 800, 1.0), 0)

func test_clamp_wager_above_max_to_max():
    assert_eq(BetLoadoutOverlay.clamp_wager(5000, 800, 1.0), 800)
    assert_eq(BetLoadoutOverlay.clamp_wager(5000, 800, 0.5), 400)
```

- [ ] **Step 2: Run, watch fail**

Expected: `BetLoadoutOverlay` script doesn't exist.

- [ ] **Step 3: Implement script**

`scripts/ui/bet_loadout_overlay.gd`:
```gdscript
# Wager-input widget shown during BET_LOADOUT phase. Listens to
# MatchController.bet_loadout_started / bet_loadout_finished. Renders
# the local player's chips, a slider 0..max, a Ready button, and a
# countdown. On Ready, calls controller.submit_wager(amount).
extends PanelContainer

const MatchConfig = preload("res://scripts/match/match_config.gd")

@onready var _title_label: Label = $VBox/TitleLabel if has_node("VBox/TitleLabel") else null
@onready var _wager_slider: HSlider = $VBox/WagerSlider if has_node("VBox/WagerSlider") else null
@onready var _wager_spin: SpinBox = $VBox/WagerSpin if has_node("VBox/WagerSpin") else null
@onready var _ready_button: Button = $VBox/ReadyButton if has_node("VBox/ReadyButton") else null
@onready var _summary_label: Label = $VBox/SummaryLabel if has_node("VBox/SummaryLabel") else null

var controller  # MatchController-like (set by MatchScene)
var local_player  # MatchPlayer-like

func _ready() -> void:
    visible = false
    if controller != null:
        controller.bet_loadout_started.connect(_on_started)
        controller.bet_loadout_finished.connect(_on_finished)
    if _ready_button != null:
        _ready_button.pressed.connect(_on_ready_pressed)
    if _wager_slider != null and _wager_spin != null:
        _wager_slider.value_changed.connect(_on_slider_changed)
        _wager_spin.value_changed.connect(_on_spin_changed)

func _on_started(_active_peer_ids: Array, max_per_player: int) -> void:
    visible = true
    if local_player != null:
        if _wager_slider != null:
            _wager_slider.min_value = 0
            _wager_slider.max_value = max_per_player
            _wager_slider.value = 0
        if _wager_spin != null:
            _wager_spin.min_value = 0
            _wager_spin.max_value = max_per_player
            _wager_spin.value = 0
        _refresh_summary()

func _on_finished() -> void:
    visible = false

func _on_slider_changed(value: float) -> void:
    if _wager_spin != null and _wager_spin.value != value:
        _wager_spin.value = value
    _refresh_summary()

func _on_spin_changed(value: float) -> void:
    if _wager_slider != null and _wager_slider.value != value:
        _wager_slider.value = value
    _refresh_summary()

func _on_ready_pressed() -> void:
    if controller == null:
        return
    var amount = int(_wager_slider.value) if _wager_slider != null else 0
    controller.submit_wager(amount)
    if _ready_button != null:
        _ready_button.disabled = true

func _refresh_summary() -> void:
    if _summary_label == null or local_player == null:
        return
    var amount = int(_wager_slider.value) if _wager_slider != null else 0
    _summary_label.text = format_wager_summary(local_player.chips, amount)

# Static formatters (testable)
static func format_wager_summary(chips: int, wager: int) -> String:
    return "Wager: %d (Chips: %d)" % [wager, chips]

static func clamp_wager(amount: int, chips: int, max_factor: float) -> int:
    var cap = int(chips * max_factor)
    return clamp(amount, 0, cap)
```

- [ ] **Step 4: Implement scene**

`scenes/ui/bet_loadout_overlay.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/bet_loadout_overlay.gd" id="1"]

[node name="BetLoadoutOverlay" type="PanelContainer"]
script = ExtResource("1")

[node name="VBox" type="VBoxContainer" parent="."]

[node name="TitleLabel" type="Label" parent="VBox"]
text = "Place your wager"

[node name="WagerSlider" type="HSlider" parent="VBox"]
min_value = 0.0
max_value = 800.0
step = 1.0

[node name="WagerSpin" type="SpinBox" parent="VBox"]
min_value = 0.0
max_value = 800.0
step = 1.0

[node name="ReadyButton" type="Button" parent="VBox"]
text = "Ready"

[node name="SummaryLabel" type="Label" parent="VBox"]
text = "Wager: 0 (Chips: 0)"
```

- [ ] **Step 5: Run, watch pass**

Expected: 286/286 tests pass (281 prior + 5 new).

- [ ] **Step 6: Commit**

```
feat(client): BetLoadoutOverlay widget for BET_LOADOUT phase

PanelContainer that subscribes to MatchController.bet_loadout_started /
bet_loadout_finished. Renders a slider + spin box (synced), a Ready
button, and a summary label. On Ready, calls controller.submit_wager
which fires the _rpc_set_wager pipeline from Task 9.

Static formatters format_wager_summary and clamp_wager are unit-tested
without scene instantiation. MatchScene wiring lands in Task 13.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 12: ResolutionOverlay painful_reveal Rocket Clash extension

Extends the existing `format_resolution_step("painful_reveal", ...)` branch with a Rocket-Clash-aware path when the payload has `crash_at` + `cash_outs_summary`. Falls back to the existing TestEvent format when those keys are absent.

**Files:**
- Modify: `scripts/ui/resolution_overlay.gd`
- Modify: `tests/unit/test_resolution_overlay.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_resolution_overlay.gd`:
```gdscript
func test_format_painful_reveal_rocket_clash_includes_crash_at():
    var payload = {
        "crash_at": 3.42,
        "winner_peer_id": 2,
        "winner_name": "Maya",
        "cash_outs_summary": [
            {"peer_id": 1, "name": "Alex", "cash_out_at": 0.0, "chip_delta": -100, "busted": true, "wager": 100},
            {"peer_id": 2, "name": "Maya", "cash_out_at": 2.20, "chip_delta": 220, "busted": false, "wager": 100},
        ]
    }
    var s = ResolutionOverlay.format_resolution_step("painful_reveal", payload)
    assert_true(s.contains("3.42"))
    assert_true(s.contains("Maya"))
    assert_true(s.contains("Alex"))
    assert_true(s.contains("busted"))

func test_format_painful_reveal_rocket_clash_flags_winner():
    var payload = {
        "crash_at": 3.42,
        "winner_peer_id": 2,
        "winner_name": "Maya",
        "cash_outs_summary": [
            {"peer_id": 2, "name": "Maya", "cash_out_at": 2.20, "chip_delta": 220, "busted": false, "wager": 100},
        ]
    }
    var s = ResolutionOverlay.format_resolution_step("painful_reveal", payload)
    # Winner indicated somewhere (Crown emoji or text marker)
    assert_true(s.contains("Crown") or s.contains("👑"))

func test_format_painful_reveal_falls_back_without_crash_at():
    # TestEvent / minimal payload: just winner_name + winner_peer_id
    var payload = {"winner_peer_id": 2, "winner_name": "Maya"}
    var s = ResolutionOverlay.format_resolution_step("painful_reveal", payload)
    assert_true(s.contains("Maya"))
    # Should NOT include rocket-specific text
    assert_false(s.contains("CRASH"))
```

- [ ] **Step 2: Run, watch fail**

Expected: tests fail because the existing painful_reveal formatter doesn't handle `cash_outs_summary`.

- [ ] **Step 3: Implement**

In `scripts/ui/resolution_overlay.gd`, update the `format_resolution_step` "painful_reveal" branch:
```gdscript
"painful_reveal":
    # Rocket Clash extended payload (also fits future events that follow
    # the cash_outs_summary contract from spec section 11).
    if payload.has("crash_at") and payload.has("cash_outs_summary"):
        return _format_painful_reveal_rocket(payload)
    # Existing TestEvent fallback (winner_peer_id + optional winner_name only)
    var winner_name = payload.get("winner_name", "")
    var winner_pid = payload.get("winner_peer_id", 0)
    if winner_name != "":
        return "Painful reveal: %s wins the event." % winner_name
    return "Painful reveal: P%d wins." % winner_pid
```

Add the helper static:
```gdscript
static func _format_painful_reveal_rocket(payload: Dictionary) -> String:
    var lines: Array = []
    var crash_at = float(payload.get("crash_at", 1.0))
    lines.append("CRASH! Rocket exploded at %.2fx" % crash_at)
    var winner_pid = int(payload.get("winner_peer_id", 0))
    var summary = payload.get("cash_outs_summary", [])
    for entry in summary:
        var name = String(entry.get("name", ""))
        if entry.get("busted", false):
            var wager = int(entry.get("wager", 0))
            lines.append("  %s busted (left %d chips on the table)" % [name, wager])
        else:
            var cash_out = float(entry.get("cash_out_at", 0.0))
            var chip_delta = int(entry.get("chip_delta", 0))
            var crown = " 👑 Crown" if int(entry.get("peer_id", -1)) == winner_pid else ""
            lines.append("  %s %.2fx +%d chips%s" % [name, cash_out, chip_delta, crown])
    return "\n".join(lines)
```

- [ ] **Step 4: Run, watch pass**

Expected: 289/289 tests pass (286 prior + 3 new). Plan B's existing `test_format_painful_reveal_with_winner` continues to pass because the fallback path is preserved.

- [ ] **Step 5: Commit**

```
feat(client): ResolutionOverlay painful_reveal Rocket Clash extension

Extends format_resolution_step("painful_reveal", payload) with a
Rocket-Clash-aware path when the payload has crash_at + cash_outs_summary
keys. Renders multi-line readout with crash multiplier, per-player
cash-out + chip delta, bust labels, and a Crown indicator on the winner.
Falls back to the existing TestEvent format (winner-name single line)
when those keys are absent — so Plan B's tests stay green and other
events can use the minimal payload.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 6: Wiring + Integration

### Task 13: MatchScene BetLoadoutSlot wiring + EVENT_POOL swap

Wires the BET_LOADOUT signals into MatchScene so the overlay appears/disappears, and swaps the EVENT_POOL from TestEvent to Rocket Clash so real matches run the real event.

**Files:**
- Modify: `scripts/ui/match_scene.gd`
- Modify: `scenes/match_scene.tscn`
- Modify: `scripts/match/match_config.gd`

- [ ] **Step 1: Update the existing EVENT_POOL test (regression guard)**

Plan A's Task 4 added `test_event_pool_contains_test_event` in `tests/unit/test_match_config.gd`. After this task swaps the pool, that assertion fails. Update the test to expect Rocket Clash instead:

In `tests/unit/test_match_config.gd`, replace:
```gdscript
func test_event_pool_contains_test_event():
    assert_true(MatchConfig.EVENT_POOL.has("res://scripts/events/test_event/test_event.tscn"))
```

with:
```gdscript
func test_event_pool_contains_rocket_clash():
    assert_true(MatchConfig.EVENT_POOL.has("res://scripts/events/rocket_clash/rocket_clash_event.tscn"))
    # TestEvent stays in the codebase for unit tests (via _event_factory test
    # seam), but is no longer in the production pool.
    assert_false(MatchConfig.EVENT_POOL.has("res://scripts/events/test_event/test_event.tscn"))
```

MatchScene wiring is exercised by Plan B's `test_match_scene.gd` (which tests `format_phase_indicator` only) plus the integration test in Task 14 — no new unit test needed for the wiring itself.

- [ ] **Step 2: Implement scene change**

Update `scenes/match_scene.tscn` — add a `BetLoadoutSlot` Container between `EventSlot` and `ResolutionSlot`:
```
[node name="BetLoadoutSlot" type="Container" parent="VBox"]
```

- [ ] **Step 3: Implement controller-signal wiring**

In `scripts/ui/match_scene.gd`:

Add the preload + new @onready var:
```gdscript
const BetLoadoutOverlayScene = preload("res://scenes/ui/bet_loadout_overlay.tscn")

@onready var _bet_loadout_slot: Container = $VBox/BetLoadoutSlot if has_node("VBox/BetLoadoutSlot") else null

var _bet_loadout_overlay: Node = null
```

Wire signals in `_ready` after constructing the controller:
```gdscript
controller.bet_loadout_started.connect(_on_bet_loadout_started)
controller.bet_loadout_finished.connect(_on_bet_loadout_finished)
```

Add the handlers:
```gdscript
func _on_bet_loadout_started(_active_peer_ids: Array, _max_per_player: int) -> void:
    if _bet_loadout_slot == null or _bet_loadout_overlay != null:
        return
    _bet_loadout_overlay = BetLoadoutOverlayScene.instantiate()
    _bet_loadout_overlay.controller = controller
    _bet_loadout_overlay.local_player = _find_local_player()
    _bet_loadout_slot.add_child(_bet_loadout_overlay)

func _on_bet_loadout_finished() -> void:
    if _bet_loadout_overlay != null:
        _bet_loadout_overlay.queue_free()
        _bet_loadout_overlay = null

func _find_local_player():
    if controller == null or controller.state == null:
        return null
    var my_id = multiplayer.get_unique_id() if multiplayer != null else 1
    return controller.state.find_player(my_id)
```

- [ ] **Step 4: Swap EVENT_POOL**

In `scripts/match/match_config.gd`:
```gdscript
const EVENT_POOL: Array = [
    "res://scripts/events/rocket_clash/rocket_clash_event.tscn",
]
```

(TestEvent files remain in the codebase for unit tests; the `_event_factory` test seam injects MockEvent regardless of pool contents.)

- [ ] **Step 5: Run, watch pass**

Run the full unit suite. Expected: 289/289 tests pass (the existing TestEvent-pool assertion is now the Rocket-Clash-pool assertion; same test count).

- [ ] **Step 6: Commit**

```
feat(client): wire BetLoadoutOverlay into MatchScene + swap EVENT_POOL

MatchScene gains a BetLoadoutSlot Container and signal handlers that
instantiate / free the BetLoadoutOverlay on controller.bet_loadout_started
/ bet_loadout_finished. The overlay is passed the controller plus the
local player record so it can render the local wager UI.

EVENT_POOL swapped to ["rocket_clash_event.tscn"]. TestEvent stays in
the codebase for the existing unit tests (the _event_factory test seam
bypasses the pool); production matches will now load Rocket Clash.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 14: Integration smoke test + playtest checklist update

Final task. One integration test exercising the full BET_LOADOUT → MAIN_EVENT → RESOLUTION pipeline against the real signaling server + WebRTC + RPC stack. Plus the manual playtest scenarios appended to PLAYTEST_CHECKLIST.md.

**Files:**
- Create: `tests/integration/test_rocket_clash_runs.gd`
- Modify: `docs/PLAYTEST_CHECKLIST.md`

- [ ] **Step 1: Write the integration test**

`tests/integration/test_rocket_clash_runs.gd`:
```gdscript
# Integration smoke test: real signaling + WebRTC + Match loop + Rocket Clash.
# Spawns two NetSession instances; runs one Rocket Clash event end-to-end
# with compressed timing; both peers observe consistent painful_reveal.
#
# Skips if signaling server is not reachable on ws://localhost:8080.
extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const WebRTCTransport = preload("res://scripts/net/web_rtc_transport.gd")
const SignalingClient = preload("res://scripts/net/signaling_client.gd")
const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")

const SIGNALING_URL := "ws://localhost:8080"
const CONNECTION_TIMEOUT_SEC := 10.0
const MATCH_TIMEOUT_SEC := 30.0

func _signaling_reachable() -> bool:
    var probe = WebSocketPeer.new()
    var err = probe.connect_to_url(SIGNALING_URL)
    if err != OK:
        return false
    var t0 = Time.get_ticks_msec()
    while Time.get_ticks_msec() - t0 < 1000:
        probe.poll()
        if probe.get_ready_state() == WebSocketPeer.STATE_OPEN:
            probe.close()
            return true
        if probe.get_ready_state() == WebSocketPeer.STATE_CLOSED:
            return false
        await get_tree().process_frame
    probe.close()
    return false

func test_rocket_clash_two_peers_consistent_reveal():
    if not await _signaling_reachable():
        pending("Signaling server not reachable at %s; skipping." % SIGNALING_URL)
        return

    # Spawn host
    var host_transport = WebRTCTransport.new()
    var host_signaling = SignalingClient.new(SIGNALING_URL)
    var host = NetSession.new(host_transport, host_signaling)
    add_child_autofree(host_transport)
    add_child_autofree(host_signaling)
    host.host_session()
    var host_code = await _wait_for_code(host)

    # Spawn joiner
    var joiner_transport = WebRTCTransport.new()
    var joiner_signaling = SignalingClient.new(SIGNALING_URL)
    var joiner = NetSession.new(joiner_transport, joiner_signaling)
    add_child_autofree(joiner_transport)
    add_child_autofree(joiner_signaling)
    joiner.join_session(host_code)

    await _wait_until(func(): return host.players.size() == 2 and joiner.players.size() == 2, CONNECTION_TIMEOUT_SEC)

    # MatchStart capture
    var host_ms = [null]
    var joiner_ms = [null]
    host.match_starting.connect(func(ms): host_ms[0] = ms)
    joiner.match_starting.connect(func(ms): joiner_ms[0] = ms)

    host.set_ready(true)
    joiner.set_ready(true)
    host.start_match()

    await _wait_until(func(): return host_ms[0] != null and joiner_ms[0] != null, CONNECTION_TIMEOUT_SEC)
    assert_not_null(host_ms[0], "host got MatchStart")
    assert_not_null(joiner_ms[0], "joiner got MatchStart")

    # Controllers
    var host_controller = MatchController.new(true, null)
    var joiner_controller = MatchController.new(false, null)
    add_child_autofree(host_controller)
    add_child_autofree(joiner_controller)
    # Compress all timer paths
    host_controller.no_op_phase_delay_ms_override = 10
    host_controller.resolution_step_delay_ms_override = 10
    host_controller.event_timeout_sec_override = 10.0
    host_controller.bet_loadout_timeout_sec_override = 1.0
    joiner_controller.no_op_phase_delay_ms_override = 10
    joiner_controller.resolution_step_delay_ms_override = 10
    joiner_controller.bet_loadout_timeout_sec_override = 1.0

    var host_match_ended = [false, []]
    var joiner_match_ended = [false, []]
    host_controller.match_ended.connect(func(r): host_match_ended[0] = true; host_match_ended[1] = r)
    joiner_controller.match_ended.connect(func(r): joiner_match_ended[0] = true; joiner_match_ended[1] = r)

    host_controller.start_match(host_ms[0])

    # Wait for the match to complete. The BET_LOADOUT timer (1s) + 5 events
    # × (1s timer + a few hundred ms rocket time) ≈ 10-15s total under
    # compressed timing.
    await _wait_until(func(): return host_match_ended[0] and joiner_match_ended[0], MATCH_TIMEOUT_SEC)

    assert_true(host_match_ended[0], "host saw match_ended")
    assert_true(joiner_match_ended[0], "joiner saw match_ended")
    assert_eq(host_match_ended[1].size(), 2)
    assert_eq(joiner_match_ended[1].size(), 2)
    assert_eq(host_match_ended[1][0].peer_id, joiner_match_ended[1][0].peer_id, "consistent winner across peers")

# Helpers
func _wait_for_code(host) -> String:
    var t0 = Time.get_ticks_msec()
    while host.code == "" and Time.get_ticks_msec() - t0 < CONNECTION_TIMEOUT_SEC * 1000:
        await get_tree().process_frame
    return host.code

func _wait_until(predicate: Callable, timeout_sec: float) -> void:
    var t0 = Time.get_ticks_msec()
    while not predicate.call():
        if Time.get_ticks_msec() - t0 > timeout_sec * 1000:
            return
        await get_tree().process_frame
```

- [ ] **Step 2: Run the integration test**

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/integration -gexit
```

Expected outcomes:
- Signaling running: test passes (slow ~15s) OR fails informatively. If it fails, debug iteratively. Two known limitations may bite on first run:
  1. **Joiner-side `match_starting` gap** (Plan B noted). NetSession doesn't broadcast MatchStart over WebRTC. Sub-project #1 limitation; if it bites, document in the commit and defer to a sub-project #1 patch.
  2. **Two NetSessions in one process share the SceneTree's MultiplayerAPI.** The C1 self-wire (`_multiplayer_node = self`) routes `self.rpc(...)` through the node's scene tree multiplayer. Both controllers inherit the same `SceneTree.get_multiplayer()`, so cross-peer RPC routing in the same process is best-effort and may produce false consistency rather than actual two-peer sync. Real end-to-end verification of multi-peer behavior is the manual playtest scenarios (§9.6 / Step 3 below). This integration test is primarily a structural placeholder + signaling-reachability probe + smoke test for the basic Rocket Clash flow.
- Signaling not running: marks PENDING.

- [ ] **Step 3: Append the playtest scenarios**

Append to `docs/PLAYTEST_CHECKLIST.md`:

```markdown

## Sub-project #3: Rocket Clash (Plan A)

Plan reference: docs/superpowers/specs/2026-05-12-rocket-clash-event-design.md §9.6
Implemented: 2026-05-12

Run by launching two `godot --path .` windows on this machine.

| # | Scenario | Status | Notes |
|---|----------|--------|-------|
| 1 | Wager + rocket end-to-end | USER | Two windows; both wager; both cash out at different multipliers; both see consistent rankings. |
| 2 | Bust event | USER | Both hold past crash; both lose wager; no Crown awarded that event. |
| 3 | Solo survivor | USER | One cashes early, one busts; survivor gets Crown. |
| 4 | Wager defaults to 0 on timeout | USER | One player ignores BET_LOADOUT; verify their event still runs with wager=0. |
| 5 | Cash-out near crash | USER | Cash out within 0.1x of expected crash; verify host accepts within tolerance band. |
| 6 | Five-event match with mixed wagers | USER | Full Quick Clash; chips and Heat update correctly across all 5 events; final rankings sensible. |
```

- [ ] **Step 4: Commit**

```
test(client): Rocket Clash integration smoke test + playtest checklist

tests/integration/test_rocket_clash_runs.gd spawns host + joiner via
real signaling, runs a full 5-event Quick Clash with Rocket Clash as
the EVENT_POOL entry. Compressed timing seams (no_op_phase_delay_ms=10,
resolution_step_delay_ms=10, bet_loadout_timeout=1s) keep the full
match under 30s. Both peers must observe match_ended with the same
winner peer_id.

PENDINGs cleanly when signaling not reachable (same pattern as Plan B).

PLAYTEST_CHECKLIST.md appended with 6 manual scenarios from spec
section 9.6.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Done

When all checkboxes above are checked, sub-project #3 is complete:

1. **Plan B C1 fix landed.** Production RPC routing now works because MatchController self-wires `_multiplayer_node = self` when it enters the SceneTree.
2. **Rocket Clash event runs end-to-end.** Real-time multiplier sync via deterministic time-based broadcast; host-authoritative cash-out validation with snapshot tolerance; Aviator-style crash distribution; per-player chip rewards (`wager × cash_out_at` for survivors, `-wager` for busts); 1 Crown to the highest-cash-out survivor.
3. **BET_LOADOUT is a real phase.** 15s wager-input window with fast-advance when all active peers ready. Players who don't submit default to wager=0. State carries through to `EventContext.wagers`.
4. **HUD widgets.** `BetLoadoutOverlay` for wager input; `ResolutionOverlay` extended with a Rocket-Clash-aware painful_reveal renderer (crash_at + per-player table with Crown indicator).
5. **EVENT_POOL swapped.** Real matches load Rocket Clash instead of TestEvent. TestEvent stays in the codebase for unit tests.
6. **289 unit + 3 integration tests passing** (up from 244 + 2 baseline; +45 unit, +1 integration).
7. **Manual playtest checklist** appended with 6 scenarios from spec §9.6.

**Tag this milestone after merge:** `rocket-clash-v0.1` and `subproject-3-complete`.

**Next step:** Sub-project #4 (Power Cards & Bounties). Will hook into the new BET_LOADOUT phase (cards play here), the cash-out RPC pipeline (Cash-Out Jammer / Afterburner intercept), and the BOUNTY_HEAT_UPDATE phase (bounty resolution). Brainstorm via `superpowers:brainstorming` when ready.
