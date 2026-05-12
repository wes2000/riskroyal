# Match Loop & Economy Core — Design Spec

**Project:** Risk Royal (Godot 4.6)
**Sub-project:** #2 of ~7 — Match Loop & Economy Core
**Date:** 2026-05-11
**Status:** Approved for planning

---

## 1. Context

Risk Royal is a multiplayer party battle casino game (full design in [`docs/RiskRoyal_DesignDoc.md`](../../RiskRoyal_DesignDoc.md)). The MVP scope (design doc §26) covers a 4-player online lobby running 5-event Quick Clash matches with 3 mini-games, a power-card system, an economy, House Twists, and a shop.

Sub-project #1 (Networking & Lobby Foundation) is complete (tags: `signaling-server-v0.1`, `godot-netsession-v0.1`, `godot-network-v0.1`, `lobby-ui-v0.1`, `subproject-1-complete`). It delivers the connection layer, lobby UI, and the `MatchStart` handoff contract.

This sub-project builds the **match scaffolding** that wraps individual events: a state machine for the 9-phase per-event cycle, the chip / Crown / Heat economy, a generic event interface that future events plug into, and the match-running scene + HUD that replaces sub-project #1's `PlaceholderMatch.tscn`. After this, the MVP can run a complete match — only the events themselves are stubs.

**Position in the MVP decomposition:**
1. ✅ Networking & Lobby Foundation
2. ← **this spec**
3. Rocket Clash (validates the event contract)
4. Power Cards & Bounties
5. Bomb Pot + Card Cannon
6. House Twists
7. Polish pass

## 2. Goals

- The match scene runs a 5-event Quick Clash end-to-end with a stub TestEvent.
- The state machine cycles through all 9 phases per event (per design doc §4.2), with no-op hooks for phases whose behavior lives in future sub-projects.
- Players have authoritative chips, Crowns, and Heat. Antes are deducted; event results apply chip/Crown/Heat deltas via a resolution pipeline.
- A visible HUD shows each player's resources and the current phase/event progress.
- Match end produces a ranking and a back-to-lobby flow.
- A clear event-interface contract that sub-projects #3 and #5 will satisfy without restructuring.

## 3. Non-Goals

