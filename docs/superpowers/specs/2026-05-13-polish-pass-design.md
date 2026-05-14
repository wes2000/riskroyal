# Polish Pass (Sub-project #7) Design Spec

**Date:** 2026-05-13
**Status:** Approved
**Sub-project:** #7 (final MVP sub-project)

---

## 1. Context

Sub-project #6 shipped 2026-05-13 with all 6 MVP House Twists (Double Bounty, No Insurance, Leader Cursed, Power Surge, Lowest Chips Picks, Sudden Death Jackpot). The MVP feature pipeline (events, cards, bounties, twists, lobby, signaling) is complete. Test suite: 564 unit + 7 integration on `main`.

Sub-project #7 is the final pre-public-playtest pass: clean up accumulated carry-forward debt + ship the visible UX polish (announcer, painful reveals, results juice, spectator behavior, missing overlay UX) that the original design doc § 3 framed as "Polish pass."

The followups memory `project_riskroyal_followups.md` accumulates ~15 carry-forwards from sub-projects #2-6; #7 closes them.

## 2. Goals

- Pay down all carry-forward debt accumulated through sub-projects #2-6
- Add visible UX polish so the game is presentable to non-developer playtesters
- Maintain test count (no regressions); add tests where refactor changes API surface
- Tag `subproject-7-complete` = MVP shipping milestone

**Cumulative target after #7 merge:** ~620 unit + 9 integration tests.

## 3. Non-Goals

- No new gameplay features, events, cards, or twists
- No new transport / networking changes (WebRTC P2P facade stays)
- No multi-language i18n
- No platform-specific (mobile, web) work
- No public lobby browser or accounts
- No TURN server / NAT-traversal work
- No real-time TTS / synthesized voices (announcer is text-only for MVP)

## 4. Decisions

| Topic | Decision | Rationale |
|---|---|---|
| Plan split | Plan A (debt paydown) → Plan B (visible info) → Plan C (feel + audio + a11y) | Cleanups first means polish lands on a tidy codebase; three distinct risk profiles |
| Plan A scope | Refactor + numeric edge cases + RPC bandwidth (skip new integration tests) | User decision 2026-05-13: integration test depth deferred; can fold into Plan B or post-MVP polish |
| Plan B scope | Visible-info pass: StatusGrid, countdowns, announcer, reveals, LoadoutOverlay, target picker | ~12 tasks; everything a first-time playtester needs to understand game state |
| Plan C scope | Feel + audio + accessibility: SFX, polished animations, spectator polish, color-blind + text-scale a11y | Separate brainstorm cycle after Plan B merges |
| Helper organization | Two new helper modules: `EventHelpers` + `PlayerSelectors` | Separation of concerns; each ~40 lines; sub-project #4 collaborator pattern |
| Starter pack broadcast | Narrow to per-peer `rpc_id()` | Real bandwidth win for Power Surge + initial deal |
| Announcer scope | Text overlays only, no TTS | TTS is a v1.1 / post-MVP polish item |
| LoadoutOverlay UX | Drag-to-loadout via Godot 4's `_get_drag_data` / `_can_drop_data` / `_drop_data` API | More natural than click-toggle; Godot 4 drag API is a clean fit; avoids ambiguous "which slot?" problem |
| Audio approach (Plan C) | Procedural synthesis via `AudioStreamGenerator` + asset-slot scan for user-provided overrides | Ships an audible framework without external dependencies; users can replace with custom assets by dropping files into `scripts/audio/sfx/` |
| Animation depth (Plan C) | Sequenced Tweens (multi-step transitions) | More polished than Plan B's single-line fades; avoids `AnimationPlayer` scene-file complexity |
| Spectator mode (Plan C) | Full layout rework with dedicated `SpectatorOverlay` scene | Leaderboard-style ranking + per-event status; supersedes the design doc §3 spectator mention |
| Accessibility (Plan C) | Color-blind shape/icon cues + text-scale toggle only | High-contrast mode and keyboard-only nav audit deferred to post-MVP v1.1 |

## 5. Architecture changes (Plan A)

### 5.1 `EventHelpers` static helper class (NEW — Plan A Task 1)

Path: `scripts/match/event_helpers.gd`
Style: `extends Object`, static-only, mirrors `HouseTwistController` / `BountyResolver` / etc.

```gdscript
extends Object

# Apply Leader Cursed multiplier to chip_delta if active. Returns the
# (possibly modified) chip_delta. Called from compute_event_result of
# all 3 events as a one-line replacement for the 7-line inline block.
static func apply_leader_cursed(context, pid: int, chip_delta: int) -> int:
    if context == null:
        return chip_delta
    var ht = context.house_twist
    if ht.get("type", "") != "leader_cursed":
        return chip_delta
    var leader_id = int(ht.get("params", {}).get("leader_peer_id", 0))
    if pid != leader_id:
        return chip_delta
    var mult = float(ht.get("params", {}).get("reward_multiplier", 1.0))
    if mult == 1.0:
        return chip_delta
    return int(chip_delta * mult)

# Apply Sudden Death Jackpot bonus crown for survivors meeting their
# event-specific condition. Takes a Callable that returns bool for the
# event-specific check (e.g. "did P2 cash out > 5.0x?"). The result
# dict is mutated in place. No-op if twist inactive or condition empty.
static func apply_sudden_death_bonus(
    context, pid: int, per_player: Dictionary, expected_condition: String,
    survives: bool
) -> void:
    if context == null or not survives:
        return
    var ht = context.house_twist
    if ht.get("type", "") != "sudden_death_jackpot":
        return
    var actual = String(ht.get("params", {}).get("condition", ""))
    if actual != expected_condition:
        return
    # Caller has already evaluated the event-specific condition AND
    # confirmed the player meets it — survives == true means "qualifies."
    per_player[pid].crown_delta = int(per_player[pid].get("crown_delta", 0)) + 1
```

