# Match UI + Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make sub-project #2 visibly playable end-to-end. Build on Plan A's headless `MatchController` by adding (1) Timer-driven scheduling so the 9-phase machine paces itself through a 5-event match without manual `_advance_phase()` calls, (2) RPC broadcast so two-player matches stay in sync, (3) the three HUD widgets (`PlayerPanel`, `ResolutionOverlay`, `MatchEndOverlay`), (4) `MatchScene.tscn` composing them, (5) the Lobby → Match scene transition, (6) a two-instance integration smoke test, and (7) the updated manual playtest checklist.

**Architecture:** Three layers on top of Plan A's engine. **Pacing layer:** new `_schedule_advance(delay_ms)` helper in `MatchController` plus a new `MatchConfig.NO_OP_PHASE_DELAY_MS` drives no-op phase transitions via `get_tree().create_timer().timeout`. The existing `resolution_step_delay_ms_override` seam wires up; an event-timeout `Timer` node lives on the controller during MAIN_EVENT. **Network layer:** `_send_rpc(method_name, args...)` host-side helper plus @rpc-annotated receivers on the controller mirror state to clients. **UI layer:** three reactive widgets that subscribe to `MatchController` signals plus a `MatchScene` that composes them and owns the controller's lifecycle. Lobby's `_on_match_starting` swaps to `match_scene.tscn` instead of the existing placeholder.

**Tech Stack:** Godot 4.6, GDScript, GUT, `.tscn` text-format scenes (no editor required), `@rpc` annotation for client mirroring. Tests use the established `FakeTransport` / `FakeSignalingClient` / `MockEvent` pattern plus a new `FakeMultiplayerNode` that records RPC sends.

**Parent spec:** [`docs/superpowers/specs/2026-05-11-match-loop-and-economy-design.md`](../specs/2026-05-11-match-loop-and-economy-design.md). Re-read §5 (Architecture), §6.5 (MatchController public interface — especially the RPC list), §6.6-6.9 (UI components), §7 (Data Flow), and §9.5-9.6 (integration + playtest scenarios) before starting.

**Companion plan (already implemented):** [`2026-05-11-match-engine.md`](2026-05-11-match-engine.md) — Plan A delivered the headless engine; this plan layers the scheduler, RPC, HUD, and integration test on top. After Plan B, sub-project #2 (Match Loop & Economy Core) is complete and shippable.

**Baseline:** Plan A ended at 196 unit + 1 integration test. This plan targets ~240 unit + 2 integration after Task 13.

---

## File Structure

```
scripts/
  match/
    match_controller.gd            # MODIFY: scheduler hooks, RPC sender/receivers, event timeout Timer
    match_config.gd                # MODIFY: add NO_OP_PHASE_DELAY_MS constant
  ui/
    player_panel.gd                # NEW
    resolution_overlay.gd          # NEW
    match_end_overlay.gd           # NEW
    match_scene.gd                 # NEW
    lobby.gd                       # MODIFY: change_scene to match_scene.tscn
scenes/
  match_scene.tscn                 # NEW (replaces placeholder_match.tscn in flow)
  ui/
    player_panel.tscn              # NEW
    resolution_overlay.tscn        # NEW
    match_end_overlay.tscn         # NEW
tests/
  fakes/
    fake_multiplayer_node.gd       # NEW — records rpc(...) calls for sender tests
  unit/
    test_match_config_no_op_delay.gd               # NEW
    test_match_controller_scheduler.gd             # NEW
    test_match_controller_resolution_pacing.gd     # NEW
    test_match_controller_event_timeout.gd         # NEW
    test_match_controller_rpc_senders.gd           # NEW
    test_match_controller_rpc_receivers.gd         # NEW
    test_player_panel.gd                           # NEW
    test_resolution_overlay.gd                     # NEW
    test_match_end_overlay.gd                      # NEW
    test_match_scene.gd                            # NEW
    test_lobby_match_scene_transition.gd           # NEW
  integration/
    test_match_runs_five_events.gd                 # NEW (companion to existing test_web_rtc_transport_smoke.gd)
docs/
  PLAYTEST_CHECKLIST.md            # MODIFY: append §9.6 scenarios
```

**Per-file responsibility:**

- `match_controller.gd` — Plan A's controller, extended with: (1) `_schedule_advance(delay_ms)` helper that awaits `get_tree().create_timer().timeout` then calls `_advance_phase`, (2) no-op-phase entry hooks that call `_schedule_advance(MatchConfig.NO_OP_PHASE_DELAY_MS)`, (3) resolution-pacing `await` loop in `_process_resolution_phase`, (4) per-MAIN_EVENT `Timer` child that fires `_on_event_timeout`, (5) `_send_rpc(name, args...)` helper called at each broadcast site, (6) `@rpc("any_peer", "call_remote", "reliable")`-annotated receivers (`_rpc_phase_changed`, `_rpc_apply_deltas`, `_rpc_resolution_step`, `_rpc_match_ended`, `_rpc_return_to_lobby`).
- `match_config.gd` — adds `NO_OP_PHASE_DELAY_MS: int = 300`.
- `player_panel.gd` — per-player widget. Subscribes to `MatchController.player_resources_changed(peer_id)`; refreshes from `controller.state.find_player(peer_id)`. Static formatters: `format_chip_text`, `format_crown_text`, `heat_band(int) -> String`.
- `resolution_overlay.gd` — subscribes to `MatchController.resolution_step(step_name, payload)`; appends formatted line. Static formatter: `format_resolution_step(step_name, payload) -> String`.
- `match_end_overlay.gd` — subscribes to `MatchController.match_ended(rankings)`; shows ranked list; host sees Back-to-Lobby button. Static formatter: `format_match_end_rankings(rankings) -> String`.
- `match_scene.gd` — composes everything: builds `MatchController` from `NetSessionMain.get_last_match_start()`, hosts the `PlayerPanels` HBox, `PhaseIndicator` label, `EventSlot` Container, `ResolutionOverlay`, `MatchEndOverlay`, `PauseOverlay`. Static formatter: `format_phase_indicator(event_index, total, phase) -> String`.
- `lobby.gd` (modify) — one-line change: `_on_match_starting` calls `change_scene_to_file("res://scenes/match_scene.tscn")` instead of placeholder.
- `fake_multiplayer_node.gd` — records `rpc("method_name", args)` calls for sender tests. Returns OK.

## Conventions

- **TDD strictly:** failing test → run-fail → minimum implementation → run-pass → commit. Same discipline as Plan A.
- **UI tests use static formatters.** Plan A's `MatchController` tests proved out the scene-tree-free pattern; widgets here follow the same: a `format_*` static helper takes data, returns a string; the widget's `_ready` and signal handlers call the formatter and assign the result to a Label. Tests exercise the formatters directly without instantiating scenes.
- **Scene tests instantiate the .tscn and verify node tree.** A few tests for `MatchScene` and the widgets check that loading the scene doesn't error and that key child nodes exist. They run headlessly via GUT.
- **Test session injection pattern (re-used from Plan D):** UI scripts default to `NetSessionMain.session` / `null` controller in `_ready()` but expose `var session` / `var controller` properties tests can set BEFORE `_ready` runs (via `var w = preload(...).new(); w.controller = test_controller;`).
- **RPC test seam:** `MatchController` exposes `_send_rpc(method_name: String, args: Array)` as a small wrapper around `_multiplayer_node.rpc(method_name, ...args)`. In tests with `multiplayer_node = null`, the wrapper no-ops. With `multiplayer_node = FakeMultiplayerNode.new()`, calls are recorded for inspection. Real-network RPC routing is Godot's responsibility, not ours.
- **Commit prefixes:** `feat(client):`, `test(client):`, `chore(client):`, `refactor(client):`, `docs(client):`. `(client)` scope matches Plans A-D + Plan A of sub-project #2.
- **Tabs for indentation in `.gd` files.** No `class_name` registration — keep `preload(...)` discipline.
- **Avoid apostrophes in PowerShell here-string commit message bodies.** When PS mangles, fall back to `git commit -F <tempfile>` with `Set-Content -Encoding utf8`.
- **GUT test runner:**
  ```
  godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
  ```
- **Integration runner (signaling required):**
  ```
  cd ../signaling-server && node server.js &  # in another terminal
  cd <project> && godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/integration -gexit
  ```
- **`godot` is on PATH** (resolves to `C:\Users\whann\Tools\godot-voxel-1.6\godot.exe`); just call `godot ...` directly.
- **Co-author footer on every commit:**
  ```
  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  ```
- **Baseline test count:** 196 unit + 1 integration after Plan A. Plan B targets ~240 unit + 2 integration.
- **Scene tree warning:** Plan A controllers were tested as RefCounted-equivalent (detached Nodes). Plan B introduces real `get_tree()` calls (Timer creation, scene changes). Where tests need the tree, they use GUT's `add_child_autofree(node)` or `add_child_autoqfree(node)` so the tree exists and cleans up.

---

## Phase 1: Timer-driven pacing

### Task 1: `MatchConfig.NO_OP_PHASE_DELAY_MS` + `_schedule_advance` helper

Adds the no-op phase delay constant and the test-injectable scheduling helper. No phase wiring yet.

**Files:**
- Modify: `scripts/match/match_config.gd`
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_config_no_op_delay.gd`
- Create: `tests/unit/test_match_controller_scheduler.gd`

- [ ] **Step 1: Write the failing test for the constant**

`tests/unit/test_match_config_no_op_delay.gd`:
```gdscript
extends GutTest

const MatchConfig = preload("res://scripts/match/match_config.gd")

func test_no_op_phase_delay_ms_default():
    assert_eq(MatchConfig.NO_OP_PHASE_DELAY_MS, 300)
```

- [ ] **Step 2: Write the failing test for the helper**

`tests/unit/test_match_controller_scheduler.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")

func test_no_op_phase_delay_override_default():
    var c = MatchController.new(true, null)
    assert_eq(c.no_op_phase_delay_ms_override, -1, "default: use MatchConfig value")

func test_schedule_advance_synchronous_when_override_zero():
    # With override=0, the helper should call _advance_phase synchronously.
    var c = MatchController.new(true, null)
    c.no_op_phase_delay_ms_override = 0
    c.state.phase = MatchPhase.Phase.HOUSE_REVEAL
    await c._schedule_advance()
    assert_eq(c.state.phase, MatchPhase.Phase.ANTE, "should advance synchronously")
