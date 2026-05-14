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

**Cumulative target after #7 merge:** ~590 unit + 7-8 integration tests.

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
| Plan split | Plan A (debt paydown) → Plan B (UX polish) | Cleanups first means polish lands on a tidy codebase; halves the surface area per plan |
| Plan A scope | Refactor + numeric edge cases + RPC bandwidth (skip new integration tests) | User decision 2026-05-13: integration test depth deferred; can fold into Plan B or post-MVP polish |
| Plan B scope | UX polish for public playtest | Visible game work; the most player-facing pass |
| Helper organization | Two new helper modules: `EventHelpers` + `PlayerSelectors` | Separation of concerns; each ~40 lines; sub-project #4 collaborator pattern |
| Starter pack broadcast | Narrow to per-peer `rpc_id()` | Real bandwidth win for Power Surge + initial deal |
| Announcer scope | Text overlays only, no TTS | TTS is a v1.1 / post-MVP polish item |

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

## 6. Architecture changes (Plan B preview)

Plan B is written after Plan A merges; its design will be brainstormed at that time. Anticipated scope (~15-20 tasks):

- **StatusGrid populated** — Rocket Clash currently has empty `StatusGrid` HBoxContainer; populate with per-peer status chips (in/cashed/busted) during MAIN_EVENT.
- **BetLoadoutOverlay countdown + readied indicator** — phase has timeout but no UI feedback; players don't know how long they have.
- **EventPickerOverlay countdown** — Plan B Task 10 (sub-project #6) deferred the countdown; #7 wires it.
- **`crown_delta = 2` rendering polish** — Sudden Death + Crown stacks to 2; results overlay needs visual confirmation it shows "2 crowns" clearly.
- **LoadoutOverlay interactive button-grid** — Plan A of sub-project #4 deferred the real interactive grid (static formatters only today).
- **Cash-Out Card Drawer target picker** — Cash-Out Jammer is target_required but UI submits with target_peer_id=0; non-functional via UI today.
- **Announcer text overlays** — text-only ("HOUSE TWIST: Double Bounty Round!", "P2 EJECTED!", "CRASH!", etc.); no TTS.
- **Painful reveals** — when a peer busts, brief overlay showing the chip loss + reason; spec § 3 polish item.
- **Results juice** — chip animations, sound cues for chip transfers; spec § 3 polish item.
- **Spectator behavior** — when local peer is dropped or all-bust, UI shows a clean spectator view rather than dead overlays.

Plan B test count target: ~590 unit + maybe +1 integration.

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
- TBD after Plan A merge — anticipated: 4-6 new UI scenes/scripts, 5-8 MatchScene wiring touches, ~5 new test files for static formatters

## 8. Test count math

| Milestone | Unit | Integration |
|---|---|---|
| Sub-project #6 end | 564 | 7 pending |
| Plan A end (target) | ~576-580 | 7 pending (unchanged) |
| Plan B end (target) | ~590 | 7-8 pending |

**Total #7 delta:** ~+26 unit, maybe +1 integration.

## 9. Error handling

Refactoring does not change error semantics. The new helpers preserve existing defensive `.get()` patterns; null-guards on `context` are preserved at the helper level. RPC bandwidth changes preserve the host-authoritative validation semantics — the `is_host` guards in receivers remain unchanged (defense in depth even though `rpc_id(host)` eliminates the broadcast path).

## 10. Testing strategy

- **Refactor tests:** New `test_event_helpers.gd` + `test_player_selectors.gd` cover the extracted helpers directly. Existing event + bounty tests must continue to pass (the helper extraction is behavior-preserving).
- **Numeric edge case tests:** 1 new test per edge case (Bomb Pot no-winner, Bounty 3-way tie-split modulo).
- **RPC bandwidth tests:** Existing tests verify behavior; bandwidth change is observable only via `FakeMultiplayerNode.rpc_calls` count — add `test_match_controller_rpc_bandwidth.gd` verifying targeted vs broadcast usage for ~3 representative client→host calls.
- **Integration tests:** Unchanged from sub-project #6 (7 PENDING). Real two-peer regression coverage deferred per user decision.

## 11. Tags

- After Plan A merges: `subproject-7-plan-a-complete`
- After Plan B merges: `subproject-7-plan-b-complete` + `subproject-7-complete` + `mvp-complete`

## 12. Carry-forwards inherited from sub-project #6

All items in `project_riskroyal_followups.md` "Open from sub-project #6 final review" are scoped:
- **Plan A closes:** twist consumer DRY (Tasks 1-4), find_chip_leader consolidation (Task 5), guard cleanup (Task 6), winner_pull_out_ms sentinel (Task 7), Heat Shield doc (Task 8), bounty tie-split (Task 9), RPC bandwidth (Task 10), starter pack narrowing (Task 11), MatchRpcSender arity (Task 12).
- **Plan B closes:** EventPickerOverlay countdown UX, `crown_delta=2` rendering, StatusGrid UX, BetLoadoutOverlay countdown/readied, Cash-Out Card Drawer target picker, LoadoutOverlay interactive grid.
- **Deferred to post-MVP:** integration test depth (the 7 PENDING stubs); spec drift reconciliation; minor test cleanup items (M1-M3 from Plan A fixup-3).

## 13. Memory updates after #7 merges

- `MEMORY.md` / `project_riskroyal.md` — mark sub-project #7 complete; MVP done; tag `mvp-complete`
- `project_riskroyal_followups.md` — close all carry-forwards Plan A + Plan B addressed; flag any remaining as post-MVP / v1.1 items