**Design note on `apply_sudden_death_bonus`:** the per-event condition (cash_out > 5.0, pull_out_after_80%, locked == 21) is event-specific and depends on event-private state (`cash_outs`, `pull_out_timestamps`, `locked_scores`). Rather than overloading the helper with event-specific data extraction, the caller pre-evaluates the boolean and passes it as `survives`. This keeps the helper event-agnostic. Alternative considered (Callable-based check) was rejected for clarity.

**Refactor framing:** the helper is a **guard extraction**, not a one-liner. The caller still owns the `for player in context.players:` loop and the per-player condition evaluation; the helper absorbs the outer `if ht.get("type", "") == ... and condition == ...` guard plus the `crown_delta += 1` mutation. Net win: ~5 boilerplate lines per consumer become 1 call.

Consumers (3 events) become — note the per-player loop stays with the caller:

```gdscript
# Rocket Clash compute_event_result, after Crown award block, before painful_reveal:
for player in context.players:
    var pid = player.peer_id
    var survives = not busted.has(pid) and float(cash_outs.get(pid, 0.0)) > 5.0
    EventHelpers.apply_sudden_death_bonus(context, pid, result.per_player, "cash_out_over_5x", survives)

# Bomb Pot — same shape, but precompute threshold once outside the loop:
var threshold_ms = bomb_at_sec * 1000.0 * 0.80
for player in context.players:
    var pid = player.peer_id
    var survives = (pid in pulled_out_peers) and float(pull_out_timestamps.get(pid, 0)) >= threshold_ms
    EventHelpers.apply_sudden_death_bonus(context, pid, result.per_player, "pull_out_after_80_pct", survives)

# Card Cannon:
for player in context.players:
    var pid = player.peer_id
    var survives = not busted.get(pid, false) and int(locked_scores.get(pid, 0)) == 21
    EventHelpers.apply_sudden_death_bonus(context, pid, result.per_player, "locked_at_perfect", survives)

# Leader Cursed (called from inside the existing survivor branch, one line replacement):
chip_delta = EventHelpers.apply_leader_cursed(context, pid, chip_delta)
```

### 5.2 `PlayerSelectors` static helper class (NEW — Plan A Task 5)

Path: `scripts/match/player_selectors.gd`

```gdscript
extends Object

# Find the peer_id with the extremum of `chips` over state.players.
# direction: "max" or "min"; tie_break: if true, lower seat_index wins ties;
# if false, first-encountered traversal order wins.
static func find_chips_extremum(state, direction: String, tie_break: bool) -> int:
    if state.players.is_empty():
        return 0
    var best = state.players[0]
    for p in state.players:
        var wins: bool = false
        if direction == "max":
            wins = p.chips > best.chips
        else:
            wins = p.chips < best.chips
        if wins:
            best = p
        elif tie_break and p.chips == best.chips and p.seat_index < best.seat_index:
            best = p
    return best.peer_id
```

Replaces:
- `BountyResolver.find_chip_leader_peer_id` (max, no tie-break) — delegates to `PlayerSelectors.find_chips_extremum(state, "max", false)`
- `HouseTwistController._find_chip_leader_peer_id` (max, tie-break) — delegates to `PlayerSelectors.find_chips_extremum(state, "max", true)`
- `HouseTwistController._find_lowest_chips_peer_id` (min, tie-break) — delegates to `PlayerSelectors.find_chips_extremum(state, "min", true)`

The 3 existing functions stay as 1-line delegations to preserve their callers' API; their bodies become single calls into `PlayerSelectors`. No call site updates needed.

### 5.3 Guard cleanup (Plan A Task 6)

In the 3 event scripts' `compute_event_result`, delete the redundant `and "event_modifiers" in context:` portion of the existing 3 `if context != null and "event_modifiers" in context:` guards. `event_modifiers` is a typed field on `EventContext`; the membership check is dead code that was originally a copy-paste from a Dictionary access pattern.

### 5.4 Numeric edge cases (Plan A Tasks 7-9)

**Task 7 — Bomb Pot `winner_pull_out_ms` sentinel:**
Replace the `-1` initialization with `INF` (or use an explicit `var has_winner: bool = false` flag) so a future refactor can't accidentally allow a non-puller to "win" via a `>` comparison against `-1`. The current invariant (`if pid in pulled_out_peers:` guard outside the comparison) becomes explicit. 1 new test for "no puller fires no winner."

**Task 8 — Heat Shield int-div assumption:**
Doc-only addition: comment in `scripts/cards/effects/heat_shield.gd` near the `int(heat_delta / 2)` line explaining that `int(1 / 2) = 0` is intentional for the current `heat_delta = 1` case. If a future twist sets `heat_delta = 2`, the framing in the design doc would need updating. No behavior change.

**Task 9 — Bounty tie-split remainder:**
In `BountyResolver.resolve`, the `int(reward / claimants.size())` line evaporates the modulo. Refactor to deterministic: assign the modulo to the claimant with the lowest seat_index. 1 new test for 3-claimant tie with non-divisible reward.

### 5.5 RPC bandwidth + arity (Plan A Tasks 10-12)

**Task 10 — Client→host RPCs:**
Audit ~5-8 client→host RPC call sites (`_rpc_set_wager`, `_rpc_cash_out_requested`, `_rpc_card_play_requested`, `_rpc_event_picker_choice`, etc.). All currently use `rpc("...")` which broadcasts to ALL peers; the `is_host` guard short-circuits non-host receivers. Switch to `rpc_id(state.host_peer_id, "...")` so only the host receives. Behavior unchanged; bandwidth saved on N-1 peers per call.

**Task 11 — Starter pack broadcast narrowing:**
`_rpc_starter_pack_dealt(serialized_hands)` (in `scripts/match/match_controller.gd`) currently broadcasts every peer's full hand to every peer. The two callers are: (a) `_process_house_reveal` initial deal at match start, (b) `_process_house_twist` Power Surge bonus deal. Refactor both call sites to send only the changed peer's hand via `rpc_id(peer_id, ...)` — one rpc per peer instead of one rpc with all peers' hands serialized.

**Task 12 — MatchRpcSender arity cap rewrite:**
`MatchRpcSender.send` uses a match statement that caps at 3 args (silently push_errors on 4+). Replace with `Callable.callv` so the sender handles arbitrary args. Removes a latent bug class.