```

- [ ] **Step 3: Run, watch fail**

Run: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit`. Expected: `NO_OP_PHASE_DELAY_MS` constant missing; `no_op_phase_delay_ms_override` field missing; `_schedule_advance` method missing.

- [ ] **Step 4: Implement**

In `scripts/match/match_config.gd`, append:
```gdscript
# Small delay used to pace no-op phase transitions (HOUSE_REVEAL, BET_LOADOUT,
# BOUNTY_HEAT_UPDATE->SHOP, SHOP, HOUSE_TWIST) so HUD updates animate rather
# than blurring past in one frame.
const NO_OP_PHASE_DELAY_MS: int = 300
```

In `scripts/match/match_controller.gd`, near `resolution_step_delay_ms_override`, add the new override:
```gdscript
# Test seam: override no-op phase auto-advance delay. -1 = use MatchConfig
# default. 0 = advance synchronously (no await). >0 = use this delay in ms.
var no_op_phase_delay_ms_override: int = -1
```

Add the helper method (place near `_advance_phase`):
```gdscript
func _schedule_advance() -> void:
    # Detached-controller test pattern (Plan A): when not in the scene tree
    # there's no SceneTree to create timers from, so advance synchronously.
    # This preserves the behavior of every Plan A unit test that constructs
    # MatchController.new(true, null) without add_child_autofree.
    if not is_inside_tree():
        _advance_phase()
        return
    var delay_ms: int = no_op_phase_delay_ms_override
    if delay_ms < 0:
        delay_ms = MatchConfig.NO_OP_PHASE_DELAY_MS
    if delay_ms > 0:
        await get_tree().create_timer(delay_ms / 1000.0).timeout
    _advance_phase()
```

Note: the synchronous-test path (detached controller OR `delay_ms == 0` on an attached one) is what unit tests use; the production path takes the real Timer.

- [ ] **Step 5: Run, watch pass**

Expected: 199/199 tests pass (196 prior + 3 new).

- [ ] **Step 6: Commit**

```
feat(client): MatchController scheduler helper for no-op phase pacing

NO_OP_PHASE_DELAY_MS (300ms default) controls the visible pause between
phases without MVP behavior. _schedule_advance awaits get_tree().create_timer
then calls _advance_phase. The no_op_phase_delay_ms_override seam mirrors
resolution_step_delay_ms_override: -1 = use MatchConfig, 0 = synchronous,
>0 = custom. Phase-entry wiring lands in Task 2.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 2: Wire no-op phases through the scheduler

Connect `_schedule_advance` to the phase-entry hook for HOUSE_REVEAL, BET_LOADOUT, BOUNTY_HEAT_UPDATE (after heat application), SHOP, and HOUSE_TWIST. Together with Plan A's existing handlers, this lets a host complete a full 5-event match end-to-end without manual `_advance_phase` calls.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Modify: `tests/unit/test_match_controller_scheduler.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_match_controller_scheduler.gd`:
```gdscript
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

func _new_controller_synchronous() -> MatchController:
    var c = MatchController.new(true, null)
    c.no_op_phase_delay_ms_override = 0
    c.start_match(_build_match_start(2))
    return c

func test_house_reveal_auto_advances_to_ante():
    # start_match sets phase to HOUSE_REVEAL which enters the scheduler hook.
    # With override=0 we run synchronously; by the time start_match returns,
    # the phase should already have advanced.
    var c = _new_controller_synchronous()
    await get_tree().process_frame
    # After scheduling, phase has advanced from HOUSE_REVEAL → ANTE → cascade.
    assert_ne(c.state.phase, MatchPhase.Phase.HOUSE_REVEAL)

func test_bet_loadout_auto_advances_to_main_event():
    var c = _new_controller_synchronous()
    c.state.phase = MatchPhase.Phase.BET_LOADOUT
    await c._enter_phase_behavior()
    # current_event_id may be empty; MAIN_EVENT's empty-id guard returns;
    # we still know BET_LOADOUT itself left.
    assert_ne(c.state.phase, MatchPhase.Phase.BET_LOADOUT)

func test_shop_auto_advances_to_house_twist():
    var c = _new_controller_synchronous()
    c.state.phase = MatchPhase.Phase.SHOP
    await c._enter_phase_behavior()
    # SHOP → HOUSE_TWIST → cascades; expect phase past SHOP.
    assert_ne(c.state.phase, MatchPhase.Phase.SHOP)

func test_bounty_heat_advances_after_heat_application():
    var c = _new_controller_synchronous()
    # Set a non-null current_result so the heat handler runs.
    var EventResult = preload("res://scripts/events/event_result.gd")
    c.state.current_result = EventResult.new()
    c.state.phase = MatchPhase.Phase.BOUNTY_HEAT_UPDATE
    await c._enter_phase_behavior()
    assert_ne(c.state.phase, MatchPhase.Phase.BOUNTY_HEAT_UPDATE)

func test_house_twist_advances_to_next_event_or_match_end():
    var c = _new_controller_synchronous()
    c.state.phase = MatchPhase.Phase.HOUSE_TWIST
    c.state.event_index = 2
    await c._enter_phase_behavior()
    # event_index incremented to 3, phase past HOUSE_TWIST.
    assert_ne(c.state.phase, MatchPhase.Phase.HOUSE_TWIST)
```

- [ ] **Step 2: Run, watch fail**

Expected: tests fail because `_enter_phase_behavior` doesn't return a coroutine and the no-op phases don't call `_schedule_advance`.

- [ ] **Step 3: Implement**

Modify `_enter_phase_behavior` in `scripts/match/match_controller.gd` to add no-op phase hooks. The function must become async (returns `void` but `await`s `_schedule_advance`):

```gdscript
func _enter_phase_behavior() -> void:
    if not is_host:
        return
    match state.phase:
        MatchPhase.Phase.HOUSE_REVEAL:
            await _schedule_advance()
        MatchPhase.Phase.ANTE:
            _process_ante_phase()
            await _schedule_advance()
        MatchPhase.Phase.EVENT_SELECTION:
            _process_event_selection()
            await _schedule_advance()
        MatchPhase.Phase.BET_LOADOUT:
            await _schedule_advance()
        MatchPhase.Phase.MAIN_EVENT:
            _process_main_event()
            # MAIN_EVENT does NOT _schedule_advance; the event drives the
            # transition via event_complete or watchdog timeout.
        MatchPhase.Phase.RESOLUTION:
            await _process_resolution_phase()
            # RESOLUTION pipeline calls _advance_phase at its end (existing).
        MatchPhase.Phase.BOUNTY_HEAT_UPDATE:
            _process_bounty_heat_update()
            await _schedule_advance()
        MatchPhase.Phase.SHOP:
            await _schedule_advance()
        MatchPhase.Phase.HOUSE_TWIST:
            await _schedule_advance()
        MatchPhase.Phase.MATCH_END:
            _process_match_end()
        _:
            pass
```

**Important caveats from this change:**
- `_set_phase` calls `_enter_phase_behavior()` without awaiting (and can't easily — `_set_phase` itself isn't async). The phase change still happens synchronously; the *scheduled advance* happens on the next tick. This is the desired behavior — the signal `phase_changed` fires before clients can observe the next phase.
- Plan A's existing tests that call `_enter_phase_behavior()` directly without `await` continue to work because GDScript ignores the unwaited coroutine (it just runs detached). Tests that need to observe post-await state must `await _enter_phase_behavior()` explicitly.

- [ ] **Step 4: Run, watch pass**

Expected: 204/204 tests pass (199 prior + 5 new). **All Plan A tests must still pass** — verify carefully.

- [ ] **Step 5: Commit**

```
feat(client): MatchController auto-advances no-op phases via scheduler

HOUSE_REVEAL, BET_LOADOUT, BOUNTY_HEAT_UPDATE (post-heat), SHOP, and
HOUSE_TWIST now call _schedule_advance after their entry behavior. The
ANTE and EVENT_SELECTION phases keep their existing behavior but also
chain through the scheduler so the match continues without manual
_advance_phase calls. MAIN_EVENT remains the only event-driven phase
(the event scene emits event_complete or the watchdog times out).

Plan A's tests that called _enter_phase_behavior without await continue
to pass; the unwaited coroutine runs detached.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 3: Resolution step pacing via the existing override seam

Plan A declared `resolution_step_delay_ms_override: int = -1` as a forward seam. This task wires it: when delay > 0, each substep awaits a Timer before the next.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_resolution_pacing.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_controller_resolution_pacing.gd`:
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

func _new_controller(delay_override: int) -> MatchController:
    var c = MatchController.new(true, null)
    c.no_op_phase_delay_ms_override = 0  # don't pace no-op phases in tests
    c.resolution_step_delay_ms_override = delay_override
    c.start_match(_build_match_start(2))
    return c

func test_resolution_synchronous_when_override_zero():
    # delay 0 → no awaits; pipeline completes within the call.
    var c = _new_controller(0)
    c.state.current_result = EventResult.new()
    c.state.phase = MatchPhase.Phase.RESOLUTION
    await c._process_resolution_phase()
    # After pipeline, BOUNTY_HEAT_UPDATE handler will have run (also no-op
    # delay 0) and chained through. Just assert phase is past RESOLUTION.
    assert_ne(c.state.phase, MatchPhase.Phase.RESOLUTION)

func test_resolution_resolution_step_emits_substeps_in_order_with_paced_delay():
    # With override=10ms, the pipeline emits 5 substeps with 4 timer awaits
    # between them. Verify order is preserved.
    var c = _new_controller(10)
    c.state.current_result = EventResult.new()
    c.state.phase = MatchPhase.Phase.RESOLUTION
    var steps: Array = []
    c.resolution_step.connect(func(name, _payload): steps.append(name))
    await c._process_resolution_phase()
    assert_eq(steps, ["busts", "cash_outs", "chip_changes", "crown_awards", "painful_reveal"])

func test_resolution_uses_match_config_when_override_negative():
    # override=-1 → use MatchConfig.RESOLUTION_STEP_DELAY_MS. We can't time
    # the run in a test, but we can verify the controller picks the right
    # delay value via _resolution_step_delay_ms() helper.
    var c = _new_controller(-1)
    assert_eq(c._resolution_step_delay_ms(), MatchConfig.RESOLUTION_STEP_DELAY_MS)
```

- [ ] **Step 2: Run, watch fail**

Expected: `_resolution_step_delay_ms()` doesn't exist; pipeline doesn't await between steps.

- [ ] **Step 3: Implement**

