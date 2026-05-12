# Rocket Clash Event — Design Spec

**Project:** Risk Royal (Godot 4.6)
**Sub-project:** #3 of ~7 — Rocket Clash (validates the EventNode contract)
**Date:** 2026-05-12
**Status:** Approved for planning

---

## 1. Context

Sub-project #2 (Match Loop & Economy Core) shipped the headless match engine plus the visible HUD, scheduler, and RPC scaffolding (tags: `match-engine-v0.1`, `match-ui-v0.1`, `subproject-2-complete`). It established the `EventNode` contract: each event is a `.tscn` extending `EventNode`, owns its scene + real-time RPCs, and returns an `EventResult` with per-player deltas + a `painful_reveal` payload. The current `MatchConfig.EVENT_POOL` ships only `TestEvent` — a deterministic stub that proves the contract.

This sub-project replaces TestEvent with **Rocket Clash**, the design doc's flagship event (§10). After this lands, the MVP can run a real signature event end-to-end across two peers. The remaining sub-projects (#4 power cards, #5 more events, #6 twists, #7 polish) layer on top without restructuring this contract.

**Position in the MVP decomposition:**
1. ✅ Networking & Lobby Foundation
2. ✅ Match Loop & Economy Core
3. ← **this spec**
4. Power Cards & Bounties
5. Bomb Pot + Card Cannon
6. House Twists
7. Polish pass

## 2. Goals

- Players cash out of a real-time rising-multiplier rocket; survivors collect `wager × cash_out_at` chips; busts lose their wager; the highest-cash-out survivor earns 1 Crown.
- Two peers stay in lock-step on multiplier display via deterministic time-based sync.
- Host stays authoritative on cash-out timing and the hidden crash point.
- A new `BET_LOADOUT` phase becomes a real phase (currently a no-op pass-through), letting players place an extra wager beyond the ante.
- `ResolutionOverlay`'s `painful_reveal` substep is extended to show Rocket Clash's full crash readout (actual crash multiplier + per-player table).
- The sub-project #1 + #2 contracts (NetSession surface, EventNode contract, RPC pipeline) require **no spec changes** — sub-project #3 is purely additive on top.
- Bundled fix: Plan B's production RPC wiring follow-up (`_multiplayer_node` target) so Rocket Clash's new RPCs actually route in production.

## 3. Non-Goals