## 6. Architecture changes (Plan B — visible info pass)

Plan A shipped 2026-05-13. Tag: `subproject-7-plan-a-complete`. Final counts: 587 unit + 7 integration. All 8 debt carry-forwards from sub-project #6 closed. Plan B is the "visible info" pass (~12 tasks), organized into 4 phases.

### Phase 1 — Core info displays (Tasks 1-5)

**Task 1 — `StatusGrid` widget (NEW).**
Files: `scripts/ui/status_grid.gd` + `scenes/ui/status_grid.tscn`. Implemented as a `PanelContainer` containing an `HBoxContainer` of per-peer status chips. The script exposes a static formatter `format_status(event_id: String, peer_state: Dictionary) -> String` that returns event-specific status text from a fixed vocabulary: `"IN"` / `"CASHED"` / `"BUSTED"` / `"PULLED"` / `"DRAWING"` / `"LOCKED"`. The widget subscribes to `MatchController`'s new `status_changed(peer_id: int, status_string: String)` signal while the match is in the `MAIN_EVENT` phase; chips update in place on each emission. A test file `test_status_grid.gd` covers `format_status` directly (pure static, no scene needed).

**Task 2 — Per-event StatusGrid population.**
Each of the 3 events emits `status_changed` at the appropriate lifecycle points by calling up to `MatchController` (or via a new `_rpc_event_status_changed` if cross-peer delivery is needed before the event result RPC):
- Rocket Clash: `CASHED` on `cash_out`, `BUSTED` on crash, `IN` otherwise.
- Bomb Pot: `PULLED` on `pull_out`, `BUSTED` on bomb detonation, `IN` otherwise.
- Card Cannon: `LOCKED` on lock-in, `BUSTED` on bust, `DRAWING` otherwise.

Signal flows host→clients via the existing event RPC paths where possible; a dedicated `_rpc_event_status_changed(peer_id, status_string)` is added only if the existing event result RPC fires too late to give real-time feedback. Integration point: each event script gains a `_emit_status` helper that calls `context.controller.emit_signal("status_changed", pid, status_str)` after the relevant state mutation.

**Task 3 — BetLoadoutOverlay enhancements.**
`scripts/ui/bet_loadout_overlay.gd` gains two additions: (a) a countdown `Label` node that reads `seconds_remaining` from a new `MatchController` signal `bet_loadout_timer_tick(seconds_remaining: int)` fired once per second during the BET_LOADOUT phase; (b) a per-peer readied indicator (a small icon or checkmark per peer chip) that subscribes to the existing `wager_acknowledged(peer_id)` signal from sub-project #3, which was never wired to any visual. No new RPC; both signals already exist or are trivially added to `MatchController`.