In `scripts/match/match_controller.gd`, modify `_process_resolution_phase` to use the awaitable helper. Replace:

```gdscript
func _process_resolution_phase() -> void:
    var result = state.current_result
    if result == null:
        _advance_phase()
        return
    _emit_resolution_step("busts", _build_busts_payload(result))
    _emit_resolution_step("cash_outs", _build_cash_outs_payload(result))
    _apply_and_emit("chip_changes", result, "chip_delta")
    _apply_and_emit("crown_awards", result, "crown_delta")
    _emit_resolution_step("painful_reveal", result.painful_reveal)
    _advance_phase()
```

With:
```gdscript
func _resolution_step_delay_ms() -> int:
    if resolution_step_delay_ms_override >= 0:
        return resolution_step_delay_ms_override
    return MatchConfig.RESOLUTION_STEP_DELAY_MS

func _await_resolution_step_delay() -> void:
    var ms = _resolution_step_delay_ms()
    if ms <= 0:
        return
    await get_tree().create_timer(ms / 1000.0).timeout

func _process_resolution_phase() -> void:
    var result = state.current_result
    if result == null:
        _advance_phase()
        return
    _emit_resolution_step("busts", _build_busts_payload(result))
    await _await_resolution_step_delay()
    _emit_resolution_step("cash_outs", _build_cash_outs_payload(result))
    await _await_resolution_step_delay()
    _apply_and_emit("chip_changes", result, "chip_delta")
    await _await_resolution_step_delay()
    _apply_and_emit("crown_awards", result, "crown_delta")
    await _await_resolution_step_delay()
    _emit_resolution_step("painful_reveal", result.painful_reveal)
    _advance_phase()
```

- [ ] **Step 4: Run, watch pass**

Expected: 207/207 tests pass (204 prior + 3 new). Plan A's `test_resolution_emits_substeps_in_order` continues to pass — it set `resolution_step_delay_ms_override = 0`, so the loop runs synchronously.

- [ ] **Step 5: Commit**

```
feat(client): MatchController paces resolution substeps with Timer

_process_resolution_phase now awaits get_tree().create_timer between
substeps when _resolution_step_delay_ms returns >0. delay 0 keeps the
synchronous-test path; -1 (default) falls back to MatchConfig's 600ms.
Plan A's resolution tests still pass — they all set override=0.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 4: Event timeout watchdog Timer

When MAIN_EVENT enters, start a Timer for `MatchConfig.EVENT_TIMEOUT_SEC` (120s). Cancel on `_on_event_complete`. On timeout, call `_on_event_timeout` (already wired by Plan A).

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_event_timeout.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_controller_event_timeout.gd`:
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
    add_child_autofree(c)  # need tree for Timer creation
    c.no_op_phase_delay_ms_override = 0
    var mock = MockEvent.new()
    c._event_factory = func(_path): return mock
    c.start_match(_build_match_start(2))
    return {"controller": c, "mock": mock}

func test_event_timeout_timer_created_on_main_event_entry():
    var d = _new_with_mock()
    var c = d.controller
    c.state.current_event_id = "res://scripts/events/test_event/test_event.tscn"
    c.state.phase = MatchPhase.Phase.MAIN_EVENT
    c._enter_phase_behavior()
    assert_not_null(c._event_timeout_timer, "watchdog timer attached")
    assert_almost_eq(c._event_timeout_timer.wait_time, 120.0, 0.1)

func test_event_timeout_timer_cleared_on_event_complete():
    var d = _new_with_mock()
    var c = d.controller
    c.state.current_event_id = "res://scripts/events/test_event/test_event.tscn"
    c.state.phase = MatchPhase.Phase.MAIN_EVENT
    c._enter_phase_behavior()
    var result = EventResult.new()
    d.mock.emit_complete(result)
    assert_null(c._event_timeout_timer, "watchdog timer cleared")

func test_event_timeout_short_override_triggers_synthetic_result():
    var d = _new_with_mock()
    var c = d.controller
    c.event_timeout_sec_override = 0.05  # 50ms
    c.state.current_event_id = "res://scripts/events/test_event/test_event.tscn"
    c.state.phase = MatchPhase.Phase.MAIN_EVENT
    c._enter_phase_behavior()
    # Wait long enough for the timer to fire
    await get_tree().create_timer(0.15).timeout
    assert_not_null(c.state.current_result, "synthetic result stored")
    assert_ne(c.state.phase, MatchPhase.Phase.MAIN_EVENT, "advanced past MAIN_EVENT")
```

- [ ] **Step 2: Run, watch fail**

Expected: `_event_timeout_timer` field doesn't exist; `event_timeout_sec_override` doesn't exist; watchdog isn't wired.

- [ ] **Step 3: Implement**

In `scripts/match/match_controller.gd`, add the watchdog plumbing:

```gdscript
# Watchdog timer for the currently-running MAIN_EVENT. Created in
# _process_main_event when the event node is instantiated; freed in
# _on_event_complete and _on_event_timeout.
var _event_timeout_timer: Timer = null

# Test seam: override watchdog timeout in seconds. -1 = use MatchConfig.
var event_timeout_sec_override: float = -1.0

func _event_timeout_sec() -> float:
    if event_timeout_sec_override >= 0.0:
        return event_timeout_sec_override
    return float(MatchConfig.EVENT_TIMEOUT_SEC)

func _start_event_timeout_watchdog() -> void:
    if not is_inside_tree():
        # Tests that bypass the scene tree skip the watchdog; the test
        # may call _on_event_timeout directly to verify timeout behavior.
        return
    _clear_event_timeout_watchdog()
    _event_timeout_timer = Timer.new()
    _event_timeout_timer.one_shot = true
    _event_timeout_timer.wait_time = _event_timeout_sec()
    add_child(_event_timeout_timer)
    _event_timeout_timer.timeout.connect(_on_event_timeout)
    _event_timeout_timer.start()

func _clear_event_timeout_watchdog() -> void:
    if _event_timeout_timer != null:
        if _event_timeout_timer.is_inside_tree():
            _event_timeout_timer.queue_free()
        _event_timeout_timer = null
```

Wire `_start_event_timeout_watchdog` into `_process_main_event` (after the event-starting emit, before `_run`):
```gdscript
func _process_main_event() -> void:
    if state.current_event_id.is_empty():
        return
    if _current_event_node != null:
        _current_event_node.queue_free()
        _current_event_node = null
    _current_event_node = _event_factory.call(state.current_event_id)
    if _current_event_node == null:
        var empty_result = preload("res://scripts/events/event_result.gd").new()
        state.current_result = empty_result
        _advance_phase()
        return
    _current_event_node.event_complete.connect(_on_event_complete)
    event_starting.emit(_current_event_node.get_event_id(), state.event_index)
    _start_event_timeout_watchdog()                  # NEW
    var context = _build_event_context()
    _current_event_node._run(context)
```

Update `_on_event_complete` and `_on_event_timeout` to clear the watchdog. `_on_event_complete`:
```gdscript
func _on_event_complete(result) -> void:
    state.current_result = result
    _clear_event_timeout_watchdog()                  # NEW
    if _current_event_node != null:
        _current_event_node.queue_free()
        _current_event_node = null
    _advance_phase()
```

`_on_event_timeout` (also add the watchdog clear at the top):
```gdscript
func _on_event_timeout() -> void:
    _clear_event_timeout_watchdog()                  # NEW
    if _current_event_node == null:
        return
    var empty = preload("res://scripts/events/event_result.gd").new()
    for p in state.players:
        if p.is_active_this_event:
            empty.per_player[p.peer_id] = {"chip_delta": 0, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0}
    state.current_result = empty
    _current_event_node.queue_free()
    _current_event_node = null
    _advance_phase()
```

- [ ] **Step 4: Run, watch pass**

Expected: 210/210 tests pass (207 prior + 3 new). Plan A's `test_event_timeout_synthesizes_zero_delta_result` continues to pass (it calls `_on_event_timeout` directly without using the Timer; `_clear_event_timeout_watchdog` is a no-op when `_event_timeout_timer` is null).

- [ ] **Step 5: Commit**

```
feat(client): MatchController event-timeout watchdog Timer

_start_event_timeout_watchdog creates a one-shot Timer when MAIN_EVENT
begins. _on_event_complete and _on_event_timeout both call
_clear_event_timeout_watchdog to free it. event_timeout_sec_override
test seam allows short timeouts in unit tests. Production uses
MatchConfig.EVENT_TIMEOUT_SEC (120s).

is_inside_tree guard ensures detached-controller tests (Plan A pattern)
skip the Timer entirely; those tests still drive _on_event_timeout
directly.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 2: RPC layer

### Task 5: RPC senders (host broadcasts)

Host's `MatchController` broadcasts state changes to clients. Each broadcast site checks `is_host` and that `_multiplayer_node` is non-null. Tests use a `FakeMultiplayerNode` that records `rpc(...)` calls instead of routing them through Godot's MultiplayerAPI.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/fakes/fake_multiplayer_node.gd`
- Create: `tests/unit/test_match_controller_rpc_senders.gd`

- [ ] **Step 1: Write the failing tests**

`tests/fakes/fake_multiplayer_node.gd`:
```gdscript
# Records rpc(...) calls for sender-side tests. Each call is appended to
# rpc_calls as {method, args}. MatchController's _send_rpc helper invokes
# fake.rpc("method_name", arg1, arg2, ...) — we capture the method name
# and all positional arguments.
extends Node

var rpc_calls: Array = []

func rpc(method: StringName, p1=null, p2=null, p3=null, p4=null) -> int:
    var args: Array = []
    if p1 != null: args.append(p1)
    if p2 != null: args.append(p2)
    if p3 != null: args.append(p3)
    if p4 != null: args.append(p4)
    rpc_calls.append({"method": String(method), "args": args})
    return OK
```

`tests/unit/test_match_controller_rpc_senders.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MockEvent = preload("res://tests/fakes/mock_event.gd")
const EventResult = preload("res://scripts/events/event_result.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")
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

func _new_host_with_fake() -> Dictionary:
    var fake = FakeMultiplayerNode.new()
    var c = MatchController.new(true, fake)
    c.no_op_phase_delay_ms_override = 0
    c.resolution_step_delay_ms_override = 0
    return {"controller": c, "fake": fake}

func _rpc_methods_called(fake) -> Array:
    var out: Array = []
    for call in fake.rpc_calls:
        out.append(call.method)
    return out

