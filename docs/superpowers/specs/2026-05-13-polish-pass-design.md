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

## 6.5. Architecture changes (Plan C preview — final MVP plan)

Plan C is the third and final plan for sub-project #7. After Plan C merges, the project receives tags `subproject-7-plan-c-complete` + `subproject-7-complete` + `mvp-complete`.

Plan C will receive its own detailed brainstorm cycle after Plan B merges. Anticipated scope (~12-15 tasks):

**SFX cues.** New autoload `scripts/audio/sound_manager.gd` manages all in-game audio. Cues: chip-transfer sound, bust sound, crown-win sound, match-end sound, button-press tactile feedback, twist-announce stinger. Free CC-0 assets are acceptable for MVP. `SoundManager` listens to the same `player_busted` / `crown_awarded` / `house_twist_announced` / `match_outcome_decided` signals added in Plan B and plays the matching cue. No SFX are added in Plan B (all Tween-only for Plan B widgets).

**Polished animations.** Replace the simple `Tween` blocks added in Plan B with sequenced animations: `Announcer` slide-in from top with ease-out, `PainfulReveal` expansion + hold + dissolve using `AnimationPlayer`, `crown_delta=2` stack pulse with a distinct GOLD burst frame, match-end winner reveal with a full-screen flash moment.

**Spectator-mode polish.** When the local peer is busted or dropped during an active match, surface a clean `"Spectating P3 (Crown leader)"` overlay. Hide play-only widgets (`BetLoadoutOverlay`, target-picker prompts, hand row). Keep `StatusGrid` and `Announcer` visible so the spectating peer can follow the game. The spectator overlay reads the crown-leader from `MatchController.state` using the existing `PlayerSelectors.find_chips_extremum` helper as a proxy until a dedicated crown-leader tracker is available.

**Color-blind accessibility.** Convert chip-loss RED / crown-win GOLD color cues in `PainfulReveal` and `StatusGrid` to also use shape/icon differentiation (e.g., a skull icon for bust, a crown icon for crown win) so color is not the sole signal. A settings toggle for a full color-blind mode is a v1.1 item unless implementation proves trivial during Plan C.

**Text scaling.** Settings toggle for 1.0× / 1.25× / 1.5× UI text scale, applied via Godot theme overrides. Allows playtesters on lower-resolution monitors to read the game without squinting.

**Post-Plan-B fixups.** Plan C may fold in any review feedback or minor bugs surfaced during Plan B playtesting.

Full task breakdown, file paths, and test targets will be specified in the Plan C design amendment after Plan B merges.

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
- Scope TBD per future brainstorm after Plan B merges.
- Expected: new `scripts/audio/sound_manager.gd` autoload + CC-0 audio assets + `scenes/ui/spectator_overlay.tscn` + `scripts/ui/spectator_overlay.gd` + settings UI nodes for a11y toggles (text scale, color-blind mode).
- Full file list will be specified in the Plan C design amendment.

## 8. Test count math

| Milestone | Unit | Integration | Notes |
|---|---|---|---|
| Sub-project #6 end | 564 | 7 pending | Baseline |
| Plan A end (target) | ~576-580 | 7 pending (unchanged) | Original target |
| Plan A end (actual) | 587 | 7 pending | ACTUAL — shipped 2026-05-13 |
| Plan B end (target) | ~606 | 8 pending | +19 unit (8 new widget test files), +1 integration (announcer stub) |
| Plan C end (target) | ~620 | 9 pending | Rough estimate — depends on Plan C brainstorm |

**Total #7 delta (all plans):** ~+56 unit, +2 integration.

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

**Plan C closes:** SFX cues, polished animations, spectator-mode polish, color-blind and text-scale accessibility — to be detailed in the Plan C brainstorm after Plan B merges.

**Deferred to post-MVP:** integration test depth (the 7 PENDING stubs); spec drift reconciliation; minor test cleanup items (M1-M3 from Plan A fixup-3); color-blind settings toggle (unless trivial in Plan C).

## 13. Memory updates after #7 merges

**After Plan B merges:**
- `project_riskroyal.md` — mark Plan B done; note Plan C brainstorm needed
- `project_riskroyal_followups.md` — close the 6 UX carry-forwards that Plan B addresses (EventPickerOverlay countdown, crown_delta rendering, StatusGrid, BetLoadoutOverlay UX, target picker, LoadoutOverlay grid); flag remaining items as Plan C or post-MVP

**After Plan C merges:**
- `MEMORY.md` / `project_riskroyal.md` — mark sub-project #7 complete; MVP done; tag `mvp-complete`
- `project_riskroyal_followups.md` — close all remaining Plan C carry-forwards (SFX, animations, spectator, a11y); flag any residuals as post-MVP / v1.1 items