**Task 4 — EventPickerOverlay countdown wiring.**
`scenes/ui/event_picker_overlay.tscn` already declares a `CountdownLabel` node (added in Plan A of sub-project #6) but no code ticks it. `scripts/ui/event_picker_overlay.gd` gains a `_process(delta)` block (active only while the picker is visible) that reads the remaining time from the overlay's `time_remaining` property and updates the label as `"[Xs]"`. Integration: `MatchController` passes the timeout when it opens the picker via the existing `show_event_picker(options, timeout_sec)` call; the overlay stores the deadline and counts down locally without an additional RPC.

**Task 5 — `crown_delta=2` rendering in results overlay.**
When `crown_delta == 2` (Sudden Death Jackpot bonus + regular Crown stack), the results overlay currently shows nothing visually distinct. Add prominent rendering: display `"2× CROWN"` or two crown icons side-by-side in the per-player results row when `crown_delta >= 2`. This gives players clear confirmation that the Sudden Death stacking fired. Integration point: `scripts/ui/results_overlay.gd` checks `per_player[pid].crown_delta` and branches its display string/node accordingly.

### Phase 2 — Announcer + painful reveals (Tasks 6-8)

**Task 6 — `Announcer` widget (NEW).**
Files: `scripts/ui/announcer.gd` + `scenes/ui/announcer.tscn`. Banner-style `PanelContainer` positioned at screen top-center, with a message `Label` and auto-dismiss after 3 seconds (default, configurable). Internally maintains a FIFO queue so simultaneous triggers don't collide. Exposes static formatters for each event-class:
- `format_twist_text(twist_dict: Dictionary) -> String` — e.g., `"HOUSE TWIST: Double Bounty Round!"`
- `format_bust_text(peer_name: String, chip_loss: int) -> String` — e.g., `"P2 EJECTED! -$100"`
- `format_crown_text(peer_name: String, crown_count: int) -> String` — e.g., `"P3 WINS THE CROWN!"`
- `format_match_outcome_text(winner_peer_id: int, winner_name: String) -> String` — e.g., `"P1 WINS THE MATCH!"`

The widget subscribes to 4 signals on `MatchController`: `house_twist_announced`, `player_busted(peer_id, chip_loss)`, `crown_awarded(peer_id, count)`, and `match_outcome_decided(winner_peer_id)`. All 4 fire both locally (for the local player) and arrive via RPC for remote events. Test file `test_announcer.gd` covers all 4 static formatters plus the queue flush behavior.

**Task 7 — MatchController supporting signals.**
`scripts/match/match_controller.gd` gains two new signals extracted from existing paths:
- `player_busted(peer_id: int, chip_loss: int)` — extracted from the existing per-event bust path. Each event script emits a generic `peer_busted` signal upward to `MatchController` after its result RPC; `MatchController` re-emits as `player_busted` with the chip_loss delta from `per_player[pid]`. No new state; the signal fires alongside the existing state mutation.
- `crown_awarded(peer_id: int, count: int)` — extracted from `_process_resolution` after `crown_delta` is applied to a peer's crown tally. Fires with the `crown_delta` value from the result dict.

Both signals preserve all existing resolution tests; the new emissions are additive. Integration: `Announcer` and `PainfulReveal` (Task 8) both subscribe independently — the signals are general-purpose.

**Task 8 — `PainfulReveal` widget (NEW).**
Files: `scripts/ui/painful_reveal.gd` + `scenes/ui/painful_reveal.tscn`. Animated text+chip overlay using `Tween` (no SFX — deferred to Plan C). Two reveal types:
- Bust reveal: RED color scheme, text `"P2 LOST $100"`, 2-second slide-in followed by dissolve.
- Crown reveal: GOLD color scheme, text `"+1 CROWN"` or `"+2 CROWN"`, 1.5-second pulse animation.

Subscribes to the same `player_busted` / `crown_awarded` signals as `Announcer`; the two widgets are fully independent — both receive every event and each handles its own display logic. The `PainfulReveal` widget only fires for bust and crown moments (2 reveal types), not house twist or match outcome (those are `Announcer`-only). Test file `test_painful_reveal.gd` covers the two reveal-type builders as static helpers.

### Phase 3 — Interactive overlays (Tasks 9-11)

**Task 9 — `LoadoutOverlay` drag-to-loadout rewrite.**
`scripts/ui/loadout_overlay.gd` is rewritten to replace the Plan A static-formatter scaffold from sub-project #4 with a fully interactive drag-and-drop grid. Layout: a hand row (`HBoxContainer` of card `Button` nodes) above 2 loadout slot `PanelContainer` nodes. Drag protocol uses Godot 4's built-in API:
- `_get_drag_data(at_position)` on hand buttons returns the `card_id` string as drag payload.
- `_can_drop_data(at_position, data)` on loadout slots returns `data is String and data in valid_card_ids`.
- `_drop_data(at_position, data)` places the card into the slot and fires `loadout_changed.emit(slot_index, card_id)`.

Visual feedback during a drag: valid target slots modulate to `+1.2` brightness; invalid slots modulate to `+0.5`. The `loadout_changed` signal is the sole output from this widget; no direct RPC calls inside the widget. Test file `test_loadout_overlay.gd` covers the `_can_drop_data` logic and `loadout_changed` emission via simulated drop.

**Task 10 — LoadoutOverlay integration wiring.**
`scripts/ui/match_scene.gd` wires `LoadoutOverlay.loadout_changed` to the existing `submit_loadout_change` RPC call. End-to-end flow: drag card → slot drop fires `loadout_changed(slot_index, card_id)` → `match_scene._on_loadout_changed` → `submit_loadout_change(slot_index, card_id)` → host `_rpc_loadout_set` (now targeted via `rpc_id` after Plan A Task 12). This closes the sub-project #4 carry-forward where the interactive grid was deferred.

**Task 11 — Cash-Out Jammer target picker (NEW).**
Files: `scripts/ui/cash_out_card_drawer_target_picker.gd` + `scenes/ui/cash_out_card_drawer_target_picker.tscn`. Modal popup that opens when the Cash-Out Jammer card is selected (detected by `target_required == true` on the card definition). Displays other active peers as labeled `Button` nodes. Clicking a peer fires `submit_card_play("cash_out_jammer", chosen_target_peer_id, {})` and closes the popup. Replaces the current no-op path where the drawer submits with `target_peer_id=0` and the host rejects the play. Integration point: `scripts/ui/match_scene.gd` intercepts the card-selection event for `target_required` cards and opens this picker instead of immediately calling `submit_card_play`. This closes the sub-project #4 Plan B carry-forward.

### Phase 4 — Integration + docs (Task 12)

**Task 12 — Integration test + playtest checklist.**
New PENDING integration test stub: `tests/integration/test_announcer_fires_across_phases.gd`. This is a PENDING stub (not yet executable), consistent with the existing integration test pattern established in sub-projects #3-6. The stub documents the expected behavior across a 2-peer simulated match: Announcer fires on all 4 trigger types in the correct phase; `StatusGrid` populates correctly for each event; `PainfulReveal` shows on bust and crown only.

`docs/PLAYTEST_CHECKLIST.md` gains scenarios 28-34:
- 28: StatusGrid populates correctly for each of the 3 events
- 29: BetLoadoutOverlay shows countdown ticking + per-peer readied checkmarks
- 30: EventPickerOverlay countdown ticks down visibly
- 31: `crown_delta=2` renders prominently in results overlay
- 32: Announcer fires on all 4 trigger types (twist / bust / crown / match outcome)
- 33: Painful reveals appear on bust (RED) and crown (GOLD) moments only
- 34: LoadoutOverlay drag-to-slot works end-to-end; Cash-Out Jammer target picker opens and submits

## 6.5. Architecture changes (Plan C — feel + audio + a11y)

Plan C is the third and final plan for sub-project #7. After Plan C merges, the project receives tags `subproject-7-plan-c-complete` + `subproject-7-complete` + `mvp-complete`. Plan B shipped 2026-05-13. Plan C scope: 5 phases, 17 tasks. Final test target: ~650 unit + 9 integration.

### Phase 1 — Audio framework (Tasks 1-3)

**Task 1 — `SoundManager` autoload (NEW).**
Files: `scripts/audio/sound_manager.gd`, registered in `project.godot` as a global autoload named `SoundManager`. The class exposes 6 named play methods: `play_chip_transfer()`, `play_bust()`, `play_crown_win()`, `play_match_end()`, `play_button_press()`, and `play_twist_stinger()`. Each method drives an `AudioStreamGenerator` node to synthesize a short distinct waveform inline — no asset file required to ship an audible experience. Waveform personalities: saw-wave descending 200 Hz burst for bust; ascending C-E-G arpeggio for crown win; descending tone for match end; brief click for button press; rising sweep for twist stinger; soft tone for chip transfer. A static helper centralizes synthesis parameters:

```gdscript
static func synth_params(name: String) -> Dictionary:
    # Returns keys: frequency (float), duration (float), waveform_type (String)
    # Used by unit tests to assert distinct cue personalities without playing audio.
```

`synth_params` is the primary unit-test entry point — tests assert that each named cue returns a distinct `frequency`/`waveform_type` combination without instantiating an audio bus. Test file: `tests/unit/test_sound_manager.gd` (+3 unit tests).

**Task 2 — Asset-slot loading (MODIFY `SoundManager`).**
`SoundManager._ready` scans `scripts/audio/sfx/*.ogg` at startup. For each filename matching a known slot (`bust.ogg`, `crown_win.ogg`, `match_end.ogg`, `button_press.ogg`, `twist_stinger.ogg`, `chip_transfer.ogg`), the corresponding play method switches from procedural `AudioStreamGenerator` synthesis to a file-backed `AudioStreamPlayer` loaded from the matched path. Slots with no matching file fall back to the procedural synthesizer. This lets a user drop higher-quality replacements into `scripts/audio/sfx/` with zero code changes. A `README` in `scripts/audio/sfx/` documents the 6 expected filenames and their slot semantics. Test file: `tests/unit/test_sound_manager.gd` (+2 unit tests covering slot detection logic via a mock filesystem scan helper).

**Task 3 — Signal-to-SFX dispatcher (NEW or folded into `SoundManager`).**
`scripts/audio/sound_dispatcher.gd` (or an inner method in `SoundManager._ready`) wires the Plan B signals to their corresponding cues: `MatchController.player_busted` → `play_bust()`; `MatchController.crown_awarded` → `play_crown_win()`; `MatchController.house_twist_announced` → `play_twist_stinger()`; `MatchController.match_outcome_decided` → `play_match_end()`. UI buttons fire `SoundManager.play_button_press()` either by calling it directly in their `pressed` handler or via a thin `ButtonWithSFX` subclass that wraps the base `Button` and connects `pressed` to `SoundManager.play_button_press()` automatically. Dispatcher integration is tested by asserting that signal emissions trigger the correct `synth_params` key lookup (mock SoundManager, no audio hardware). Test file: `tests/unit/test_sound_dispatcher.gd` (+2 unit tests).

### Phase 2 — Sequenced animations (Tasks 4-7)

**Task 4 — Announcer slide animation overhaul (MODIFY `scripts/ui/announcer.gd`).**
Replaces the Plan B single-`Tween` alpha fade with a three-stage sequenced transition. Stage 1: position slides from `y = -100` to `y = 0` over 0.3 s using `EASE_OUT_BACK` for a subtle bounce on entry. Stage 2: hold at full opacity for 2.5 s. Stage 3: position slides back to `y = -100` over 0.3 s while alpha transitions from 1.0 to 0.0 in parallel via a second `Tween` property track. All three stages are chained in a single `Tween` using `append`/`parallel` calls so the sequence is cancellable (new message arriving during stage 2 resets the queue per Plan B's FIFO contract). Test assertion: the Tween chain has correct duration constants (1 unit test, +1).

**Task 5 — `PainfulReveal` bust animation (MODIFY `scripts/ui/painful_reveal.gd`).**
Replaces the Plan B 2-second slide-in with a 5-step micro-animation. Step 1: scale from `0` to `1.2` over 0.15 s with `EASE_OUT` (snap-in). Step 2: scale from `1.2` to `1.0` over 0.1 s with `EASE_IN_OUT` (settle). Step 3: brief position-offset oscillation to simulate a shake (3 cycles, ±4 px, 0.12 s total). Step 4: hold RED modulate for 1.2 s. Step 5: alpha fade to `0.0` over 0.3 s. The 5-step sequence uses a single chained Tween. Test assertion: stage durations sum to expected total (1 unit test, +1).

**Task 6 — `PainfulReveal` crown animation (MODIFY `scripts/ui/painful_reveal.gd`).**
Replaces the Plan B 1.5-second pulse with a sequenced sparkle + pulse. Step 1: scale `0` → `1.0` and rotate `-15°` → `+15°` simultaneously over 0.2 s (sparkle burst). Step 2: double-pulse scale sequence `1.0 → 1.15 → 1.0 → 1.15 → 1.0` over 0.6 s total (each leg ~0.15 s). Step 3: alpha fade `1.0` → `0.0` over 0.3 s. All steps are chained Tween tracks. Test assertion: crown animation total duration is approximately 1.1 s (1 unit test, +1).

**Task 7 — `crown_delta=2` stack animation (MODIFY `scripts/ui/resolution_overlay.gd`).**
Extends the Plan B `crown_delta >= 2` rendering with a sequenced entry. The first crown icon renders via the existing path. After a 0.3 s delay, a second crown icon slides in from below: alpha `0 → 1` and position `y + 20 → y` over 0.4 s. Once the second crown is settled, the suffix text `"(Sudden Death stack!)"` fades in over 0.3 s on a separate `Label` node. The full sequence is a single Tween subgraph attached to the `crown_delta=2` branch in the results row renderer. Test assertion: the delay + slide + text-fade sequence fires only when `crown_delta >= 2` (1 unit test, +1).

### Phase 3 — Spectator full layout rework (Tasks 8-13)

**Task 8 — `SpectatorOverlay` scene + script (NEW).**
Files: `scripts/ui/spectator_overlay.gd` + `scenes/ui/spectator_overlay.tscn`. Full-screen `Control` anchored to fill the right 40% of the viewport. Internal layout: `VBoxContainer` with a fixed title label `"SPECTATING"`, a leaderboard section (sorted ranking rows), a per-event status panel (populated by Task 12), and a match-progress label. The script exposes a static formatter:

```gdscript
static func format_leaderboard(players: Array) -> Array[Dictionary]:
    # Returns players sorted by crowns desc, then chips desc.
    # Each element: { peer_id, display_name, crowns, chips, rank }
```

The formatter is pure-function and unit-testable without instantiating the scene. Test file: `tests/unit/test_spectator_overlay.gd` (+3 unit tests: sort by crowns, tiebreak by chips, single-player edge case).

**Task 9 — `local_player_spectator_mode_entered` signal (MODIFY `scripts/match/match_controller.gd`).**
A new signal `local_player_spectator_mode_entered(reason: String)` is added to `MatchController`. It fires under two conditions: (a) the local peer's `is_active_this_event` flag is `false` while the match phase is `MAIN_EVENT`; (b) the local peer's connection drops mid-match. The `reason` string carries `"busted"` or `"dropped"` to allow the UI to display context-appropriate messaging. The signal is emitted on the host and mirrors to all peers via the existing match-state RPC pathway — spectating clients need to receive it too. Two tests cover emission conditions: bust path and drop path. Test file: `tests/unit/test_match_controller_spectator_signal.gd` (+2 unit tests).

**Task 10 — Match scene visibility gating (MODIFY `scripts/ui/match_scene.gd` + `scenes/match_scene.tscn`).**
When `local_player_spectator_mode_entered` fires, `match_scene.gd` hides: `BetLoadoutOverlay`, `LoadoutOverlay`, `EventPickerOverlay`, `CashOutCardDrawer`, and `CashOutCardDrawerTargetPicker`. Simultaneously, `SpectatorOverlay` becomes visible. On `event_starting` signal, `match_scene.gd` checks if the local peer is now active; if not, the overlay stays visible (once busted, local stays in spectator mode for the rest of the match — mid-match re-entry is not supported in MVP). The visibility toggle is a direct `show()`/`hide()` on named scene nodes; no re-parenting needed for this gating step. No new unit tests (visibility gating is integration-only).

**Task 11 — Compact widget re-layout for spectator view (MODIFY `scenes/match_scene.tscn`).**
When `SpectatorOverlay` is visible, `StatusGrid`, `Announcer`, and `PainfulReveal` shift to a compact right-column layout so they don't occlude the spectator leaderboard. The preferred approach is a dedicated `SpectatorSlot` anchor container declared in `match_scene.tscn`; on the `local_player_spectator_mode_entered` signal, `match_scene.gd` re-parents those three nodes into `SpectatorSlot` at runtime. A secondary option (two pre-placed node slots, toggle visibility) is acceptable if re-parenting proves fragile during implementation. No new unit tests (layout swap is integration-only).

**Task 12 — Per-event spectator status text (MODIFY `scripts/ui/spectator_overlay.gd`).**
`SpectatorOverlay` exposes a method `format_event_status(event_id: String, ctx_data: Dictionary) -> String` that returns event-specific live status for the watched player. Branch behavior: Rocket Clash → `"P3 riding @ 4.2x"`; Bomb Pot → `"P3 in, 5s to bomb"`; Card Cannon → `"P3 score: 17/21"`. The `ctx_data` dictionary shape is event-specific (Rocket Clash passes `{ peer_id, multiplier }`; Bomb Pot passes `{ peer_id, seconds_to_bomb }`; Card Cannon passes `{ peer_id, score, target }`). Three formatter branches + their `ctx_data` shapes are documented inline. Test file: `tests/unit/test_spectator_overlay.gd` (+3 unit tests, one per event branch).

**Task 13 — Spectator overlay layout polish (MODIFY `scripts/ui/spectator_overlay.gd` + `scenes/ui/spectator_overlay.tscn`).**
Theme overrides on the `SpectatorOverlay` root `Control` increase font sizes relative to the main UI theme (leaderboard rows use a larger `theme_override_font_sizes/font_size`). Countdown widgets (bet timer, event picker timer) are never shown inside `SpectatorOverlay` — those are play-context-only nodes. The leaderboard rows are prominent and center-aligned. No new unit tests (visual-only change).

### Phase 4 — Accessibility (Tasks 14-16)

**Task 14 — Color-blind shape/icon cues (MODIFY `scripts/ui/announcer.gd`, `scripts/ui/painful_reveal.gd`).**
Bust-related display strings are prefixed with `✗` (red X character); crown messages are prefixed with `👑`; chip-loss messages append a `↓` arrow suffix. These are embedded directly in the strings returned by the static formatters (`format_bust_text`, `format_crown_text`, etc.) so color stops being the sole differentiator. Existing formatter tests in `test_announcer.gd` and `test_painful_reveal.gd` are updated to assert the icon prefix/suffix is present. Test delta: updated assertions in existing files (+2 net new assertions counted as new tests).

**Task 15 — Settings scene + text-scale toggle (NEW).**
Files: `scripts/ui/settings_overlay.gd` + `scenes/ui/settings_overlay.tscn`. The scene contains three `Button` nodes labeled `"1.0×"`, `"1.25×"`, and `"1.5×"`. Activating a button applies the selected scale factor to the root `Control` node via `theme_override_font_sizes` or `theme_type_variation`. The chosen scale is persisted via `ConfigFile` at `user://settings.cfg` under key `[display] / text_scale`. On game start, `settings_overlay.gd._ready` reads `user://settings.cfg` and re-applies the saved scale. Test file: `tests/unit/test_settings_overlay.gd` (+3 unit tests: default scale applied on fresh start, scale persisted to cfg, scale loaded and re-applied on re-init).

**Task 16 — Settings menu wiring (MODIFY `scripts/ui/match_scene.gd`, main menu scene).**
A settings gear icon or labeled `Button` is added to the match scene HUD and the main menu. Pressing it opens `SettingsOverlay` as a modal (using `popup()` on a `Window` node or a full-screen `Control` with `mouse_filter = STOP`). The overlay is dismissed via a `Close` button or by pressing Escape. The persistence from Task 15 means settings survive scene reloads with no additional wiring. Test file: `tests/unit/test_settings_overlay.gd` (+1 unit test: wiring asserts the overlay's `visible` flips on button press).

### Phase 5 — Integration + docs (Task 17)

**Task 17 — Integration test stub + playtest checklist (NEW).**
A PENDING integration test stub `tests/integration/test_sound_dispatcher.gd` documents the expected end-to-end behavior: 6 SFX cues fire on the correct `MatchController` signals in a 2-peer simulated match, and the dispatcher wiring survives a full event lifecycle. This follows the PENDING-stub convention established in sub-projects #3-6.

`docs/PLAYTEST_CHECKLIST.md` gains scenarios 35-43:
- 35: `play_bust()` SFX fires audibly on player bust
- 36: `play_crown_win()` SFX fires on crown award
- 37: `play_twist_stinger()` fires when house twist is announced
- 38: `play_match_end()` fires on match outcome
- 39: `play_button_press()` fires on UI button interactions
- 40: Announcer slide-in/hold/slide-out 3-stage animation looks correct
- 41: PainfulReveal bust micro-animation (snap, shake, hold, fade) looks correct
- 42: SpectatorOverlay appears with leaderboard when local player is busted mid-match
- 43: Text-scale toggle persists across scene reloads

## 7. Component-level change list

### Plan A
- `scripts/match/event_helpers.gd` (NEW)
- `scripts/match/player_selectors.gd` (NEW)
- `scripts/events/rocket_clash/rocket_clash_event.gd` (MODIFY — Tasks 2, 6, 7's caller if applicable)
- `scripts/events/bomb_pot/bomb_pot_event.gd` (MODIFY — Tasks 3, 6, 7)
- `scripts/events/card_cannon/card_cannon_event.gd` (MODIFY — Tasks 4, 6)
- `scripts/match/bounty_resolver.gd` (MODIFY — Task 5 delegation, Task 9 tie-split)
- `scripts/match/house_twist_controller.gd` (MODIFY — Task 5 delegation)
- `scripts/cards/effects/heat_shield.gd` (MODIFY — Task 8 doc)
- `scripts/match/match_controller.gd` (MODIFY — Task 10 RPC switch)
- `scripts/match/match_rpc_sender.gd` (MODIFY — Task 12 callv rewrite)
- New test files: `test_event_helpers.gd`, `test_player_selectors.gd`, plus assertion tighteners in existing files where API changes

### Plan B
- `scripts/ui/status_grid.gd` (NEW)
- `scenes/ui/status_grid.tscn` (NEW)
- `scripts/ui/announcer.gd` (NEW)
- `scenes/ui/announcer.tscn` (NEW)
- `scripts/ui/painful_reveal.gd` (NEW)
- `scenes/ui/painful_reveal.tscn` (NEW)
- `scripts/ui/loadout_overlay.gd` (MODIFY — full rewrite for drag-to-loadout UX)
- `scripts/ui/cash_out_card_drawer_target_picker.gd` (NEW)
- `scenes/ui/cash_out_card_drawer_target_picker.tscn` (NEW)
- `scripts/ui/event_picker_overlay.gd` (MODIFY — wire CountdownLabel tick)
- `scenes/ui/event_picker_overlay.tscn` (MODIFY — no structural change; CountdownLabel already declared)
- `scripts/ui/bet_loadout_overlay.gd` (MODIFY — countdown label + readied indicators)
- `scripts/ui/match_scene.gd` (MODIFY — wire LoadoutOverlay, target picker, new overlay slots)
- `scenes/match_scene.tscn` (MODIFY — add StatusGrid, Announcer, PainfulReveal node slots)
- `scripts/match/match_controller.gd` (MODIFY — new signals: `player_busted`, `crown_awarded`, `status_changed`, `bet_loadout_timer_tick`)
- `scripts/events/rocket_clash/rocket_clash_event.gd` (MODIFY — emit `status_changed`)
- `scripts/events/bomb_pot/bomb_pot_event.gd` (MODIFY — emit `status_changed`)
- `scripts/events/card_cannon/card_cannon_event.gd` (MODIFY — emit `status_changed`)
- New test files: `test_status_grid.gd`, `test_announcer.gd`, `test_painful_reveal.gd`, `test_loadout_overlay.gd`, `test_cash_out_card_drawer_target_picker.gd`, `test_bet_loadout_overlay.gd`, `test_event_picker_overlay.gd`, `test_results_overlay_crown_delta.gd` (~8 files)
- `tests/integration/test_announcer_fires_across_phases.gd` (NEW — PENDING stub)
- `docs/PLAYTEST_CHECKLIST.md` (MODIFY — scenarios 28-34)

### Plan C
- `scripts/audio/sound_manager.gd` (NEW) + autoload registration in `project.godot` (MODIFY)
- `scripts/audio/sound_dispatcher.gd` (NEW — may be folded into `sound_manager.gd`)
- `scripts/ui/spectator_overlay.gd` (NEW)
- `scenes/ui/spectator_overlay.tscn` (NEW)
- `scripts/ui/settings_overlay.gd` (NEW)
- `scenes/ui/settings_overlay.tscn` (NEW)
- `scripts/ui/announcer.gd` (MODIFY — Task 4 animation overhaul + Task 14 icon cues)
- `scripts/ui/painful_reveal.gd` (MODIFY — Tasks 5-6 sequenced animations + Task 14 icons)
- `scripts/ui/resolution_overlay.gd` (MODIFY — Task 7 `crown_delta=2` stack animation)
- `scripts/ui/match_scene.gd` (MODIFY — Tasks 10-11 spectator visibility gating + slot placement + Task 16 settings button wiring)
- `scenes/match_scene.tscn` (MODIFY — Task 11 `SpectatorSlot` anchor + Task 16 settings button node)
- `scripts/match/match_controller.gd` (MODIFY — Task 9 `local_player_spectator_mode_entered` signal)
- `project.godot` (MODIFY — `SoundManager` autoload registration)
- New test files: `test_sound_manager.gd`, `test_sound_dispatcher.gd`, `test_spectator_overlay.gd`, `test_settings_overlay.gd`, `test_match_controller_spectator_signal.gd` + assertion updates in `test_announcer.gd` + `test_painful_reveal.gd` (~7 files touched)
- `tests/integration/test_sound_dispatcher.gd` (NEW — PENDING stub)
- `docs/PLAYTEST_CHECKLIST.md` (MODIFY — scenarios 35-43)

## 8. Test count math

| Milestone | Unit | Integration | Notes |
|---|---|---|---|
| Sub-project #6 end | 564 | 7 pending | Baseline |
| Plan A end (target) | ~576-580 | 7 pending (unchanged) | Original target |
| Plan A end (actual) | 587 | 7 pending | ACTUAL — shipped 2026-05-13 |
| Plan B end (target) | ~606 | 8 pending | +19 unit (8 new widget test files), +1 integration (announcer stub) |
| Plan B end (actual) | 623 | 8 pending | ACTUAL — shipped 2026-05-13 |
| Plan C end (target) | ~650 | 9 pending | +27 unit (+3 SoundManager, +2 asset-slot, +2 dispatcher, +4 animations, +3 leaderboard formatter, +2 spectator signal, +3 per-event formatters, +2 icon cues, +3 text-scale, +1 settings wiring, +2 outstanding), +1 integration (sound dispatcher stub) |

**Total #7 delta (all plans):** ~+86 unit, +2 integration.

**Plan C unit test breakdown:** T1 +3 (synth params), T2 +2 (asset slot detection), T3 +2 (signal dispatcher), T4-T7 +1 each (4 animation duration/sequence assertions), T8 +3 (leaderboard formatter), T9 +2 (spectator signal emission), T10-T11 +0 (visibility gating, integration-only), T12 +3 (per-event formatters), T13 +0 (visual-only), T14 +2 (icon-cue formatter assertions), T15 +3 (text-scale persistence + theme apply), T16 +1 (wiring test), T17 +0 unit + 1 integration. Total Plan C delta: +27 unit, +1 integration.

## 9. Error handling

Refactoring does not change error semantics. The new helpers preserve existing defensive `.get()` patterns; null-guards on `context` are preserved at the helper level. RPC bandwidth changes preserve the host-authoritative validation semantics — the `is_host` guards in receivers remain unchanged (defense in depth even though `rpc_id(host)` eliminates the broadcast path).

## 10. Testing strategy

- **Refactor tests:** New `test_event_helpers.gd` + `test_player_selectors.gd` cover the extracted helpers directly. Existing event + bounty tests must continue to pass (the helper extraction is behavior-preserving).
- **Numeric edge case tests:** 1 new test per edge case (Bomb Pot no-winner, Bounty 3-way tie-split modulo).
- **RPC bandwidth tests:** Existing tests verify behavior; bandwidth change is observable only via `FakeMultiplayerNode.rpc_calls` count — add `test_match_controller_rpc_bandwidth.gd` verifying targeted vs broadcast usage for ~3 representative client→host calls.
- **Integration tests:** Unchanged from sub-project #6 (7 PENDING). Real two-peer regression coverage deferred per user decision.

## 11. Tags

- After Plan A merges: `subproject-7-plan-a-complete` **(DONE — 2026-05-13)**
- After Plan B merges: `subproject-7-plan-b-complete`
- After Plan C merges: `subproject-7-plan-c-complete` + `subproject-7-complete` + `mvp-complete`

## 12. Carry-forwards inherited from sub-project #6

All items in `project_riskroyal_followups.md` "Open from sub-project #6 final review" are scoped:

**Plan A closes:** twist consumer DRY (Tasks 1-4), find_chip_leader consolidation (Task 5), guard cleanup (Task 6), winner_pull_out_ms sentinel (Task 7), Heat Shield doc (Task 8), bounty tie-split (Task 9), RPC bandwidth (Task 10), starter pack narrowing (Task 11), MatchRpcSender arity (Task 12). — **All 8 closed; DONE.**

**Plan B closes:**
- EventPickerOverlay countdown UX (Task 4)
- `crown_delta=2` rendering in results overlay (Task 5)
- StatusGrid populated for all 3 events (Tasks 1+2)
- BetLoadoutOverlay countdown + readied indicator (Task 3)
- Cash-Out Card Drawer target picker — closes sub-project #4 Plan B carry-forward (Task 11)
- LoadoutOverlay interactive grid — closes sub-project #4 Plan A carry-forward (Tasks 9+10)
- (Announcer + PainfulReveal are new design additions, not inherited carry-forwards)

**Plan C closes:**
- SFX cues — deferred to Plan C from the §6.5 preview; now delivered via `SoundManager` autoload + signal dispatcher (Tasks 1-3)
- Polished sequenced animations — deferred from Plan B's single-Tween fades; now delivered via multi-step Tween chains for Announcer, PainfulReveal (bust + crown), and `crown_delta=2` stack (Tasks 4-7)
- Spectator behavior — originally from design doc §3 "Polish pass"; deferred from Plan B; now delivered as a full layout rework with `SpectatorOverlay`, leaderboard ranking, per-event status, and visibility gating (Tasks 8-13)
- Color-blind shape/icon cues — from §6.5 preview; delivered by embedding `✗`/`👑`/`↓` icons in static formatter output (Task 14)
- Text-scale a11y — from §6.5 preview; delivered via `SettingsOverlay` + `ConfigFile` persistence (Tasks 15-16)
- Any post-Plan-B fixup items: none flagged from Plan B's final review

**Deferred to post-MVP (v1.1):** integration test depth (the 8 PENDING stubs); spec drift reconciliation; minor test cleanup items (M1-M3 from Plan A fixup-3); high-contrast color-blind mode (full palette swap); keyboard-only nav audit. Note: high-contrast mode and keyboard-only nav were explicitly evaluated for Plan C and deferred — they are v1.1 items, not accidentally omitted.

## 13. Memory updates after #7 merges

**After Plan B merges:**
- `project_riskroyal.md` — mark Plan B done; note Plan C brainstorm needed
- `project_riskroyal_followups.md` — close the 6 UX carry-forwards that Plan B addresses (EventPickerOverlay countdown, crown_delta rendering, StatusGrid, BetLoadoutOverlay UX, target picker, LoadoutOverlay grid); flag remaining items as Plan C or post-MVP

**After Plan C merges:**
- `MEMORY.md` / `project_riskroyal.md` — mark sub-project #7 complete; MVP done; tag `mvp-complete`; note all 7 sub-projects shipped
- `project_riskroyal_followups.md` — close ALL remaining carry-forwards: SFX cues, polished animations, spectator behavior, color-blind icon cues, text-scale a11y; mark the file as "closed / MVP complete"
- Flag as post-MVP v1.1: high-contrast color-blind mode, keyboard-only nav audit, integration test depth (8 PENDING stubs), TURN server / NAT-traversal, multi-language i18n
- No further sub-project memory updates needed after #7 — MVP milestone reached