func test_start_match_emits_rpc_phase_changed():
    var d = _new_host_with_fake()
    d.controller.start_match(_build_match_start(2))
    var methods = _rpc_methods_called(d.fake)
    assert_true("_rpc_phase_changed" in methods, "phase_changed broadcast on start")

func test_ante_emits_rpc_apply_deltas():
    var d = _new_host_with_fake()
    d.controller.start_match(_build_match_start(2))
    var methods = _rpc_methods_called(d.fake)
    # ANTE handler should have broadcast a delta packet
    var apply_deltas_count = 0
    for m in methods:
        if m == "_rpc_apply_deltas":
            apply_deltas_count += 1
    assert_gt(apply_deltas_count, 0, "ante deltas broadcast")

func test_resolution_pipeline_emits_rpc_resolution_step_per_substep():
    var d = _new_host_with_fake()
    d.controller.start_match(_build_match_start(2))
    d.fake.rpc_calls.clear()  # reset after start_match noise
    d.controller.state.current_result = EventResult.new()
    d.controller.state.phase = MatchPhase.Phase.RESOLUTION
    await d.controller._process_resolution_phase()
    var step_calls = 0
    for c in d.fake.rpc_calls:
        if c.method == "_rpc_resolution_step":
            step_calls += 1
    assert_eq(step_calls, 5, "five substeps broadcast")

func test_match_end_emits_rpc_match_ended():
    var d = _new_host_with_fake()
    d.controller.start_match(_build_match_start(2))
    d.fake.rpc_calls.clear()
    d.controller.state.phase = MatchPhase.Phase.MATCH_END
    d.controller._enter_phase_behavior()
    var methods = _rpc_methods_called(d.fake)
    assert_true("_rpc_match_ended" in methods)

func test_joiner_does_not_emit_rpcs():
    # Non-host controller should not broadcast.
    var fake = FakeMultiplayerNode.new()
    var c = MatchController.new(false, fake)
    c.start_match(_build_match_start(2))  # no-op for non-host
    assert_eq(fake.rpc_calls.size(), 0, "non-host doesn't broadcast")
```

- [ ] **Step 2: Run, watch fail**

Expected: `_send_rpc` doesn't exist; no broadcasts wired.

- [ ] **Step 3: Implement**

In `scripts/match/match_controller.gd`, add the RPC sender helper:

```gdscript
# Internal RPC sender. Routes through _multiplayer_node.rpc when non-null;
# no-ops in unit tests where _multiplayer_node is null.
func _send_rpc(method_name: String, args: Array = []) -> void:
    if _multiplayer_node == null:
        return
    match args.size():
        0: _multiplayer_node.rpc(method_name)
        1: _multiplayer_node.rpc(method_name, args[0])
        2: _multiplayer_node.rpc(method_name, args[0], args[1])
        3: _multiplayer_node.rpc(method_name, args[0], args[1], args[2])
        _:
            push_error("MatchController._send_rpc: unsupported arity %d" % args.size())
```

Wire broadcast calls at every state-mutating site. Update `_set_phase`:
```gdscript
func _set_phase(new_phase: int) -> void:
    state.phase = new_phase
    phase_changed.emit(new_phase)
    if is_host:
        _send_rpc("_rpc_phase_changed", [new_phase, _phase_change_context()])
    _enter_phase_behavior()

func _phase_change_context() -> Dictionary:
    return {
        "event_index": state.event_index,
        "current_event_id": state.current_event_id,
    }
```

Update `_process_ante_phase` to broadcast a delta packet after the loop:
```gdscript
func _process_ante_phase() -> void:
    var ante = MatchConfig.ANTE_BY_EVENT_INDEX[state.event_index]
    var deltas: Array = []
    for p in state.players:
        if p.chips >= ante:
            p.chips -= ante
            p.is_active_this_event = true
            player_resources_changed.emit(p.peer_id)
            deltas.append({"peer_id": p.peer_id, "chip_delta": -ante, "crown_delta": 0, "heat_delta": 0})
        else:
            p.is_active_this_event = false
    if deltas.size() > 0 and is_host:
        _send_rpc("_rpc_apply_deltas", [deltas])
```

Update `_apply_and_emit` to broadcast deltas after applying:
```gdscript
func _apply_and_emit(step_name: String, result, delta_key: String) -> void:
    var deltas: Array = []
    var broadcast_deltas: Array = []
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
                broadcast_deltas.append({"peer_id": pid, "chip_delta": d, "crown_delta": 0, "heat_delta": 0})
            "crown_delta":
                p.crowns += d
                broadcast_deltas.append({"peer_id": pid, "chip_delta": 0, "crown_delta": d, "heat_delta": 0})
        deltas.append({"peer_id": pid, "delta": d})
        player_resources_changed.emit(pid)
    _emit_resolution_step(step_name, {"deltas": deltas})
    if broadcast_deltas.size() > 0 and is_host:
        _send_rpc("_rpc_apply_deltas", [broadcast_deltas])
```

Update `_emit_resolution_step` to broadcast each substep:
```gdscript
func _emit_resolution_step(step_name: String, payload: Dictionary) -> void:
    resolution_step.emit(step_name, payload)
    if is_host:
        _send_rpc("_rpc_resolution_step", [step_name, payload])
```

Update `_process_bounty_heat_update` to broadcast heat deltas:
```gdscript
func _process_bounty_heat_update() -> void:
    var result = state.current_result
    if result == null:
        return
    var broadcast_deltas: Array = []
    for pid in result.per_player.keys():
        var d = result.heat_delta_for(pid)
        if d == 0:
            continue
        var p = state.find_player(pid)
        if p == null:
            continue
        p.heat = clamp(p.heat + d, 0, MatchConfig.HEAT_MAX)
        player_resources_changed.emit(pid)
        broadcast_deltas.append({"peer_id": pid, "chip_delta": 0, "crown_delta": 0, "heat_delta": d})
    if broadcast_deltas.size() > 0 and is_host:
        _send_rpc("_rpc_apply_deltas", [broadcast_deltas])
```

Update `_process_match_end` to broadcast:
```gdscript
func _process_match_end() -> void:
    var rankings = state.players.duplicate()
    rankings.sort_custom(func(a, b):
        if a.crowns != b.crowns: return a.crowns > b.crowns
        if a.chips != b.chips: return a.chips > b.chips
        return a.heat > b.heat
    )
    match_ended.emit(rankings)
    if is_host:
        var serialized: Array = []
        for p in rankings:
            serialized.append(p.to_dict())
        _send_rpc("_rpc_match_ended", [serialized])
```

Add a `return_to_lobby` host-only orchestration method that broadcasts the intent:
```gdscript
# Host-only: signals all peers to leave the match scene. Called by
# MatchEndOverlay's Back-to-Lobby button. NetSession.return_to_lobby
# (from Task 6 in Plan A) is called separately by MatchScene.
func return_to_lobby() -> void:
    if not is_host:
        return
    _send_rpc("_rpc_return_to_lobby", [])
```

- [ ] **Step 4: Run, watch pass**

Expected: 215/215 tests pass (210 prior + 5 new). All Plan A tests still pass because `_multiplayer_node = null` in those tests means `_send_rpc` no-ops.

- [ ] **Step 5: Commit**

```
feat(client): MatchController RPC senders for host broadcasts

_send_rpc helper routes to _multiplayer_node.rpc when non-null; no-ops
in unit tests. Broadcast sites wired:
- _set_phase: _rpc_phase_changed(phase, ctx)
- _process_ante_phase: _rpc_apply_deltas(chip deltas)
- _apply_and_emit: _rpc_apply_deltas(chip or crown deltas)
- _process_bounty_heat_update: _rpc_apply_deltas(heat deltas)
- _emit_resolution_step: _rpc_resolution_step(name, payload)
- _process_match_end: _rpc_match_ended(serialized rankings)
- return_to_lobby (new, host-only): _rpc_return_to_lobby()

FakeMultiplayerNode records calls for sender tests. Plan A's 196 unit
tests continue to pass — _multiplayer_node is null in all of them.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 6: RPC receivers (client mirroring)

@rpc-annotated receivers on `MatchController` mutate state when invoked by the host. Receivers are also test-callable directly (Godot lets you call @rpc methods like any method when invoked locally).

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_rpc_receivers.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_controller_rpc_receivers.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
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

func _new_client() -> MatchController:
    var c = MatchController.new(false, null)  # non-host
    # Seed with 2 players so deltas have targets.
    for i in 2:
        var p = MatchPlayer.new()
        p.peer_id = i + 1
        p.name = "P%d" % (i + 1)
        p.chips = 800
        c.state.players.append(p)
    return c

func test_rpc_phase_changed_updates_local_state():
    var c = _new_client()
    c._rpc_phase_changed(MatchPhase.Phase.ANTE, {"event_index": 0, "current_event_id": ""})
    assert_eq(c.state.phase, MatchPhase.Phase.ANTE)
    assert_eq(c.state.event_index, 0)

func test_rpc_phase_changed_emits_signal():
    var c = _new_client()
    var phases: Array = []
    c.phase_changed.connect(func(p): phases.append(p))
    c._rpc_phase_changed(MatchPhase.Phase.EVENT_SELECTION, {"event_index": 1, "current_event_id": "x"})
    assert_true(MatchPhase.Phase.EVENT_SELECTION in phases)

func test_rpc_apply_deltas_mutates_chips():
    var c = _new_client()
    c._rpc_apply_deltas([{"peer_id": 1, "chip_delta": -25, "crown_delta": 0, "heat_delta": 0}])
    assert_eq(c.state.players[0].chips, 775)

func test_rpc_apply_deltas_ignores_unknown_peer():
    var c = _new_client()
    c._rpc_apply_deltas([{"peer_id": 99, "chip_delta": -25, "crown_delta": 0, "heat_delta": 0}])
    # P1 and P2 unaffected
    assert_eq(c.state.players[0].chips, 800)
    assert_eq(c.state.players[1].chips, 800)

func test_rpc_resolution_step_emits_signal():
    var c = _new_client()
    var steps: Array = []
    c.resolution_step.connect(func(name, _payload): steps.append(name))
    c._rpc_resolution_step("painful_reveal", {"winner_peer_id": 1})
    assert_eq(steps, ["painful_reveal"])