- No battle output / damage / combat system. Design doc §10.4 lists a battle-energy formula; no combat exists in the MVP yet to consume it. Defer to a later combat sub-project (not on the current 7-sub-project list).
- No power-card hooks (sub-project #4): Afterburner, Emergency Eject, Cash-Out Jammer, Black Box, Fuel Leak, Copy Eject, Heat Shield.
- No bounty integration (sub-project #4): "bounty mode" where players earn bonus rewards for beating a target's cash-out.
- No alternate Crown objectives (sub-project #6 House Twists rotates them). MVP locks Crown to "highest cash-out among survivors".
- No Team Rocket / linked-rocket variant.
- No visual polish: explosions, particles, audio, screen shake, announcer voice (sub-project #7).
- No replay / event log / "you were 0.12x away" near-miss callouts beyond a plain text rendering of crash vs cash-out values.
- No persistent crash-distribution tuning / provably-fair display. Aviator math is seeded from the existing `EventContext.rng_seed`.

## 4. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope envelope | Standard + extra wager | Validates the contract under realistic event complexity (per-event UI, real-time RPCs, painful_reveal payload). Defers everything explicitly future (cards, bounties, combat). |
| Wager UI location | `BET_LOADOUT` phase (was no-op pass-through) | Sub-project #2 explicitly reserved this phase for wager + power-card input. Reusing it here unblocks sub-project #4 instead of postponing the phase upgrade. |
| Crown objective | Highest cash-out among survivors | Simple, deterministic, clearly tied to skill+risk. If all bust, no Crown that event. Other 3 design-doc objectives rotate via sub-project #6 House Twists. |
| Crash distribution | Aviator-style formula | 5% instabust at 1.00x; otherwise `max(1.0, 0.99 / (1 − rng.randf()))`, capped at 100.0. Matches design doc §10.5 distribution shape with no hand-tuning. |
| Multiplier sync | Deterministic time-based | Host broadcasts `_rpc_rocket_launched(start_time_ms, crash_at)` once. Peers compute `multiplier_at(t) = exp(GROWTH_RATE × elapsed)` locally. Cash-outs flow client→host with snapshot validation. Cheap on the wire; low-latency UI; standard crash-game architecture. |
| Multiplier growth rate | `0.06` per second exponential (≈6%/sec) | Matches Aviator-class pacing; rocket reaches 2x at ~12s, 5x at ~27s, 10x at ~38s. Lives in `MatchConfig.ROCKET_GROWTH_RATE` for easy playtest tuning. |
| Cash-out validation | Snapshot tolerance | Client sends its local `snapshot_mult`; host accepts if `abs(snapshot − host_mult) < CASH_OUT_TOLERANCE` (0.05). Otherwise rejects (the player busts on their local display anyway). |
| Painful reveal rendering | Extend ResolutionOverlay formatter | Add Rocket-Clash-aware branch to `format_resolution_step("painful_reveal", ...)` when `crash_at` + `cash_outs_summary` keys present. Falls back to existing winner-only format for TestEvent. |
| Bundled fixes | Plan B C1 (`_multiplayer_node` self-wire) | Rocket Clash's RPCs need real Godot routing; the Plan B production bug must land here or sub-project #3 ships broken. |

## 5. Architecture

Three layers building on existing sub-project #2 infrastructure.

### 5.1 Event scene layer

`RocketClashEvent` (extends `EventNode`) lives entirely under `scripts/events/rocket_clash/`. Its `.tscn` owns its visual surface: a rocket altitude display, current-multiplier readout, per-player status panels (in / cashed_at / busted), and a local Cash Out button. The scene IS the MAIN_EVENT — when `MatchController._process_main_event` instantiates the event via `_event_factory`, the scene tree owns it until `event_complete(result)` fires.

The event holds its own per-round state: `_crash_at: float`, `_start_time_ms: int`, `_cash_outs: Dictionary` (peer_id → cash_out_at), `_active_peers: Array[int]`, `_rng: RandomNumberGenerator`. Multiplier display is computed locally every frame from elapsed time, so display stays smooth regardless of network latency.

### 5.2 Networking layer

Rocket Clash uses three `@rpc` methods on the event node itself (not on MatchController). Per the spec §5.4 contract: "During a MAIN_EVENT phase, the event itself owns its real-time RPCs." MatchController stays out of the rocket loop entirely.

```
Event flow (host = is_host=true via EventContext.is_host new field):

Host _run(context):
  _active_peers = [p.peer_id for p in context.players]
  _rng = RandomNumberGenerator.new(); _rng.seed = context.rng_seed
  _crash_at = compute_crash_at(_rng)
  _start_time_ms = Time.get_ticks_msec()
  rpc("_rpc_rocket_launched", _start_time_ms, _crash_at)

All peers _rpc_rocket_launched(start_time_ms, crash_at):
  Store locally; begin _process(delta) multiplier loop.

Client Cash Out pressed:
  snapshot_mult = current_local_multiplier
  rpc_id(host, "_rpc_cash_out_requested", my_peer_id, snapshot_mult)
  Optimistic local UI flip to "cashing out…"

Host _rpc_cash_out_requested(peer_id, snapshot_mult):
  if crash_already_triggered:
    rpc_id(peer_id, "_rpc_cash_out_rejected", peer_id)
  elif peer_id in _cash_outs:
    silently drop (double-click guard)
  elif abs(snapshot - host_current_mult) > CASH_OUT_TOLERANCE:
    rpc_id(peer_id, "_rpc_cash_out_rejected", peer_id)
  else:
    accepted_mult = host_current_mult  # host-authoritative
    _cash_outs[peer_id] = accepted_mult
    rpc("_rpc_cash_out_confirmed", peer_id, accepted_mult)

Host-only _process: when local multiplier ≥ _crash_at:
  Build EventResult; emit event_complete(result).
```

### 5.3 BET_LOADOUT phase upgrade

The currently-no-op phase becomes a real one.

- `MatchController._enter_phase_behavior` BET_LOADOUT branch now dispatches to a new `_process_bet_loadout` method.
- `_process_bet_loadout` emits `bet_loadout_started(active_peer_ids, max_per_player)` and starts a Timer for `MatchConfig.BET_LOADOUT_TIMEOUT_SEC` (15s).
- New `@rpc` receiver `_rpc_set_wager(peer_id, amount)` on host: clamps to chip count, writes into `state.pending_wagers[peer_id]`, broadcasts `_rpc_wager_acknowledged(peer_id, clamped_amount)` so all peers' UI can render readied state.
- Advance trigger: all active peer_ids present in `state.pending_wagers` OR timer fires. On advance: any un-set wagers default to 0; `state.pending_wagers` is read into `EventContext.wagers` by the existing `_build_event_context` (replacing the current ante-fallback); then `pending_wagers` is cleared.
- New signal: `bet_loadout_finished` so MatchScene can dismiss the overlay.

### 5.4 Plan B C1 fix (bundled)

Sub-project #2 left `_multiplayer_node` set to MatchScene in production, which is wrong because the @rpc receivers live on MatchController. Fix: in `MatchController.start_match`, add:

```gdscript
if _multiplayer_node == null and is_inside_tree():
    _multiplayer_node = self
```

Tests with detached controllers keep `_multiplayer_node = null` and `_send_rpc` no-ops as before. The flaky test that tripped this fix in Plan B's final review is already resolved on main (the timing-sensitive watchdog test now invokes `_on_event_timeout` directly).

## 6. Components

### 6.1 `scripts/events/rocket_clash/rocket_clash_event.gd`

**Extends:** `EventNode` (which extends `Node`)

**Constants (file-local):** `GROWTH_RATE_DEFAULT = 0.06`, `INSTABUST_PROB = 0.05`, `CASH_OUT_TOLERANCE = 0.05`, `MAX_CRASH_AT = 100.0`.

**Fields:** `_crash_at: float`, `_start_time_ms: int`, `_cash_outs: Dictionary`, `_active_peers: Array[int]`, `_rng: RandomNumberGenerator`, `_finished: bool`.

**Test seams:** `_growth_rate_override: float = -1.0` (uses `MatchConfig.ROCKET_GROWTH_RATE` when negative), `_force_crash_at_override: float = -1.0` (skips RNG when positive).

**Public interface (overrides EventNode):**
- `get_event_id() -> String` returns `"rocket_clash"`.
- `_run(context: EventContext)` — entry. Host runs the loop; clients await RPCs.

**Static helpers (testable without scene tree):**
- `compute_crash_at(rng: RandomNumberGenerator) -> float`
- `multiplier_at(elapsed_ms: int, growth_rate: float) -> float`
- `compute_event_result(context, crash_at: float, cash_outs: Dictionary, busted_peer_ids: Array) -> EventResult`

**Real-time loop:** `_process(delta)` computes elapsed since `_start_time_ms`; updates the multiplier label; on host, triggers `_finish()` once when multiplier ≥ `_crash_at`.

**RPC methods (all `@rpc("any_peer", "call_local", "reliable")` except cash-out request which is `call_remote`):**
- `_rpc_rocket_launched(start_time_ms: int, crash_at: float)` — host → all
- `_rpc_cash_out_requested(peer_id: int, snapshot_mult: float)` — client → host only
- `_rpc_cash_out_confirmed(peer_id: int, accepted_mult: float)` — host → all
- `_rpc_cash_out_rejected(peer_id: int)` — host → originating client

**Depends on:** `EventContext`, `EventResult`, `MatchConfig`, `EventNode` (base class).

### 6.2 `scripts/events/rocket_clash/rocket_clash_event.tscn`

Scene tree: root `RocketClashEvent` (Node, attached script) → `VBox` containing `MultiplierLabel` (large "2.34x" display), `StatusGrid` (HBox of per-player mini-cards showing name + status: in/cashed/busted + cash-out value), and `CashOutButton` (the local player's button; disabled when local player has cashed/busted/inactive).

### 6.3 `scripts/ui/bet_loadout_overlay.gd` + `scenes/ui/bet_loadout_overlay.tscn`

Shown during BET_LOADOUT phase. Composed in MatchScene's new `BetLoadoutSlot` container.

**Public:** `set_player(player: MatchPlayer)` populates the local view. `controller: MatchController` injection field (mirrors the other overlay pattern).

**UI:** Renders local player's chips, a slider 0 → `min(player.chips, player.chips × MatchConfig.ROCKET_CLASH_MAX_WAGER_FACTOR)`, a numeric input that mirrors the slider, a Ready button, and a countdown showing BET_LOADOUT remaining time.

**Reactive:** subscribes to `controller.bet_loadout_started` (show), `controller.bet_loadout_finished` (hide). Local Ready button calls `controller.submit_wager(amount)`.

**Static helpers (testable):** `format_wager_summary(chips: int, wager: int) -> String`, `clamp_wager(amount: int, chips: int, max_factor: float) -> int`.

### 6.4 `scripts/match/match_controller.gd` (modify)

Three additions/changes:

1. **BET_LOADOUT phase handler:**
```gdscript
func _process_bet_loadout() -> void:
    state.pending_wagers = {}
    var active = []
    for p in state.players:
        if p.is_active_this_event:
            active.append(p.peer_id)
    bet_loadout_started.emit(active, _max_per_player())
    var timeout_sec = _bet_loadout_timeout_sec()  # test seam
    var timer = get_tree().create_timer(timeout_sec)
    while timer.time_left > 0:
        if _all_active_ready(active):
            break
        await get_tree().process_frame
    bet_loadout_finished.emit()
```
Update `_enter_phase_behavior` BET_LOADOUT branch to `await _process_bet_loadout()` then `await _schedule_advance()`.

2. **Wager pipeline:** new public method `submit_wager(amount: int)` fires `_rpc_set_wager(my_peer_id, amount)`. New `@rpc("any_peer", "call_remote", "reliable")` receiver `_rpc_set_wager(peer_id, amount)` (host clamps, stores in `state.pending_wagers`, broadcasts `_rpc_wager_acknowledged`).

3. **C1 self-wire:** in `start_match`, prepend `if _multiplayer_node == null and is_inside_tree(): _multiplayer_node = self`.

4. **`_build_event_context` change:** when `state.pending_wagers` is non-empty, use it for `ctx.wagers`; otherwise fall back to the existing per-player ante.

**New signals:** `bet_loadout_started(active_peer_ids: Array, max_per_player: int)`, `bet_loadout_finished`.

**New test seams:** `bet_loadout_timeout_sec_override: float = -1.0` (mirror of `event_timeout_sec_override`).

### 6.5 `scripts/match/match_state.gd` (modify)

Add `pending_wagers: Dictionary = {}` field. Round-trip in `to_dict` / `from_dict` (with `.duplicate(true)` to avoid reference aliasing during RPC marshalling).

### 6.6 `scripts/match/match_config.gd` (modify)

Add:
```gdscript
const BET_LOADOUT_TIMEOUT_SEC: int = 15
const ROCKET_CLASH_MAX_WAGER_FACTOR: float = 1.0  # max extra wager = chips × factor
const ROCKET_GROWTH_RATE: float = 0.06            # multiplier(t) = exp(ROCKET_GROWTH_RATE × elapsed_sec)
```

Update `EVENT_POOL` to:
```gdscript
const EVENT_POOL: Array = [
    "res://scripts/events/rocket_clash/rocket_clash_event.tscn",
]
```

(Remove `test_event.tscn` from the pool. TestEvent stays in the codebase for unit tests; the existing `_event_factory` test seam injects MockEvent regardless.)

### 6.7 `scripts/events/event_context.gd` (modify)

Add `is_host: bool` field. Populated by `MatchController._build_event_context` from `self.is_host`. Round-trip in `to_dict` / `from_dict`. Defaults to `false`.

### 6.8 `scripts/ui/resolution_overlay.gd` (modify)

Extend `format_resolution_step` "painful_reveal" branch. When payload contains `crash_at` AND `cash_outs_summary`, render multi-line:

```
CRASH! Rocket exploded at {crash_at}x
  {name}  busted (left {wager} chips on the table)        # if entry.busted
  {name}  {cash_out_at}x  +{chip_delta} chips             # if survivor
                                          (+ "  👑 Crown" if entry.peer_id == winner_peer_id)
```

Fall back to existing single-line winner format when those keys are absent.

`cash_outs_summary` shape: `Array[Dictionary]` where each entry has `{peer_id: int, name: String, cash_out_at: float, chip_delta: int, busted: bool, wager: int}`.

### 6.9 `scripts/ui/match_scene.gd` (modify)

Wire `controller.bet_loadout_started` → `_on_bet_loadout_started` (instantiate `BetLoadoutOverlay` into a new `BetLoadoutSlot` Container; pass `controller` and `local_player`); wire `controller.bet_loadout_finished` → `_on_bet_loadout_finished` (clear the slot). Mirrors the existing ResolutionOverlay / MatchEndOverlay slot pattern.

Add `BetLoadoutSlot` (Container) to `match_scene.tscn` between `EventSlot` and `ResolutionSlot`.

## 7. Data Flow

End-to-end for one rocket round, showing how existing match phases compose with the new event-level RPCs.

### 7.1 BET_LOADOUT phase (new, ~15s)

```
Host enters BET_LOADOUT:
  state.pending_wagers = {}
  bet_loadout_started.emit(active_peer_ids, max_per_player)
  rpc _rpc_phase_changed(BET_LOADOUT, ctx)
  Wait for: (all active in pending_wagers) OR (timer expires).

All peers: MatchScene shows BetLoadoutOverlay
  Local player taps slider + Ready

On Ready (local):
  controller.submit_wager(amount)
    → rpc_id(host, _rpc_set_wager, my_peer_id, amount)

Host _rpc_set_wager(peer_id, amount):
  clamped = clamp(amount, 0, state.find_player(peer_id).chips)
  state.pending_wagers[peer_id] = clamped
  rpc _rpc_wager_acknowledged(peer_id, clamped)

All peers update BetLoadoutOverlay to show "P3 ready: 200" etc.

Advance trigger fires:
  controller.bet_loadout_finished.emit()
  rpc _rpc_phase_changed(MAIN_EVENT, ctx)
  _build_event_context() reads state.pending_wagers into context.wagers
  state.pending_wagers cleared
  → MAIN_EVENT begins
```

### 7.2 MAIN_EVENT (Rocket Clash runs)

```
MatchController._process_main_event:
  Instantiate RocketClashEvent via _event_factory
  Connect event_complete → _on_event_complete
  Emit event_starting; start watchdog (existing Plan B)
  Call event._run(context)

RocketClashEvent._run on host:
  _active_peers = [p.peer_id for p in context.players]
  _rng.seed = context.rng_seed
  _crash_at = compute_crash_at(_rng)
  _start_time_ms = Time.get_ticks_msec()
  rpc _rpc_rocket_launched(_start_time_ms, _crash_at)

All peers _rpc_rocket_launched:
  Store; begin _process loop computing multiplier_at(elapsed)

Per-frame on all peers:
  m = multiplier_at(elapsed_ms, growth_rate)
  if m >= _crash_at: visual crash
    [host only: trigger _finish() once via _finished guard]
  else: update MultiplierLabel

Local Cash Out:
  if local_peer active AND not in _cash_outs AND not busted:
    snapshot = current_multiplier
    rpc_id(host, _rpc_cash_out_requested, my_peer_id, snapshot)
    Optimistic UI: "cashing out…"

Host _rpc_cash_out_requested:
  Validate per §5.2 (crash already? double cash-out? tolerance?)
  Accept: _cash_outs[peer_id] = host_mult; rpc _rpc_cash_out_confirmed
  Reject: rpc_id(originator, _rpc_cash_out_rejected)

All peers _rpc_cash_out_confirmed: StatusGrid card updates to "Cashed at X.XXx"

Host _finish():
  _busted = [pid for pid in _active_peers if pid not in _cash_outs]
  result = compute_event_result(context, _crash_at, _cash_outs, _busted)
  event_complete.emit(result)

MatchController._on_event_complete:
  Existing Plan B behavior: clear watchdog, free event node, _advance_phase
  → RESOLUTION pipeline runs
```

### 7.3 RESOLUTION (existing pipeline + extended formatter)

```
For each substep, MatchController emits resolution_step(name, payload) + RPC:
  "busts"          → {bust_peer_ids: [3]}                       (existing)
  "cash_outs"      → {cash_outs: {1: 2.20, 2: 1.45, 3: 0.0}}    (existing)
  "chip_changes"   → applies chip_delta + player_resources_changed (existing)
  "crown_awards"   → applies crown_delta + player_resources_changed (existing)
  "painful_reveal" → {
       crash_at: 3.42,
       winner_peer_id: 2,
       winner_name: "Maya",
       cash_outs_summary: [
         {peer_id: 1, name: "Alex",   cash_out_at: 0.0,  chip_delta: -100, busted: true,  wager: 100},
         {peer_id: 2, name: "Maya",   cash_out_at: 2.20, chip_delta: +220, busted: false, wager: 100},
         {peer_id: 3, name: "Jordan", cash_out_at: 1.45, chip_delta: +145, busted: false, wager: 100},
       ]
     }

ResolutionOverlay renders:
  CRASH! Rocket exploded at 3.42x
    Alex   busted (left 100 chips on the table)
    Maya   2.20x  +220 chips  👑 Crown
    Jordan 1.45x  +145 chips
```

## 8. Error Handling

### 8.1 BET_LOADOUT failures

| Trigger | Behavior |
|---|---|
| Player disconnects mid-wager | Existing NetSession PAUSED machinery freezes phase advance. Reconnect within 30s resumes. 30s timeout: player removed from active_peer_ids; their wager defaults to 0. |
| Player never presses Ready | Timer expires; their pending_wagers entry is missing; wager defaults to 0. Silent. |
| Client sends wager > chips | Host clamps in `_rpc_set_wager`. Broadcasts the clamped value via `_rpc_wager_acknowledged`. Client UI snaps to host value. |
| Host drops | Existing host-lost flow: clients see session_ended, return to MainMenu after 3s. Match discarded. |

### 8.2 Rocket Clash event failures

| Trigger | Behavior |
|---|---|
| Cash-out arrives after crash | Host detects (crash_at already triggered finish); replies `_rpc_cash_out_rejected`. Originating client's UI reverts to active state; player ends up bust. |
| Cash-out snapshot drift > CASH_OUT_TOLERANCE | Host rejects same as above. Silent — the rocket already crashed visually on that peer, so the bust display is already correct. |
| Client sends cash-out twice (double-click) | Host's first acceptance stores peer_id in `_cash_outs`; second arrives with peer_id already present and is silently dropped (no duplicate `_rpc_cash_out_confirmed`). |
| Host disconnects mid-rocket | Existing host-lost flow. Event state discarded. |
| Client disconnects mid-rocket | Existing pause machinery freezes everyone. On 30s timeout: that peer treated as bust (no cash-out registered); event continues without them. |
| `event_complete` never fires | Existing watchdog (MatchConfig.EVENT_TIMEOUT_SEC = 120s) fires `_on_event_timeout`, synthesizing all-bust zero-delta result. No new code needed. |

### 8.3 Multiplier-math edge cases

| Trigger | Behavior |
|---|---|
| `compute_crash_at` returns < 1.0 (bug) | Clamp via `max(1.0, ...)` in the helper. Unreachable in normal use. |
| `compute_crash_at` returns > 100x (Aviator high tail) | Cap at `MAX_CRASH_AT = 100.0`. |
| `multiplier_at(t)` overflow for huge elapsed | Won't happen in practice (rocket crashes within ~50s for sub-100x). The watchdog fires at 120s anyway. |
| Floating-point drift across peers | Acceptable — display only. Crash trigger and cash-out validation are host-authoritative; client display drift is invisible at typical magnitudes. |

### 8.4 RPC desync / out-of-order

Plan B's spec §8.4 rules carry over:
- Client receives `_rpc_rocket_launched` after already starting: re-read start_time/crash_at; resume display.
- Client receives `_rpc_cash_out_confirmed` for unknown peer_id: silently drop.
- Out-of-order: cash_out_requested before rocket_launched is impossible (gated on local launched-RPC handler).

### 8.5 Wager-math edge cases

| Trigger | Behavior |
|---|---|
| Player has 0 chips after ante | Already handled in ANTE: `is_active_this_event = false`; excluded from BET_LOADOUT active_peer_ids. |
| All active players bust | All `chip_delta = -wager`, all `bust: true`. No survivors → no Crown. painful_reveal still shows crash_at. |
| Only one active player | They face rocket solo. Survive → Crown; bust → no Crown. |
| Player wagers 0 | Allowed. They participate (cash out for 0 chips: `0 × cash_out_at = 0`). Can still win Crown if their cash_out_at is highest. |

### 8.6 Plan B C1 bundled fix

In `MatchController.start_match`: `if _multiplayer_node == null and is_inside_tree(): _multiplayer_node = self`. Production routes via the controller (where @rpc receivers live); tests with detached controllers keep `_multiplayer_node = null` so `_send_rpc` no-ops. No new failure modes.

## 9. Testing

### 9.1 Tier 1 — Static helpers (pure-math GUT)

- `test_rocket_clash_crash_at.gd` — `compute_crash_at(rng)` with seeded RNG. Verify determinism, 5% instabust, cap at 100, histogram across 1000 seeds.
- `test_rocket_clash_multiplier.gd` — `multiplier_at(elapsed_ms, growth_rate)`. Verify `(0, 0.06) → 1.0`, `(10000, 0.06) ≈ 1.822`, monotonic.
- `test_rocket_clash_result.gd` — `compute_event_result(context, crash_at, cash_outs, busted)`. Mix of survivors + busts; Crown to argmax(cash_outs); painful_reveal shape correct; no Crown when all bust.

Target: ~10 tests.

### 9.2 Tier 2 — BET_LOADOUT phase (GUT against fakes)

- `test_match_controller_bet_loadout.gd` — handler runs with `bet_loadout_timeout_sec_override = 0` (test seam). Verify signal emission, pending_wagers cleared on entry, phase advances.
- `submit_wager` host path: stores in pending_wagers; broadcasts `_rpc_wager_acknowledged` (record via FakeMultiplayerNode).
- `_rpc_set_wager` clamps over-wager (5000 → 800 when chips=800).
- "All ready" fast-advance: with slow timer override, all wagers submitted → advance immediately.
- `_build_event_context` reads pending_wagers into context.wagers (200 for P1, 0 default for P2).

Target: ~6 tests.

### 9.3 Tier 3 — Rocket Clash event (GUT with scene tree)

Use `add_child_autofree` since `_process` and Timer-style operations need a real SceneTree.

- `test_rocket_clash_event.gd` — `_run(context)` on host with `_force_crash_at_override = 2.5`. Drive cash-outs via direct `_rpc_cash_out_requested` calls; verify event_complete fires with expected per_player payload.
- Cash-out validation: within tolerance → accepted; out-of-tolerance → rejected.
- Double cash-out: second request for same peer_id silently dropped.
- Non-host: instantiate with `context.is_host = false`; verify no `_rpc_rocket_launched` broadcast.

Target: ~8 tests.

### 9.4 Tier 4 — UI widgets (static formatter GUT)

- `test_bet_loadout_overlay.gd` — `format_wager_summary`, `clamp_wager`.
- `test_resolution_overlay_rocket_painful_reveal.gd` — extends existing `test_resolution_overlay.gd` with the new branch. Verify rendering includes crash_at, each name + cash_out_at, Crown indicator on winner, bust labels. Verify fallback path still works without `crash_at` key.

Target: ~6 tests.

### 9.5 Tier 5 — Integration smoke test

- `tests/integration/test_rocket_clash_runs.gd` — host + joiner via real signaling; seed RNG to land on Rocket Clash; both peers see BetLoadoutOverlay; both submit wagers (host immediately, joiner via timer); MAIN_EVENT runs with `_growth_rate_override = 1.0` (compressed timing) and `_force_crash_at_override = 3.0` (deterministic); both peers see consistent cash_out_confirmed events; after crash both peers see consistent painful_reveal with same winner.
- Skips with `pending()` if signaling not reachable.

Target: 1 integration test.

### 9.6 Manual playtest additions

Append to `docs/PLAYTEST_CHECKLIST.md`:

| # | Scenario | Notes |
|---|---|---|
| 1 | Wager + rocket runs end-to-end | Two windows; both wager; both cash out at different multipliers; both see consistent rankings. |
| 2 | Bust event | Both hold past crash; both -wager; no Crown. |
| 3 | Solo survivor | One cashes early, one busts; survivor gets Crown. |
| 4 | Wager defaults to 0 on timeout | Ignore BET_LOADOUT; event runs with wager=0. |
| 5 | Cash-out near crash | Within 0.1x of expected; verify host accepts/rejects per tolerance. |
| 6 | Five-event match with mixed wagers | Full Quick Clash; chips and Heat update correctly. |

### 9.7 Out of scope for #3's testing

- Latency / jitter simulation infrastructure
- Cash-out tolerance tuning under real conditions (surface in playtest; tune via constants in polish pass)
- Battle-output integration (no combat system yet)

## 10. Open Questions / Future Work

- **Wager max higher than starting chips** — would require Debt system. Out of scope until that lands.
- **Auto cash-out toggle** — UX smoothing for non-card players. Polish sub-project.
- **Crash-distribution tuning** — Aviator's 0.99 numerator gives ~1% house edge; the 5% instabust is independent. Constants exposed via `MatchConfig` so tuning is one edit.
- **Multiplier growth rate (0.06/sec)** — felt right on paper; playtest will validate. Tunable via `MatchConfig.ROCKET_GROWTH_RATE`.

**Future sub-project hooks:**

- **#4 Power Cards & Bounties** — BET_LOADOUT phase grows a "play card" surface; cash-out RPC path can be intercepted by Cash-Out Jammer / Afterburner; bounty resolution reads `painful_reveal` payload. All additive.
- **#5 More events (Bomb Pot, Card Cannon)** — reuse BET_LOADOUT phase as-is; reference Rocket Clash's RPC scaffold as the pattern.
- **#6 House Twists** — rotate Crown objectives (the 4 from design doc §10.9), modify wager limits per-event. Hooks via `EventContext.event_index`.
- **#7 Polish** — particle explosions, audio, screen shake, animated painful_reveal callouts, announcer voice. None touch EventNode contract.

**Bundled with sub-project #3:**
1. Plan B C1 production RPC wiring fix (`_multiplayer_node` self-wire in `start_match`).

**Deferred (NOT bundled):**
- `*.uid` cleanup (separate cleanup pass)
- MatchController size reduction (Plan C cleanup candidate)
- PlayerPanel.set_player vs set_peer spec drift
- return_to_lobby orchestration split between MatchScene and MatchController

## 11. Contract Summary for Downstream Sub-Projects

Sub-project #3 sets the pattern for real events. Sub-project #5 (Bomb Pot + Card Cannon) should mirror this shape:

- **Event scene** at `scripts/events/<event_id>/<event_id>_event.gd` + `.tscn`, extending `EventNode`.
- **Event-owned RPCs** for any real-time multiplayer state (not on MatchController). Host-authoritative validation pattern with snapshot tolerance.
- **Static math helpers** for crash/distribution/result computation, fully unit-tested without scene instantiation.
- **`EventContext.is_host`** field tells the event whether to run host-only logic.
- **`EventResult.painful_reveal`** carries event-specific keys; `ResolutionOverlay.format_resolution_step` is extended with a new branch when this event ships. Falls back to existing render when keys absent.
- **`EventResult.per_player`** entries should include `wager` so the painful_reveal "left X chips on the table" rendering works without re-passing context.
- **BET_LOADOUT phase** is now a real phase any event can use for wager input. Power-card play (sub-project #4) hooks in here.
- **Test seams** mirror the existing pattern: `_growth_rate_override`, `_force_crash_at_override` (for time-based events), `bet_loadout_timeout_sec_override` (for the BET_LOADOUT phase), `_event_factory` injection (existing).

Sub-projects #5+ should NOT:
- Add their RPCs to `MatchController` (events own their own real-time RPCs).
- Restructure `BET_LOADOUT` or `RESOLUTION` phases — extend with new substep payloads instead.
- Persist event state across events. Each `_run(context)` invocation is independent; `EventContext.rng_seed` is the only carry-over.