- No specific real events. Just one `TestEvent` stub to verify the contract (Rocket Clash, Bomb Pot, Card Cannon come in #3 and #5).
- No power cards, no Bet/Loadout UI (sub-project #4).
- No bounties (sub-project #4).
- No shop (sub-project #4).
- No House Twists (sub-project #6).
- No announcer voice or fancy "painful reveal" juice (sub-project #7).
- No Reputation, no Debt — only chips, Crowns, Heat in the MVP economy.
- No Standard or Long Night mode. Quick Clash 5-event only.
- No replay / event log / save+resume.
- No spectator mid-match join.

## 4. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope envelope | Engine + HUD bundled | Ships a visually playable match scaffolding with stub events. Larger plan but no "second pass" needed. |
| Resources | Chips, Crowns, Heat | MVP per design §26.1. Reputation and Debt deferred. |
| Phase model | Full 9-phase with no-op hooks | Future plans (#4, #6) plug into named phases without restructuring the state machine. |
| Event interface | Event-as-scene with signal contract | Each event owns its own .tscn, visuals, and RPCs. Matches design's "each event is its own showpiece" framing. |
| Event count | 5 (Quick Clash) | Per design §24.2 and §26.1. |
| Event selection | Casino Wheel auto-pick | Only one event in the pool in #2 anyway. Other selection methods (Lowest Picks, Winner Bans, Chip Vote) deferred. |
| Authority model | Host-authoritative | Continues sub-project #1's pattern. Host runs simulation; clients receive RPCs. |
| Match-end resolution | Most Crowns wins, ties broken by chips DESC then Heat DESC | Per design §20.6, the full tiebreaker is "chips → Heat survival → final event placement." MVP simplifies to "chips → Heat" because Heat-survival tracking and final-event-placement attribution depend on event-level Heat history (sub-project #4) and ranking-by-event-result (sub-project #3 onwards). Revisit when those land. |
| Resolution pacing | Sequential substeps with configurable per-step delay | Per design §4.2.6 ("Resolution should happen in a satisfying sequence"). MVP step delay ~600ms. |

## 5. Architecture

Sub-project #2 replaces sub-project #1's `PlaceholderMatch.tscn` with a real **MatchScene** that runs a 5-event Quick Clash. The structure is three layers.

### 5.1 `MatchController` (logic layer)

Owns `MatchState` (per-match authoritative data) and drives the phase state machine. Holds the per-player records, the seeded RNG, and the current event reference. Authoritative on host; mirrors via RPC on clients. Constructed when `MatchScene` enters the tree and torn down when the match ends.

Not an autoload — instantiated as a Node child of `MatchScene` so its lifetime matches the match scene's. The autoload pattern (used in sub-project #1's `NetSessionMain`) doesn't fit here because match state should not persist across matches.

### 5.2 `MatchScene.tscn` (visual layer)

The scene that replaces `PlaceholderMatch.tscn`. Contains:
- `PlayerPanels` HBox (8 `PlayerPanel` widgets — one per seat, empty slots hidden)
- `PhaseIndicator` Label
- `EventSlot` Container (instantiates the current event's scene)
- `ResolutionOverlay` (shown during RESOLUTION phase)
- `MatchEndOverlay` (shown on `match_ended`)

Reads state from `MatchController`; listens to its signals to drive UI updates.

### 5.3 `EventNode` base class + `TestEvent`

`EventNode` (extends `Node`) defines the standard event contract: virtual `_run(context: EventContext)` plus signals `event_complete(result: EventResult)` and `event_progress(payload: Dictionary)`. Each specific event ships as a `.tscn` extending `EventNode` with its own UI and state.

`TestEvent` is the one concrete event in this sub-project. It is intentionally trivial: shows an "advance" button (or auto-advances after a brief timer in test mode), then emits a deterministic result derived from the seeded RNG. It exists to prove the contract works and lets the match loop run 5 events back-to-back without depending on real game logic.

### 5.4 Authority and sync

Host-authoritative continuation from sub-project #1.

- Host's `MatchController` runs the simulation. State transitions trigger `rpc_phase_changed(phase, ctx)` to clients.
- Per-player resource changes computed on host, broadcast via `rpc_apply_deltas(serialized_deltas)`.
- During a `MAIN_EVENT` phase, the event itself owns its real-time RPCs (e.g., Rocket Clash's multiplier ticks). The match controller doesn't tick — events do.
- Event results flow back to MatchController via the `event_complete` signal; MatchController runs the resolution pipeline on host and broadcasts each substep.

### 5.5 Phase state machine

Per event, the state machine cycles through 9 phases. Phases without MVP behavior emit their `phase_changed` signal and advance immediately. Future sub-projects fill in those hooks.

| Phase | Constant | MVP behavior |
|---|---|---|
| 1. House Reveal | `HOUSE_REVEAL` | No-op signal emit; advance. |
| 2. Ante | `ANTE` | Deduct ante from all players' chips. Skip those with insufficient chips (set `is_active_this_event = false`). |
| 3. Event Selection | `EVENT_SELECTION` | Casino Wheel: random pick from `MatchConfig.EVENT_POOL` using seeded RNG. |
| 4. Bet / Loadout | `BET_LOADOUT` | No-op signal emit; advance. (Power cards deferred to #4.) |
| 5. Main Event | `MAIN_EVENT` | Instantiate event scene; call `_run(context)`; await `event_complete`. |
| 6. Resolution | `RESOLUTION` | Sequential substep pipeline: busts → cash_outs → chip_changes → crown_awards → painful_reveal. Apply chip/Crown deltas to authoritative state. |
| 7. Bounty / Heat Update | `BOUNTY_HEAT_UPDATE` | Apply Heat deltas (bounties deferred to #4). |
| 8. Shop | `SHOP` | No-op signal emit; advance. (Shop deferred to #4.) |
| 9. House Twist | `HOUSE_TWIST` | No-op signal emit; advance. (Twists deferred to #6.) |

After phase 9: if `event_index < 4`, increment and start the next event's `HOUSE_REVEAL`. Otherwise transition to `MATCH_END`, which computes rankings and emits `match_ended`.

## 6. Components

Each component below specifies **what it does**, **public interface**, **what it depends on**.

### 6.1 Data classes

**`MatchPhase.gd`** (Object subclass, enum only):
```gdscript
enum Phase {
    HOUSE_REVEAL, ANTE, EVENT_SELECTION, BET_LOADOUT, MAIN_EVENT,
    RESOLUTION, BOUNTY_HEAT_UPDATE, SHOP, HOUSE_TWIST, MATCH_END
}
```

**`MatchPlayer.gd`** (RefCounted data class):
- `peer_id: int`, `seat_index: int`, `name: String`, `color_index: int`
- `chips: int`, `crowns: int = 0`, `heat: int = 0`
- `is_active_this_event: bool = true`
- `to_dict()` / `static from_dict(d) -> RefCounted` for RPC marshalling

**`MatchState.gd`** (RefCounted data class):
- `event_index: int = 0`
- `phase: int = MatchPhase.Phase.HOUSE_REVEAL`
- `players: Array = []` (of `MatchPlayer`)
- `current_event_id: String = ""`
- `current_result = null` (last `EventResult`)
- `rng_seed: int = 0`
- `rng: RandomNumberGenerator` (constructed and seeded in `MatchController.start_match`)
- `to_dict()` / `from_dict()`

**`EventContext.gd`** (RefCounted data class):
- `players: Array` (only `is_active_this_event = true` from `MatchState.players`)
- `event_index: int`
- `rng_seed: int` (per-event seed: `match_seed ^ (event_index * 0x9E3779B9)`)
- `wagers: Dictionary` (`{peer_id: int}`; MVP = flat ante per player)

**`EventResult.gd`** (RefCounted data class):
- `event_id: String`
- `per_player: Dictionary` (`{peer_id: PlayerEventResult}` where `PlayerEventResult` has `chip_delta: int`, `crown_delta: int`, `heat_delta: int`, `bust: bool`, `cash_out_at: float`)
- `painful_reveal: Dictionary` (opaque payload for UI)
- Missing per-player entries default to zero deltas (defensive)

### 6.2 `MatchConfig.gd` (constants Object)

- `STARTING_CHIPS_BY_PLAYER_COUNT: Dictionary` — `{2:800, 3:700, 4:700, 5:600, 6:600, 7:500, 8:500}` per design §5.1.
- `ANTE_BY_EVENT_INDEX: Array` — `[25, 25, 25, 50, 100]` for Quick Clash MVP (mapping design §4.2.2 phase antes).
- `HEAT_MAX: int = 10`
- `EVENT_POOL: Array` — list of event scene paths; `["res://scripts/events/test_event/test_event.tscn"]` in this sub-project; appended by future sub-projects.
- `QUICK_CLASH_EVENT_COUNT: int = 5`
- `RESOLUTION_STEP_DELAY_MS: int = 600`
- `EVENT_TIMEOUT_SEC: int = 120`

### 6.3 `EventNode.gd` (base class)

**Extends:** `Node`

**Public interface:**
- `signal event_complete(result)` — emitted exactly once per run.
- `signal event_progress(payload: Dictionary)` — emitted as the event wants HUD/announcer to react during play. Optional.
- `func _run(context) -> void` — virtual; subclasses override. Receives the `EventContext`.
- `func get_event_id() -> String` — virtual; returns a stable string identifier.

**Depends on:** Nothing. Standalone contract.

### 6.4 `TestEvent.gd` + `test_event.tscn`

**What it does:** Stub event that verifies the contract. Implementation:
1. Reads `context.players` and `context.rng_seed`.
2. Shows a "End event" Button (or auto-completes after `auto_complete_ms` when set, for tests).
3. On completion, computes a deterministic Crown winner using the seeded RNG: `winner_index = rng.randi() % context.players.size()`.
4. Builds `EventResult` with `crown_delta = 1` for the winner, zero deltas for others. No chip changes (the ante already left them). Heat delta of +1 for the winner. `painful_reveal` shows the winner.
5. Emits `event_complete(result)`.

**Depends on:** `EventContext`, `EventResult`.

### 6.5 `MatchController.gd`

**Extends:** `Node`

**What it does:** Owns `MatchState`. Drives the phase state machine. Authoritative on host; mirror-only on clients (receives RPCs to update local state for HUD).

**Public interface:**

Properties:
- `state: MatchState` (read-only for consumers; host mutates internally)
- `is_host: bool`

Signals:
- `phase_changed(new_phase: int)` — every transition.
- `event_starting(event_id: String, event_index: int)` — when `MAIN_EVENT` begins.
- `resolution_step(step_name: String, payload: Dictionary)` — once per resolution substep.
- `match_ended(rankings: Array)` — after event 5 RESOLUTION → BOUNTY_HEAT_UPDATE → SHOP → HOUSE_TWIST.
- `player_resources_changed(peer_id: int)` — after any chip/Crown/Heat delta applies; HUD subscribes.

Methods:
- `start_match(match_start) -> void` — host-only; initializes state from `MatchStart`, advances to HOUSE_REVEAL of event 0.
- `pause() / resume()` — called by `MatchScene` in response to `NetSession.state_changed(PAUSED)` / `(MATCH)`.
- `return_to_lobby()` — host-only; called by `MatchEndOverlay`. Broadcasts intent; everyone changes scene back to Lobby.

RPC methods (host-only senders, all peers receivers):
- `_rpc_phase_changed(phase: int, ctx: Dictionary)`
- `_rpc_apply_deltas(serialized_deltas: Array)`
- `_rpc_resolution_step(step_name: String, payload: Dictionary)`
- `_rpc_match_ended(serialized_rankings: Array)`
- `_rpc_return_to_lobby()`

**Depends on:** `NetSessionMain` (autoload from sub-project #1; wraps the `NetSession` class with `get_last_match_start()` cache and singleton access) for the multiplayer peer / RPC routing. `MatchState`, `MatchPlayer`, `EventNode`, `MatchConfig`.

Note on `MatchController.return_to_lobby()` (host-only): it's a thin wrapper that calls `NetSessionMain.session.return_to_lobby()` (which transitions `NetSession.state` from MATCH to LOBBY) and then broadcasts `_rpc_return_to_lobby()` so all peers can change scene. The two methods are deliberate: `NetSession` owns state-machine ownership, `MatchController` owns scene-change orchestration.

### 6.6 `MatchScene.tscn` + `match_scene.gd`

**What it does:** The visible match scene. Composes the HUD plus the event slot. Owns the `MatchController` lifecycle.

**Sub-views:**
- `PlayerPanels` — HBoxContainer with 8 `PlayerPanel` instances; populated from `MatchController.state.players`.
- `PhaseIndicator` — Label showing `"Event {n}/5: {phase_name}"`.
- `EventSlot` — Container that holds the currently-running event's instantiated scene.
- `ResolutionOverlay` — VBoxContainer shown during RESOLUTION phase; refreshes on each `resolution_step` signal.
- `MatchEndOverlay` — shown when `match_ended` fires; displays final rankings + Back-to-Lobby button (host-only) + Quit button.
- `PauseOverlay` — same pattern as Lobby's pause overlay; shown on `NetSession.state_changed(PAUSED)`.

**Depends on:** `MatchController`, `NetSessionMain`, `MatchStart` (read from `NetSessionMain.get_last_match_start()`).

### 6.7 `PlayerPanel.tscn` + `player_panel.gd`

**What it does:** Per-player HUD widget. Displays name + color swatch, chips, Crowns, Heat (with band indicator: Quiet / Noticed / Hot Seat / Public Enemy per design §5.3).

**Public interface:** `set_player(player: MatchPlayer)`. Subscribes to `MatchController.player_resources_changed(peer_id)`; refreshes when its peer_id matches.

**Static helpers (for unit tests):** `format_chip_text(int)`, `format_crown_text(int)`, `heat_band(int) -> String`.

### 6.8 `ResolutionOverlay.tscn` + `resolution_overlay.gd`

**What it does:** Reactive UI that listens to `MatchController.resolution_step`. Pure formatter — displays whatever the step payload says. Real "painful reveal" juice (animations, sounds) deferred to sub-project #7.

**Static helpers:** `format_resolution_step(step_name: String, payload: Dictionary) -> String`.

### 6.9 `MatchEndOverlay.tscn` + `match_end_overlay.gd`

**What it does:** Shown on `match_ended(rankings)`. Lists ranked players with their final Crowns / chips / Heat. Host sees a Back-to-Lobby button; everyone sees a Quit button.

**Static helpers:** `format_match_end_rankings(rankings: Array) -> String`.

### 6.10 `NetSession.return_to_lobby()` (modify sub-project #1)

**What it does:** Host-only method that transitions `NetSession.state` from MATCH back to LOBBY. Sub-project #2 adds this because the match-end flow needs it.

```gdscript
func return_to_lobby() -> void:
    if not is_host:
        return
    if state != NetSessionState.State.MATCH:
        return
    _set_state(NetSessionState.State.LOBBY)
    # Clients learn via state_changed signal
```

Tested by extending `tests/unit/test_net_session_host_join.gd`.

## 7. Data Flow

### 7.1 Match start (handoff from sub-project #1)

```
Host clicks Start in Lobby (sub-project #1 — already proven)
  → NetSession.start_match() emits match_starting(match_start)
  → NetSessionMain caches match_start on the autoload (existing behavior)
  → Lobby calls change_scene_to_file("res://scenes/match_scene.tscn")
  → MatchScene._ready() reads match_start from NetSessionMain.get_last_match_start()
  → Builds MatchController; on host, calls MatchController.start_match(match_start)
       - state.event_index = 0
       - state.players = build_match_players_from(match_start.seats)
           (each MatchPlayer initialized with starting chips per MatchConfig)
       - state.rng.seed = match_start.rng_seed
       - state.phase = HOUSE_REVEAL
       - emit phase_changed(HOUSE_REVEAL)
       - rpc_phase_changed(HOUSE_REVEAL, serialized_ctx) to all peers
  → On clients: rpc_phase_changed handler updates local mirror MatchState
  → All peers: PlayerPanels populate, PhaseIndicator shows "Event 1/5: HOUSE_REVEAL"
```

### 7.2 Per-event phase progression

Host runs the state machine. Each transition broadcasts via RPC; clients mirror locally.

```
HOUSE_REVEAL → ANTE:
  for player in state.players:
    ante = MatchConfig.ANTE_BY_EVENT_INDEX[state.event_index]
    if player.chips >= ante:
      player.chips -= ante
      player.is_active_this_event = true
    else:
      player.is_active_this_event = false
  rpc_apply_deltas(serialized_chip_deltas) to all peers
  Advance (after small delay so HUD updates animate; configurable).

ANTE → EVENT_SELECTION:
  pool_index = state.rng.randi() % MatchConfig.EVENT_POOL.size()
  state.current_event_id = MatchConfig.EVENT_POOL[pool_index]
  rpc_phase_changed(EVENT_SELECTION, {event_id: state.current_event_id})
  Advance.

EVENT_SELECTION → BET_LOADOUT:
  No-op. emit phase_changed; rpc; advance immediately.

BET_LOADOUT → MAIN_EVENT:
  All peers: MatchScene loads state.current_event_id into EventSlot.
  Host: calls event_node._run(EventContext.build(state)).
  Clients: pump event scene but await host's event-level RPCs for outcomes.
  Host's event eventually emits event_complete(result).
    → MatchController._on_event_complete(result):
        state.current_result = result
        Advance to RESOLUTION.

MAIN_EVENT → RESOLUTION:
  Sub-step pipeline (each fires resolution_step signal + RPC):
    1. "busts"        — list of busted peer_ids
    2. "cash_outs"    — list of {peer_id, cash_out_at}
    3. "chip_changes" — apply chip_delta from result.per_player; rpc_apply_deltas
    4. "crown_awards" — apply crown_delta; rpc_apply_deltas
    5. "painful_reveal" — broadcast result.painful_reveal payload
  Each step waits MatchConfig.RESOLUTION_STEP_DELAY_MS before the next.
  After pipeline: Advance to BOUNTY_HEAT_UPDATE.

RESOLUTION → BOUNTY_HEAT_UPDATE:
  Apply heat_delta from result.per_player (clamp to [0, HEAT_MAX]).
  rpc_apply_deltas(heat).
  Advance.

BOUNTY_HEAT_UPDATE → SHOP:
  No-op. Advance.

SHOP → HOUSE_TWIST:
  No-op. Advance.

HOUSE_TWIST → (next event or MATCH_END):
  if state.event_index < 4:
    state.event_index += 1
    Advance to HOUSE_REVEAL of next event.
  else:
    Advance to MATCH_END.

MATCH_END:
  rankings = sort_by(crowns DESC, chips DESC, heat DESC)
  rpc_match_ended(serialized_rankings).
  emit match_ended(rankings).
```

### 7.3 Resolution sequence detail (within phase 6)

```
On host, after event_complete(result):
  For step in ["busts", "cash_outs", "chip_changes", "crown_awards", "painful_reveal"]:
    payload = build_payload_for(step, result)
    emit resolution_step(step, payload)
    rpc_resolution_step(step, payload)
    await timer(MatchConfig.RESOLUTION_STEP_DELAY_MS)
  emit resolution_complete()
  Advance to BOUNTY_HEAT_UPDATE.

On clients, rpc_resolution_step fires the same signal locally with the payload.
HUD's ResolutionOverlay listens and renders.
```

The deliberate per-step pacing is what makes resolution feel like a "show" rather than instant math. Spec §4.2.6.

### 7.4 Player resource broadcast

```
Host has authoritative MatchPlayer records. Mutation pattern:

MatchController._apply_player_delta(peer_id, chip_delta, crown_delta, heat_delta):
  player = state.find_player(peer_id)
  player.chips += chip_delta
  player.crowns += crown_delta
  player.heat = clamp(player.heat + heat_delta, 0, MatchConfig.HEAT_MAX)
  emit player_resources_changed(peer_id)

For RPC, host batches deltas per phase step:
  rpc_apply_deltas(serialized_deltas)
    serialized_deltas: Array of {peer_id, chip_delta, crown_delta, heat_delta}

On clients, rpc_apply_deltas iterates and calls _apply_player_delta locally,
emitting player_resources_changed for each.

HUD PlayerPanel widgets subscribe to player_resources_changed and refresh.
```

### 7.5 Match end + return to lobby

```
After event 5 RESOLUTION → BOUNTY_HEAT_UPDATE → SHOP → HOUSE_TWIST:
  state.phase = MATCH_END
  rankings = sort(state.players, by crowns DESC, chips DESC, heat DESC)
  emit match_ended(rankings)
  rpc_match_ended(serialized_rankings)

MatchScene's MatchEndOverlay shows:
  - Final rankings
  - Host: Back-to-Lobby button
  - Everyone: Quit button

Back-to-Lobby (host clicks):
  - Host calls NetSession.return_to_lobby() (sub-project #2 adds this method)
  - NetSession.state → LOBBY
  - Host broadcasts rpc_return_to_lobby() to all peers
  - All peers: change_scene_to_file("res://scenes/lobby.tscn")
  - NetSession.players list is preserved; Lobby renders the same players

Quit (anyone clicks):
  - Local: NetSession.leave_session() (existing from sub-project #1)
  - Local: scene change to MainMenu
```

## 8. Error Handling

### 8.1 Match-start failures

| Trigger | User message | System behavior |
|---|---|---|
| `NetSessionMain.get_last_match_start()` returns null | "Match failed to start (no match data). Returning to lobby." (toast) | Auto-return to lobby after 2s. Indicates a Lobby bug. |
| `MatchController.start_match()` throws during init | "Match failed to start." (toast) | Host calls `NetSession.leave_session()`; all peers return to MainMenu. |

### 8.2 Disconnect mid-match (reuses sub-project #1 machinery)

| Trigger | Behavior |
|---|---|
| `NetSession.state_changed(PAUSED)` during a match | MatchController pauses phase advancement. MatchScene shows pause overlay (same pattern as Lobby). Current event continues locally but the host stops broadcasting transitions. |
| Reconnect within 30s | `NetSession.state_changed(MATCH)` fires. MatchController resumes. If the dropped player was mid-event, treats them as busted for the current event (`is_active_this_event = false`, zero deltas in result). The already-deducted ante is NOT refunded (MVP simplification — Debt refund mechanics are future plan work). |
| 30s timeout / player removed | MatchController treats them as eliminated. `MatchPlayer` stays in state with `is_active_this_event = false` permanently. Resources freeze at current values. If only 1 active player remains, end match early via `match_ended`. |
| Host drops | `NetSession.session_ended("host_lost")` fires on clients. MatchScene shows "Host disconnected — match ended"; returns to MainMenu after 3s. Existing sub-project #1 flow. |

### 8.3 Event-layer failures

| Trigger | Behavior |
|---|---|
| Event scene fails to load | Host catches load failure; broadcasts `rpc_event_load_failed(event_id, error)`. All peers show toast. Synthetic all-zero result; advance to RESOLUTION normally. |
| Event never emits `event_complete` (timeout) | Per-event watchdog (`MatchConfig.EVENT_TIMEOUT_SEC = 120`). On timeout: force-terminate, emit synthetic all-bust zero-delta result; advance. Logged at warn level. |
| Event emits malformed `EventResult` | `MatchController` validates; missing per-player entries default to zero deltas. |
| Event RPC desync (per-event RPCs) | Out of scope for #2 (TestEvent has no real-time RPCs). Each future event handles its own desync; pattern TBD per event in #3/#5. |

### 8.4 RPC and state-sync failures

| Trigger | Behavior |
|---|---|
| Client receives `rpc_apply_deltas` for unknown peer_id | Silently ignore. Resyncs on next `rpc_phase_changed`. |
| Client receives `rpc_phase_changed` for unreachable phase | Apply anyway. Host is authoritative. Logged at warn. |
| Client crashes between RPC and HUD update | Next RPC refreshes. No persistent inconsistency. |

### 8.5 Resource-math edge cases

| Trigger | Behavior |
|---|---|
| Player can't pay ante | `is_active_this_event = false`. Zero deltas. Debt deferred to future plan. |
| All players can't pay ante | All sit out. Event produces zero deltas. Logged. |
| Heat clamp | `clamp(0, HEAT_MAX)`. Silent. Per design §5.3. |
| Negative chip balance (bug) | Allow; logged at warn. Better than silently swallowing. |

### 8.6 Cross-cutting: NetSession.return_to_lobby

Adds a host-only public method (see §6.10). Asserts `state == MATCH`; transitions to `LOBBY` and broadcasts `state_changed`. Match controller is independent of NetSession's state; cleanup happens at scene-change time.

### 8.7 Out-of-scope failure modes (acknowledged, deferred)

- Save/resume incomplete matches: not in MVP.
- Spectator mid-match join: rejected by signaling's `in_progress` error from sub-project #1.
- Replay / event log: deferred to a later polish plan.

## 9. Testing

### 9.1 Tier 1 — Pure data class unit tests (GUT)

Trivial round-trip and default-value tests.

- `test_match_player.gd` — defaults; to_dict/from_dict round-trip including chips/crowns/heat fields.
- `test_match_state.gd` — defaults; phase enum integration; to_dict/from_dict including nested MatchPlayer array.
- `test_event_context.gd` — defaults; player filtering by `is_active_this_event`.
- `test_event_result.gd` — defaults; per-player accessor; missing-key tolerance.
- `test_match_config.gd` — verifies the constants table.

### 9.2 Tier 2 — MatchController state machine (GUT against fakes)

The heaviest test surface.

- Match start tests: `start_match(match_start)` initializes state correctly.
- Phase-transition tests: one per pair, verifying state mutation and `phase_changed` emission.
- Ante tests: all players pay; zero-chip player sits out; deltas emitted.
- Event selection tests: deterministic with seeded RNG; one-element pool; multi-element pool.
- MAIN_EVENT integration with `MockEvent`: synchronous `event_complete` advances to RESOLUTION.
- Event timeout test: `MockEvent` that never completes; manual watchdog tick; synthetic result applied.
- Resolution pipeline tests: substeps fire in order; chip/crown/heat deltas applied; Heat clamps.
- Multi-event progression: 5 full events; event_index increments; ante varies by event index; final state MATCH_END.
- Rankings test: at MATCH_END, sorted by (crowns DESC, chips DESC, heat DESC).
- Disconnect during match: simulate `NetSession.state_changed(PAUSED)`; phase advancement halts; resume.

Target: ~30 tests.

### 9.3 Tier 3 — TestEvent unit tests (GUT)

- `test_test_event.gd`: instantiate, call `_run(context)`, simulate advance, verify `event_complete` fires; verify result.per_player matches input; verify deterministic Crown winner.

Target: ~5 tests.

### 9.4 Tier 4 — UI logic tests (GUT)

Static-method pattern; no scene-tree instantiation.

- `test_player_panel_logic.gd` — formatters; `heat_band(int)`.
- `test_match_scene_logic.gd` — `format_phase_indicator(...)`, `format_match_end_rankings(...)`.
- `test_resolution_overlay_logic.gd` — `format_resolution_step(...)` for each of the 5 step names.

Target: ~15 tests.

### 9.5 Tier 5 — Integration smoke test

- `tests/integration/test_match_runs_five_events.gd`: host + joiner connect via real signaling server; click Lobby Start; TestEvent auto-completes via configurable delay; match runs 5 events end-to-end; both peers observe `match_ended` with consistent rankings; return-to-lobby works.

Skips cleanly if signaling server not running.

### 9.6 Manual playtest additions

Extend `docs/PLAYTEST_CHECKLIST.md`:

- Match runs all 5 events without errors.
- Player panels update on resource changes.
- Phase indicator advances correctly.
- Resolution overlay shows substeps with readable pacing.
- Ante skip works when a player has 0 chips.
- Match ends correctly; rankings displayed.
- Back-to-Lobby returns all peers to Lobby scene.
- Quit returns the quitting peer to MainMenu.

### 9.7 Out of scope for #2's testing

- Real-event behavior (Rocket Clash, etc.) — those events bring their own tests in #3 / #5.
- Bounties, power cards, shop, twists — tested when their respective plans ship.
- Performance / load testing — Quick Clash 2–8 players, no scaling concerns.
- Real-network stress — existing concern documented in earlier specs.

## 10. Open Questions / Future Work

- **Event-selection methods beyond Casino Wheel**: design §4.2.3 lists Lowest Picks, Winner Bans, Chip Vote, Host's Choice. Deferred. When events get personality, these become important — particularly Lowest Picks for comeback agency.
- **Debt / Reputation**: design §5.4 + §5.5. The full economy includes these as comeback resources. Currently sub-project #2 just skips ante-broke players. A future plan should add a "House Deal" / "Black-Market Loan" path so trailing players stay engaged.
- **Resolution juice**: design §4.2.6 and §22.4 describe "painful reveal" theatrics. Sub-project #7 polish.
- **Standard mode (10 events)**: sub-project #2 hard-codes 5. Standard mode adds Final Table (event 10) which is a 3-stage finale per design §20. Future plan.
- **Mid-match state replication on late reconnect**: sub-project #2 freezes resources but doesn't sync the latest match state to a reconnecting client mid-event. Acceptable for MVP given 30s grace; mid-event reconnect is rare.
- **Match settings / mode picker**: deferred per sub-project #1's decisions table. Quick Clash hard-coded for now.

## 11. Contract Summary for Downstream Sub-Projects

Sub-project #3 (Rocket Clash) and #5 (Bomb Pot + Card Cannon) consume the event interface this spec defines:

- An event ships as a `.tscn` in `scripts/events/<event_id>/` extending `EventNode`.
- The event's scene path is appended to `MatchConfig.EVENT_POOL`.
- The event implements `func _run(context: EventContext)` and emits `event_complete(result: EventResult)` exactly once.
- The event owns its own UI inside its scene and its own real-time RPCs during play. The match controller doesn't reach into the event.
- The event's `EventResult.per_player[peer_id]` carries chip/Crown/Heat deltas for each active player. Missing entries = zero deltas.
- The event's `painful_reveal: Dictionary` can carry any opaque data the ResolutionOverlay can render.
- The event's `event_progress(payload: Dictionary)` signal is optional; the HUD subscribes if it wants to react during play.

Sub-projects #3+ should NOT:
- Reach into `MatchController.state` to mutate player resources directly. Always go through the result.
- Run a separate phase machine. The match controller owns phase transitions.
- Wire their own scene transitions. The match scene unloads/loads events automatically.
- Persist state across events. Each event run is independent.

Sub-project #4 (Power Cards & Bounties) will add behavior to the currently-no-op `BET_LOADOUT` and `BOUNTY_HEAT_UPDATE` phases plus the `SHOP` phase. The state machine doesn't need restructuring — just real handlers in those slots.

Sub-project #6 (House Twists) will fill in the `HOUSE_TWIST` phase. Same plug-in shape.