func test_rpc_match_ended_emits_signal_with_deserialized_rankings():
    var c = _new_client()
    var rankings_seen: Array = []
    c.match_ended.connect(func(r): rankings_seen = r)
    var serialized: Array = [
        {"peer_id": 2, "name": "P2", "chips": 800, "crowns": 1, "heat": 0, "seat_index": 1, "color_index": 1, "is_active_this_event": true},
        {"peer_id": 1, "name": "P1", "chips": 700, "crowns": 0, "heat": 0, "seat_index": 0, "color_index": 0, "is_active_this_event": true},
    ]
    c._rpc_match_ended(serialized)
    assert_eq(rankings_seen.size(), 2)
    assert_eq(rankings_seen[0].peer_id, 2)
```

- [ ] **Step 2: Run, watch fail**

Expected: `_rpc_*` methods don't exist.

- [ ] **Step 3: Implement**

In `scripts/match/match_controller.gd`, add the receivers (place after `return_to_lobby`):

```gdscript
@rpc("authority", "call_remote", "reliable")
func _rpc_phase_changed(phase: int, ctx: Dictionary) -> void:
    state.phase = phase
    state.event_index = int(ctx.get("event_index", state.event_index))
    state.current_event_id = String(ctx.get("current_event_id", state.current_event_id))
    phase_changed.emit(phase)

@rpc("authority", "call_remote", "reliable")
func _rpc_apply_deltas(deltas: Array) -> void:
    for d in deltas:
        var pid = int(d.get("peer_id", 0))
        var p = state.find_player(pid)
        if p == null:
            continue  # silently ignore unknown peers per spec §8.4
        var chip_d = int(d.get("chip_delta", 0))
        var crown_d = int(d.get("crown_delta", 0))
        var heat_d = int(d.get("heat_delta", 0))
        if chip_d != 0:
            p.chips += chip_d
        if crown_d != 0:
            p.crowns += crown_d
        if heat_d != 0:
            p.heat = clamp(p.heat + heat_d, 0, MatchConfig.HEAT_MAX)
        player_resources_changed.emit(pid)

@rpc("authority", "call_remote", "reliable")
func _rpc_resolution_step(step_name: String, payload: Dictionary) -> void:
    resolution_step.emit(step_name, payload)

@rpc("authority", "call_remote", "reliable")
func _rpc_match_ended(serialized_rankings: Array) -> void:
    var rankings: Array = []
    for d in serialized_rankings:
        rankings.append(MatchPlayer.from_dict(d))
    match_ended.emit(rankings)

@rpc("authority", "call_remote", "reliable")
func _rpc_return_to_lobby() -> void:
    # MatchScene listens to this signal (re-emitted as request_return_to_lobby).
    request_return_to_lobby.emit()
```

Add the `request_return_to_lobby` signal near the other signals:
```gdscript
signal request_return_to_lobby
```

- [ ] **Step 4: Run, watch pass**

Expected: 221/221 tests pass (215 prior + 6 new).

- [ ] **Step 5: Commit**

```
feat(client): MatchController @rpc receivers for client mirroring

Five @rpc("authority","call_remote","reliable") methods accept host
broadcasts and mutate client-side state:
- _rpc_phase_changed: updates state.phase / event_index / current_event_id
- _rpc_apply_deltas: applies chip/crown/heat per peer_id; ignores unknown
- _rpc_resolution_step: re-emits the signal locally
- _rpc_match_ended: deserializes rankings via MatchPlayer.from_dict
- _rpc_return_to_lobby: re-emits request_return_to_lobby for MatchScene

Per spec §8.4, unknown peer_id in apply_deltas is silently dropped; next
phase_changed resyncs. MatchController gains the request_return_to_lobby
signal so MatchScene can swap scenes without coupling to the @rpc method.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 3: HUD widgets

### Task 7: `PlayerPanel` widget

Per-player HUD card. Shows name + color swatch, chips, Crowns, and Heat (with banded label per design §5.3).

**Files:**
- Create: `scripts/ui/player_panel.gd`
- Create: `scenes/ui/player_panel.tscn`
- Create: `tests/unit/test_player_panel.gd`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_player_panel.gd`:
```gdscript
extends GutTest

const PlayerPanel = preload("res://scripts/ui/player_panel.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func test_format_chip_text():
    assert_eq(PlayerPanel.format_chip_text(0), "0 chips")
    assert_eq(PlayerPanel.format_chip_text(1234), "1234 chips")

func test_format_crown_text():
    assert_eq(PlayerPanel.format_crown_text(0), "0 Crowns")
    assert_eq(PlayerPanel.format_crown_text(1), "1 Crown")
    assert_eq(PlayerPanel.format_crown_text(3), "3 Crowns")

func test_heat_band_quiet():
    assert_eq(PlayerPanel.heat_band(0), "Quiet")
    assert_eq(PlayerPanel.heat_band(2), "Quiet")

func test_heat_band_noticed():
    assert_eq(PlayerPanel.heat_band(3), "Noticed")
    assert_eq(PlayerPanel.heat_band(5), "Noticed")

func test_heat_band_hot_seat():
    assert_eq(PlayerPanel.heat_band(6), "Hot Seat")
    assert_eq(PlayerPanel.heat_band(8), "Hot Seat")

func test_heat_band_public_enemy():
    assert_eq(PlayerPanel.heat_band(9), "Public Enemy")
    assert_eq(PlayerPanel.heat_band(10), "Public Enemy")
```

- [ ] **Step 2: Run, watch fail**

Expected: `PlayerPanel` script doesn't exist.

- [ ] **Step 3: Implement script**

`scripts/ui/player_panel.gd`:
```gdscript
# Per-player HUD widget. Composed in MatchScene's PlayerPanels HBox.
# Subscribes to MatchController.player_resources_changed(peer_id) and
# refreshes from controller.state.find_player(peer_id) when peer_id matches.
extends PanelContainer

@onready var _name_label: Label = $VBox/NameLabel if has_node("VBox/NameLabel") else null
@onready var _color_swatch: ColorRect = $VBox/ColorSwatch if has_node("VBox/ColorSwatch") else null
@onready var _chips_label: Label = $VBox/ChipsLabel if has_node("VBox/ChipsLabel") else null
@onready var _crowns_label: Label = $VBox/CrownsLabel if has_node("VBox/CrownsLabel") else null
@onready var _heat_label: Label = $VBox/HeatLabel if has_node("VBox/HeatLabel") else null

const SEAT_COLORS: Array = [
    Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW,
    Color.PURPLE, Color.CYAN, Color.ORANGE, Color.MAGENTA,
]

var controller  # MatchController-like
var peer_id: int = 0

func _ready() -> void:
    if controller == null:
        return
    controller.player_resources_changed.connect(_on_player_resources_changed)
    _refresh()

func set_peer(p_peer_id: int) -> void:
    peer_id = p_peer_id
    _refresh()

func _on_player_resources_changed(changed_peer_id: int) -> void:
    if changed_peer_id == peer_id:
        _refresh()

func _refresh() -> void:
    if controller == null or controller.state == null:
        return
    var p = controller.state.find_player(peer_id)
    if p == null:
        visible = false
        return
    visible = true
    if _name_label != null:
        _name_label.text = p.name
    if _color_swatch != null and p.color_index >= 0 and p.color_index < SEAT_COLORS.size():
        _color_swatch.color = SEAT_COLORS[p.color_index]
    if _chips_label != null:
        _chips_label.text = format_chip_text(p.chips)
    if _crowns_label != null:
        _crowns_label.text = format_crown_text(p.crowns)
    if _heat_label != null:
        _heat_label.text = "Heat: %d (%s)" % [p.heat, heat_band(p.heat)]

# Static formatters (testable without scene instantiation)

static func format_chip_text(chips: int) -> String:
    return "%d chips" % chips

static func format_crown_text(crowns: int) -> String:
    if crowns == 1:
        return "1 Crown"
    return "%d Crowns" % crowns

static func heat_band(heat: int) -> String:
    # Per design §5.3
    if heat <= 2:
        return "Quiet"
    if heat <= 5:
        return "Noticed"
    if heat <= 8:
        return "Hot Seat"
    return "Public Enemy"
```

- [ ] **Step 4: Implement scene**

`scenes/ui/player_panel.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/player_panel.gd" id="1"]

[node name="PlayerPanel" type="PanelContainer"]
script = ExtResource("1")

[node name="VBox" type="VBoxContainer" parent="."]

[node name="NameLabel" type="Label" parent="VBox"]
text = ""

[node name="ColorSwatch" type="ColorRect" parent="VBox"]
custom_minimum_size = Vector2(40, 8)
color = Color(0.5, 0.5, 0.5, 1)

[node name="ChipsLabel" type="Label" parent="VBox"]
text = "0 chips"

[node name="CrownsLabel" type="Label" parent="VBox"]
text = "0 Crowns"

[node name="HeatLabel" type="Label" parent="VBox"]
text = "Heat: 0 (Quiet)"
```

- [ ] **Step 5: Run, watch pass**

Expected: 227/227 tests pass (221 prior + 6 new).

- [ ] **Step 6: Commit**

```
feat(client): PlayerPanel widget with band-coded Heat display

PanelContainer-based per-player HUD card. Renders name + color swatch +
chips + Crowns + Heat with banded label (Quiet/Noticed/Hot Seat/Public
Enemy per design §5.3). Subscribes to MatchController.
player_resources_changed(peer_id) and refreshes on match.

Static formatters (format_chip_text, format_crown_text, heat_band) are
unit-tested without scene instantiation; the @onready node assignments
are exercised only when the scene loads in MatchScene.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 8: `ResolutionOverlay` widget

Pure UI that listens to `MatchController.resolution_step(name, payload)` and appends a formatted line per substep.

**Files:**
- Create: `scripts/ui/resolution_overlay.gd`
- Create: `scenes/ui/resolution_overlay.tscn`
- Create: `tests/unit/test_resolution_overlay.gd`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_resolution_overlay.gd`:
```gdscript
extends GutTest

const ResolutionOverlay = preload("res://scripts/ui/resolution_overlay.gd")

func test_format_busts_with_peer_ids():
    var s = ResolutionOverlay.format_resolution_step("busts", {"bust_peer_ids": [2, 3]})
    assert_true(s.contains("Busts"))
    assert_true(s.contains("2"))
    assert_true(s.contains("3"))

func test_format_busts_with_no_busts():
    var s = ResolutionOverlay.format_resolution_step("busts", {"bust_peer_ids": []})
    assert_true(s.contains("No busts"))

func test_format_cash_outs():
    var s = ResolutionOverlay.format_resolution_step("cash_outs", {"cash_outs": {1: 2.5, 2: 0.0}})
    assert_true(s.contains("Cash-outs"))
    # Specifically check the formatted multiplier rather than just any number
    assert_true(s.contains("2.5x") or s.contains("2.5"))

func test_format_chip_changes():
    var s = ResolutionOverlay.format_resolution_step("chip_changes", {"deltas": [{"peer_id": 1, "delta": 100}, {"peer_id": 2, "delta": -50}]})
    assert_true(s.contains("Chips"))
    assert_true(s.contains("+100"))
    assert_true(s.contains("-50"))

func test_format_crown_awards():
    var s = ResolutionOverlay.format_resolution_step("crown_awards", {"deltas": [{"peer_id": 2, "delta": 1}]})
    assert_true(s.contains("Crown"))

func test_format_painful_reveal_with_winner():
    var s = ResolutionOverlay.format_resolution_step("painful_reveal", {"winner_peer_id": 2, "winner_name": "Maya"})
    assert_true(s.contains("Maya"))

func test_format_unknown_step_returns_step_name():
    var s = ResolutionOverlay.format_resolution_step("custom_step", {})
    assert_true(s.contains("custom_step"))
```

- [ ] **Step 2: Run, watch fail**

Expected: `ResolutionOverlay` script doesn't exist.

- [ ] **Step 3: Implement script**

`scripts/ui/resolution_overlay.gd`:
```gdscript
# Reactive overlay shown during the RESOLUTION phase. Listens to
# MatchController.resolution_step and appends formatted lines as the
# substep pipeline progresses. Cleared at the start of each new event.
extends PanelContainer

@onready var _lines: VBoxContainer = $VBox/Lines if has_node("VBox/Lines") else null

var controller  # MatchController-like

func _ready() -> void:
    if controller == null:
        return
    controller.resolution_step.connect(_on_resolution_step)
    controller.phase_changed.connect(_on_phase_changed)

func _on_phase_changed(phase: int) -> void:
    var MatchPhase = load("res://scripts/match/match_phase.gd")
    # Clear at the start of each event (HOUSE_REVEAL marks the boundary).
    if phase == MatchPhase.Phase.HOUSE_REVEAL:
        _clear_lines()

func _on_resolution_step(step_name: String, payload: Dictionary) -> void:
    _append_line(format_resolution_step(step_name, payload))

func _clear_lines() -> void:
    if _lines == null:
        return
    for child in _lines.get_children():
        child.queue_free()

func _append_line(text: String) -> void:
    if _lines == null:
        return
    var label = Label.new()
    label.text = text
    _lines.add_child(label)

# Static formatter (testable)

static func format_resolution_step(step_name: String, payload: Dictionary) -> String:
    match step_name:
        "busts":
            var ids = payload.get("bust_peer_ids", [])
            if ids.is_empty():
                return "No busts this event."
            var ids_str = ", ".join(ids.map(func(id): return "P%d" % id))
            return "Busts: %s" % ids_str
        "cash_outs":
            var co = payload.get("cash_outs", {})
            var parts: Array = []
            for pid in co.keys():
                parts.append("P%d cashed at %.2fx" % [pid, co[pid]])
            if parts.is_empty():
                return "Cash-outs: none."
            return "Cash-outs: %s" % ", ".join(parts)
        "chip_changes":
            var deltas = payload.get("deltas", [])
            var parts: Array = []
            for d in deltas:
                var sign = "+" if int(d.get("delta", 0)) > 0 else ""
                parts.append("P%d %s%d" % [int(d.get("peer_id", 0)), sign, int(d.get("delta", 0))])
            if parts.is_empty():
                return "Chips: no change."
            return "Chips: %s" % ", ".join(parts)
        "crown_awards":
            var deltas = payload.get("deltas", [])
            if deltas.is_empty():
                return "No Crown awarded."
            var parts: Array = []
            for d in deltas:
                parts.append("P%d gets %d Crown" % [int(d.get("peer_id", 0)), int(d.get("delta", 0))])
            return "Crowns: %s" % ", ".join(parts)
        "painful_reveal":
            var name = payload.get("winner_name", "")
            var pid = payload.get("winner_peer_id", 0)
            if name != "":
                return "Painful reveal: %s wins the event." % name
            return "Painful reveal: P%d wins." % pid
        _:
            return "(%s)" % step_name
```

- [ ] **Step 4: Implement scene**

`scenes/ui/resolution_overlay.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/resolution_overlay.gd" id="1"]

[node name="ResolutionOverlay" type="PanelContainer"]
script = ExtResource("1")

[node name="VBox" type="VBoxContainer" parent="."]

[node name="Title" type="Label" parent="VBox"]
text = "Resolution"

[node name="Lines" type="VBoxContainer" parent="VBox"]
```

- [ ] **Step 5: Run, watch pass**

Expected: 234/234 tests pass (227 prior + 7 new).

- [ ] **Step 6: Commit**

```
feat(client): ResolutionOverlay widget with substep formatters

PanelContainer that subscribes to MatchController.resolution_step and
appends formatted lines per substep. Cleared at HOUSE_REVEAL of the
next event. format_resolution_step handles all 5 substep names with
graceful fallbacks for missing payload keys.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 9: `MatchEndOverlay` widget

Shown when `match_ended` fires. Lists ranked players. Host sees Back-to-Lobby button.

**Files:**
- Create: `scripts/ui/match_end_overlay.gd`
- Create: `scenes/ui/match_end_overlay.tscn`
- Create: `tests/unit/test_match_end_overlay.gd`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_match_end_overlay.gd`:
```gdscript
extends GutTest

const MatchEndOverlay = preload("res://scripts/ui/match_end_overlay.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(name: String, crowns: int, chips: int, heat: int) -> RefCounted:
    var p = MatchPlayer.new()
    p.name = name; p.crowns = crowns; p.chips = chips; p.heat = heat
    return p

func test_format_rankings_lists_in_order():
    var rankings = [
        _make_player("Alice", 3, 700, 2),
        _make_player("Bob", 2, 800, 1),
        _make_player("Carol", 0, 500, 5),
    ]
    var s = MatchEndOverlay.format_match_end_rankings(rankings)
    var alice_pos = s.find("Alice")
    var bob_pos = s.find("Bob")
    var carol_pos = s.find("Carol")
    assert_true(alice_pos < bob_pos, "Alice listed before Bob")
    assert_true(bob_pos < carol_pos, "Bob listed before Carol")

func test_format_rankings_shows_winner_first_line():
    var rankings = [_make_player("Alice", 5, 800, 0)]
    var s = MatchEndOverlay.format_match_end_rankings(rankings)
    assert_true(s.contains("Alice"))
    assert_true(s.contains("Winner"))

func test_format_rankings_shows_crowns_chips_heat():
    var rankings = [_make_player("Alice", 3, 750, 2)]
    var s = MatchEndOverlay.format_match_end_rankings(rankings)
    assert_true(s.contains("3"))    # crowns
    assert_true(s.contains("750"))  # chips
    assert_true(s.contains("2"))    # heat

func test_format_rankings_handles_empty_list():
    var s = MatchEndOverlay.format_match_end_rankings([])
    assert_true(s.contains("No rankings"))
```

- [ ] **Step 2: Run, watch fail**

Expected: `MatchEndOverlay` script doesn't exist.

- [ ] **Step 3: Implement script**

`scripts/ui/match_end_overlay.gd`:
```gdscript
# Shown when MatchController.match_ended fires. Displays ranked players
# plus a Back-to-Lobby button (host-only) and a Quit button (everyone).
extends PanelContainer

@onready var _rankings_label: Label = $VBox/RankingsLabel if has_node("VBox/RankingsLabel") else null
@onready var _back_button: Button = $VBox/Buttons/BackToLobbyButton if has_node("VBox/Buttons/BackToLobbyButton") else null
@onready var _quit_button: Button = $VBox/Buttons/QuitButton if has_node("VBox/Buttons/QuitButton") else null

var controller  # MatchController-like
var is_host: bool = false

signal back_to_lobby_pressed
signal quit_pressed

func _ready() -> void:
    visible = false
    if controller != null:
        controller.match_ended.connect(_on_match_ended)
    if _back_button != null:
        _back_button.visible = is_host
        _back_button.pressed.connect(func(): back_to_lobby_pressed.emit())
    if _quit_button != null:
        _quit_button.pressed.connect(func(): quit_pressed.emit())

func _on_match_ended(rankings: Array) -> void:
    visible = true
    if _rankings_label != null:
        _rankings_label.text = format_match_end_rankings(rankings)

# Static formatter (testable)

static func format_match_end_rankings(rankings: Array) -> String:
    if rankings.is_empty():
        return "No rankings."
    var lines: Array = []
    for i in rankings.size():
        var p = rankings[i]
        var rank_label = "Winner: " if i == 0 else "%d. " % (i + 1)
        lines.append("%s%s — %d Crowns, %d chips, Heat %d" % [rank_label, p.name, p.crowns, p.chips, p.heat])
    return "\n".join(lines)
```

- [ ] **Step 4: Implement scene**

`scenes/ui/match_end_overlay.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/match_end_overlay.gd" id="1"]

[node name="MatchEndOverlay" type="PanelContainer"]
script = ExtResource("1")

[node name="VBox" type="VBoxContainer" parent="."]

[node name="Title" type="Label" parent="VBox"]
text = "Match End"

[node name="RankingsLabel" type="Label" parent="VBox"]
text = ""

[node name="Buttons" type="HBoxContainer" parent="VBox"]

[node name="BackToLobbyButton" type="Button" parent="VBox/Buttons"]
text = "Back to Lobby"

[node name="QuitButton" type="Button" parent="VBox/Buttons"]
text = "Quit"
```

- [ ] **Step 5: Run, watch pass**

Expected: 238/238 tests pass (234 prior + 4 new).

- [ ] **Step 6: Commit**

```
feat(client): MatchEndOverlay widget with rankings + buttons

PanelContainer hidden by default. On match_ended fires, becomes visible
and renders ranked players via format_match_end_rankings. Host sees
Back-to-Lobby button (hidden for non-host); Quit visible to everyone.
Both buttons emit signals that MatchScene wires to NetSession actions.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 4: Scene wiring

### Task 10: `MatchScene.tscn` + `match_scene.gd`

Composes everything: builds MatchController from `NetSessionMain.get_last_match_start()`, hosts PlayerPanels HBox, PhaseIndicator Label, EventSlot Container, ResolutionOverlay, MatchEndOverlay, PauseOverlay.

**Files:**
- Create: `scripts/ui/match_scene.gd`
- Create: `scenes/match_scene.tscn`
- Create: `tests/unit/test_match_scene.gd`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_match_scene.gd`:
```gdscript
extends GutTest

const MatchScene = preload("res://scripts/ui/match_scene.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")

func test_format_phase_indicator_event_one_of_five():
    var s = MatchScene.format_phase_indicator(0, 5, MatchPhase.Phase.HOUSE_REVEAL)
    assert_true(s.contains("Event 1/5"))
    assert_true(s.contains("HOUSE_REVEAL"))

func test_format_phase_indicator_event_three_of_five():
    var s = MatchScene.format_phase_indicator(2, 5, MatchPhase.Phase.MAIN_EVENT)
    assert_true(s.contains("Event 3/5"))
    assert_true(s.contains("MAIN_EVENT"))

func test_format_phase_indicator_match_end():
    var s = MatchScene.format_phase_indicator(4, 5, MatchPhase.Phase.MATCH_END)
    assert_true(s.contains("Match End"))

func test_format_phase_indicator_unknown_phase():
    var s = MatchScene.format_phase_indicator(0, 5, 999)
    assert_true(s.contains("UNKNOWN"))
```

- [ ] **Step 2: Run, watch fail**

Expected: `MatchScene` script doesn't exist.

- [ ] **Step 3: Implement script**

`scripts/ui/match_scene.gd`:
```gdscript
# The match scene. Replaces sub-project #1's placeholder_match.tscn in the
# Lobby → Match transition. Builds and owns a MatchController, populates
# 8 PlayerPanel widgets, drives the PhaseIndicator, loads the current
# event into EventSlot, and shows ResolutionOverlay / MatchEndOverlay /
# PauseOverlay reactively.
extends Control

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const PlayerPanelScene = preload("res://scenes/ui/player_panel.tscn")
const ResolutionOverlayScene = preload("res://scenes/ui/resolution_overlay.tscn")
const MatchEndOverlayScene = preload("res://scenes/ui/match_end_overlay.tscn")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")

@onready var _player_panels: HBoxContainer = $VBox/PlayerPanels if has_node("VBox/PlayerPanels") else null
@onready var _phase_indicator: Label = $VBox/PhaseIndicator if has_node("VBox/PhaseIndicator") else null
@onready var _event_slot: Container = $VBox/EventSlot if has_node("VBox/EventSlot") else null
@onready var _resolution_slot: Container = $VBox/ResolutionSlot if has_node("VBox/ResolutionSlot") else null
@onready var _match_end_slot: Container = $VBox/MatchEndSlot if has_node("VBox/MatchEndSlot") else null
@onready var _pause_overlay: PanelContainer = $PauseOverlay if has_node("PauseOverlay") else null

var session  # NetSession-like
var controller: MatchController = null
var _current_event_scene: Node = null

func _ready() -> void:
    if session == null and get_tree().root.has_node("NetSessionMain"):
        session = get_tree().root.get_node("NetSessionMain").session
    if session == null:
        push_warning("MatchScene has no session")
        return
    var match_start = _read_match_start()
    if match_start == null:
        push_error("MatchScene: no MatchStart available; cannot run match")
        return
    controller = MatchController.new(session.is_host, self)
    add_child(controller)
    controller.phase_changed.connect(_on_phase_changed)
    controller.event_starting.connect(_on_event_starting)
    controller.match_ended.connect(_on_match_ended)
    controller.request_return_to_lobby.connect(_on_request_return_to_lobby)
    session.state_changed.connect(_on_session_state_changed)
    _build_player_panels(match_start)
    _build_overlays()
    if session.is_host:
        controller.start_match(match_start)

func _read_match_start():
    if not get_tree().root.has_node("NetSessionMain"):
        return null
    var nsm = get_tree().root.get_node("NetSessionMain")
    if not nsm.has_method("get_last_match_start"):
        return null
    return nsm.get_last_match_start()

func _build_player_panels(match_start) -> void:
    if _player_panels == null:
        return
    for seat in match_start.seats:
        var panel = PlayerPanelScene.instantiate()
        panel.controller = controller
        _player_panels.add_child(panel)
        panel.set_peer(seat.peer_id)

func _build_overlays() -> void:
    if _resolution_slot != null:
        var ro = ResolutionOverlayScene.instantiate()
        ro.controller = controller
        _resolution_slot.add_child(ro)
    if _match_end_slot != null:
        var meo = MatchEndOverlayScene.instantiate()
        meo.controller = controller
        meo.is_host = session.is_host
        meo.back_to_lobby_pressed.connect(_on_back_to_lobby_pressed)
        meo.quit_pressed.connect(_on_quit_pressed)
        _match_end_slot.add_child(meo)

func _on_phase_changed(phase: int) -> void:
    if _phase_indicator != null:
        _phase_indicator.text = format_phase_indicator(controller.state.event_index, MatchConfig.QUICK_CLASH_EVENT_COUNT, phase)

func _on_event_starting(event_id: String, _event_index: int) -> void:
    _unload_current_event()
    if _event_slot == null:
        return
    var ps = load(event_id)
    if ps == null:
        push_warning("Failed to load event: %s" % event_id)
        return
    _current_event_scene = ps.instantiate()
    _event_slot.add_child(_current_event_scene)

func _unload_current_event() -> void:
    if _current_event_scene == null:
        return
    _current_event_scene.queue_free()
    _current_event_scene = null

func _on_match_ended(_rankings) -> void:
    _unload_current_event()

func _on_session_state_changed(state: int) -> void:
    if _pause_overlay != null:
        _pause_overlay.visible = (state == NetSessionState.State.PAUSED)
    if controller != null:
        if state == NetSessionState.State.PAUSED:
            controller.pause()
        else:
            controller.resume()

func _on_back_to_lobby_pressed() -> void:
    if session.is_host:
        session.return_to_lobby()       # NetSession state transition
        controller.return_to_lobby()    # broadcasts _rpc_return_to_lobby to remote peers
        # _rpc_return_to_lobby is "call_remote" so the host itself doesn't
        # receive it. Fire the local handler directly so the host's scene
        # also swaps back to Lobby.
        _on_request_return_to_lobby()

func _on_request_return_to_lobby() -> void:
    get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_quit_pressed() -> void:
    session.leave_session()
    get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# Static formatter (testable). Takes total_events as a parameter so the
# caller chooses the count (production passes MatchConfig.QUICK_CLASH_EVENT_COUNT).
static func format_phase_indicator(event_index: int, total_events: int, phase: int) -> String:
    if phase == MatchPhase.Phase.MATCH_END:
        return "Match End"
    var phase_name = MatchPhase.name_for(phase)
    return "Event %d/%d: %s" % [event_index + 1, total_events, phase_name]
```

- [ ] **Step 4: Implement scene**

`scenes/match_scene.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/match_scene.gd" id="1"]

[node name="MatchScene" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="VBox" type="VBoxContainer" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0

[node name="PhaseIndicator" type="Label" parent="VBox"]
text = "Loading match..."

[node name="PlayerPanels" type="HBoxContainer" parent="VBox"]

[node name="EventSlot" type="Container" parent="VBox"]
custom_minimum_size = Vector2(0, 200)

[node name="ResolutionSlot" type="Container" parent="VBox"]

[node name="MatchEndSlot" type="Container" parent="VBox"]

[node name="PauseOverlay" type="PanelContainer" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0
visible = false

[node name="PauseLabel" type="Label" parent="PauseOverlay"]
text = "Paused (player disconnected)"
```

- [ ] **Step 5: Run, watch pass**

Expected: 242/242 tests pass (238 prior + 4 new).

- [ ] **Step 6: Commit**

```
feat(client): MatchScene composes controller + HUD widgets

Replaces sub-project #1's placeholder_match.tscn flow target. Reads
MatchStart from NetSessionMain, instantiates MatchController as a child
node, populates 8 PlayerPanel widgets, drives PhaseIndicator via
format_phase_indicator, instantiates the current event into EventSlot
on event_starting, shows ResolutionOverlay + MatchEndOverlay reactively.
PauseOverlay toggles on NetSession.state_changed(PAUSED).

Back-to-Lobby (host) calls both session.return_to_lobby() and
controller.return_to_lobby() so the host transitions NetSession state
and broadcasts the scene-change RPC. Quit calls leave_session and
returns to MainMenu.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 11: Lobby → MatchScene transition

Replace the existing Lobby → `placeholder_match.tscn` transition with Lobby → `match_scene.tscn`. One-line code change plus tests.

**Files:**
- Modify: `scripts/ui/lobby.gd`
- Create: `tests/unit/test_lobby_match_scene_transition.gd`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_lobby_match_scene_transition.gd`:
```gdscript
extends GutTest

func test_lobby_uses_match_scene_path():
    # Verify the scene path string in lobby.gd. This is a guard against
    # future regression to placeholder_match.tscn.
    var lobby_source = FileAccess.get_file_as_string("res://scripts/ui/lobby.gd")
    assert_true(lobby_source.contains("res://scenes/match_scene.tscn"))
    assert_false(lobby_source.contains("res://scenes/placeholder_match.tscn"))

func test_match_scene_file_exists():
    assert_true(ResourceLoader.exists("res://scenes/match_scene.tscn"))
```

- [ ] **Step 2: Run, watch fail**

Expected: lobby.gd still has the placeholder path.

- [ ] **Step 3: Implement**

In `scripts/ui/lobby.gd`, find:
```gdscript
func _on_match_starting(_match_start) -> void:
    get_tree().change_scene_to_file("res://scenes/placeholder_match.tscn")
```

Replace with:
```gdscript
func _on_match_starting(_match_start) -> void:
    get_tree().change_scene_to_file("res://scenes/match_scene.tscn")
```

The placeholder file at `scenes/placeholder_match.tscn` and its script at `scripts/ui/placeholder_match.gd` are no longer referenced from production code. The existing `tests/unit/test_placeholder_match_logic.gd` still exercises the static `format_match_start` helper as a regression check — leave it in place.

- [ ] **Step 4: Run, watch pass**

Expected: 244/244 tests pass (242 prior + 2 new).

- [ ] **Step 5: Commit**

```
feat(client): Lobby transitions to match_scene.tscn on match start

One-line change: _on_match_starting now loads res://scenes/match_scene
.tscn instead of placeholder_match.tscn. The placeholder scene + script
+ test remain for now (test still validates format_match_start). When
events ship in sub-project #3 we can revisit deletion.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 5: Integration + manual playtest

### Task 12: Two-instance integration smoke test

Per spec §9.5: host + joiner connect via real signaling server; click Lobby Start; TestEvent auto-completes; match runs 5 events end-to-end; both peers observe `match_ended` with consistent rankings; return-to-lobby works.

This test is in `tests/integration/` (not `tests/unit/`) because it depends on the running signaling server. It skips cleanly if signaling is unavailable.

**Files:**
- Create: `tests/integration/test_match_runs_five_events.gd`

- [ ] **Step 1: Write the test (no fail-then-pass cycle; it's end-to-end)**

`tests/integration/test_match_runs_five_events.gd`:
```gdscript
# Integration smoke test: real signaling server + WebRTC P2P + Match loop.
# Spawns two NetSession instances in the same process and drives them
# through Lobby → MatchScene → 5 TestEvents → match_ended.
#
# Skips if signaling server is not reachable on ws://localhost:8080.
extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const WebRTCTransport = preload("res://scripts/net/web_rtc_transport.gd")
const SignalingClient = preload("res://scripts/net/signaling_client.gd")
const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")

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

func test_two_peers_complete_five_events():
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

    # Wait for both peers to be in LOBBY state with each other.
    await _wait_until(func(): return host.players.size() == 2 and joiner.players.size() == 2, CONNECTION_TIMEOUT_SEC)
    assert_eq(host.players.size(), 2, "host sees both players")

    # Capture MatchStart on both peers BEFORE start_match fires the signal.
    var host_match_start = [null]    # [0] is the captured value
    var joiner_match_start = [null]
    host.match_starting.connect(func(ms): host_match_start[0] = ms)
    joiner.match_starting.connect(func(ms): joiner_match_start[0] = ms)

    # Host marks both ready, then starts the match.
    host.set_ready(true)
    joiner.set_ready(true)
    host.start_match()

    # Wait for the joiner to receive its MatchStart over the wire.
    await _wait_until(func(): return host_match_start[0] != null and joiner_match_start[0] != null, CONNECTION_TIMEOUT_SEC)
    var host_ms = host_match_start[0]
    var joiner_ms = joiner_match_start[0]
    assert_not_null(host_ms, "host got MatchStart")
    assert_not_null(joiner_ms, "joiner got MatchStart")

    # Create controllers; only host runs the simulation. Joiner is a mirror.
    var host_controller = MatchController.new(true, host)
    var joiner_controller = MatchController.new(false, joiner)
    add_child_autofree(host_controller)
    add_child_autofree(joiner_controller)

    # Speed up the run by overriding all the timer seams
    host_controller.no_op_phase_delay_ms_override = 10
    host_controller.resolution_step_delay_ms_override = 10
    host_controller.event_timeout_sec_override = 5.0
    joiner_controller.no_op_phase_delay_ms_override = 10
    joiner_controller.resolution_step_delay_ms_override = 10

    var host_match_ended = false
    var joiner_match_ended = false
    var host_final_rankings: Array = []
    var joiner_final_rankings: Array = []
    host_controller.match_ended.connect(func(r): host_match_ended = true; host_final_rankings = r)
    joiner_controller.match_ended.connect(func(r): joiner_match_ended = true; joiner_final_rankings = r)

    host_controller.start_match(host_ms)
    # Joiner doesn't call start_match; it receives _rpc_phase_changed etc.

    # Wait up to MATCH_TIMEOUT_SEC for both controllers to observe match_ended
    await _wait_until(func(): return host_match_ended and joiner_match_ended, MATCH_TIMEOUT_SEC)

    assert_true(host_match_ended, "host saw match_ended")
    assert_true(joiner_match_ended, "joiner saw match_ended")
    assert_eq(host_final_rankings.size(), 2)
    assert_eq(joiner_final_rankings.size(), 2)
    # Both should see the same winner peer_id
    assert_eq(host_final_rankings[0].peer_id, joiner_final_rankings[0].peer_id, "consistent winner")

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

- [ ] **Step 2: Run, observe outcome**

Run from project root:
```
cd ../signaling-server && node server.js &  # in another terminal
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/integration -gexit
```

Expected outcomes:
- If signaling running: test passes, both peers see `match_ended` with same winner.
- If signaling not running: test is marked PENDING.

- [ ] **Step 3: Document**

If the test exposes integration bugs (state divergence, RPC ordering, etc.), debug and fix MatchController; re-run. Multi-iteration debugging is expected here — this is the first time the full stack runs end-to-end.

**Common failure modes to debug:**
- **Joiner-side `match_starting` not firing.** In the current `scripts/net/net_session.gd`, only the host's `NetSession` emits `match_starting` from `start_match()`. The joiner has no wire-level path that synthesizes a `MatchStart` and emits the signal locally. This is the MOST LIKELY first-run failure. Workarounds, in order of preference: (a) make the host broadcast the serialized `MatchStart` via a fresh WebRTC channel message that the joiner's `NetSession` re-emits as `match_starting` (production fix; small extension to sub-project #1 surface), OR (b) for the integration test only, skip the joiner-side wait and reuse `host_ms` for `joiner_controller` initialization (`joiner_match_start[0] = host_ms.duplicate(true)` workaround), OR (c) defer the integration test until sub-project #1's match-start broadcast lands. Recommendation: do (a) — it's a small change to `NetSession.start_match` that's a real prerequisite for any sub-project #3+ networked play.
- Client's `find_player` returns null because `_rpc_phase_changed` fires before the client has built its player list. The joiner_controller starts with an empty `state.players` array because we don't call `start_match()` on it. **Mitigation:** seed the joiner's `state.players` from `joiner_ms.seats` mirroring the host's `start_match` player-build loop, OR extend `_rpc_phase_changed` to carry an initial `players` payload on the first call.
- Race between `match_starting` signal and `MatchController.start_match` being called. **Mitigation:** in production MatchScene's `_ready` reads the cached MatchStart synchronously; the test mirrors this.
- WebRTC channel reliability — sub-project #1 already validated this; if it regresses, fix in NetSession not MatchController.

- [ ] **Step 4: Commit**

```
test(client): integration smoke test — 2 peers complete 5 events

tests/integration/test_match_runs_five_events.gd spawns host + joiner
NetSessions in-process, connects via real signaling, starts a match,
runs 5 TestEvents end-to-end with shortened timers, asserts both peers
observe match_ended with the same winner peer_id.

Skips with PENDING if signaling not reachable at ws://localhost:8080.
Run from project root with the signaling server running in another shell.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 13: Update `docs/PLAYTEST_CHECKLIST.md` for sub-project #2

Append the scenarios from spec §9.6 to the existing playtest checklist.

**Files:**
- Modify: `docs/PLAYTEST_CHECKLIST.md`

- [ ] **Step 1: Append the sub-project #2 section**

Append the following block to `docs/PLAYTEST_CHECKLIST.md` (after the existing sub-project #1 content):

```markdown

## Sub-project #2: Match Loop & Economy Core (Plan B)

Plan reference: docs/superpowers/specs/2026-05-11-match-loop-and-economy-design.md §9.6
Implemented: 2026-05-11

Run by launching two `godot --path .` windows on this machine; click Host in one, Join with the host's code in the other.

| # | Scenario | Status | Notes |
|---|----------|--------|-------|
| 1 | Match runs all 5 events without errors | USER | Both peers should see PhaseIndicator advance through 5 × HOUSE_REVEAL → ... → HOUSE_TWIST cycle. |
| 2 | Player panels update on resource changes | USER | After each event, chip / Crown / Heat values update on both peers. |
| 3 | Phase indicator advances correctly | USER | Text reads "Event N/5: PHASE_NAME" throughout. |
| 4 | Resolution overlay shows substeps with readable pacing | USER | 5 substep lines appear with ~600ms between them. |
| 5 | Ante skip works when a player has 0 chips | USER | Set a player's chips to 0 via debug; ANTE phase marks them inactive; event continues with remaining players. |
| 6 | Match ends correctly; rankings displayed | USER | After event 5, MatchEndOverlay shows ranked players. |
| 7 | Back-to-Lobby returns all peers to Lobby scene | USER | Host clicks Back; both peers' scenes change to Lobby. |
| 8 | Quit returns the quitting peer to MainMenu | USER | Anyone clicks Quit; just that peer goes back to MainMenu; other peer stays in match (or shows host-disconnected message if host quit). |
```

- [ ] **Step 2: Commit**

```
docs(client): playtest checklist additions for sub-project #2

Appends the 8 manual playtest scenarios from spec §9.6 — match runs 5
events, player panels reactive, phase indicator, resolution overlay
pacing, ante skip, match end UI, back-to-lobby, and quit. All marked
USER status (run by launching two godot windows on this machine).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Done

When all checkboxes above are checked, sub-project #2 is complete:

1. **End-to-end pacing.** No-op phases auto-advance via `_schedule_advance`; resolution substeps await `MatchConfig.RESOLUTION_STEP_DELAY_MS`; MAIN_EVENT has a per-event watchdog Timer. The full 5-event Quick Clash now runs without manual `_advance_phase` calls.
2. **Two-peer RPC sync.** Host broadcasts phase changes, deltas, resolution steps, match_ended, and return-to-lobby intent. Clients mirror state via @rpc receivers.
3. **HUD.** Three reactive widgets (`PlayerPanel`, `ResolutionOverlay`, `MatchEndOverlay`) wire to MatchController signals. All formatters unit-tested.
4. **MatchScene.** Composes everything; reads `MatchStart` from `NetSessionMain.get_last_match_start()`; hosts the controller's lifecycle; reacts to pause / match_ended / return-to-lobby.
5. **Lobby integration.** Lobby's `_on_match_starting` now transitions to `match_scene.tscn`.
6. **Integration smoke test.** Two peers complete 5 TestEvents with consistent rankings under the real signaling server + WebRTC stack.
7. **~240 unit + 2 integration tests passing** (up from 196 + 1 baseline).
8. **Updated playtest checklist** with 8 manual scenarios from spec §9.6.

**Next step:** Sub-project #3 (Rocket Clash). The first real event. Will validate the EventNode contract by replacing TestEvent in `MatchConfig.EVENT_POOL` with a real game loop. Brainstorm via `superpowers:brainstorming` when ready.

**Tag this milestone after Plan B merges:** `match-ui-v0.1` and `subproject-2-complete`.
