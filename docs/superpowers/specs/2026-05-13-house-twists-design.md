# House Twists — Design Spec

**Sub-project:** #6 of 7
**Date:** 2026-05-13
**Status:** Design (pre-implementation)
**Depends on:** Sub-projects #1-5 (networking, lobby, match loop, Rocket Clash, Power Cards & Bounties, Bomb Pot + Card Cannon)

## 1. Context

Risk Royal's MVP needs variety. Sub-projects #3 and #5 deliver 3 events; #4 delivers 12 cards. Without House Twists the match feels predictable — same rules every round, same event distribution, same bounty math. The design doc §8 establishes "House Twists" as temporary modifiers that change the next decision, increase table talk, create comeback chances, and punish runaway leaders. Sub-project #6 ships the 6 MVP twists per design doc §26.3.

The match-phase machine has had a `HOUSE_TWIST` phase since sub-project #2, sitting as a no-op pass-through. It fires between events (after SHOP, before next event's HOUSE_REVEAL). Sub-project #6 replaces the no-op with actual twist selection + application + announcement.

## 2. Goals

- Ship all 6 design-doc MVP twists: Double Bounty Round, No Insurance, Leader Starts Cursed, Power Surge, Lowest Chips Picks The Game, Sudden Death Jackpot.
- Twists fire automatically at HOUSE_TWIST phase for events 2-5 of a 5-event Quick Clash (no twist on event 1). 4 twists per match minimum.
- Selection is uniform random with no-repeat (no same twist back-to-back).
- A single twist is active at a time; `state.house_twist: Dictionary` carries its data.
- Twist consumers are existing collaborators reading state keys — no per-twist event modifications.
- Absorb sub-project #5's carry-forwards: events-pattern harmonization (M1 scene-path + M2 `_send_rpc` hoist) + tunable event constants via `EventContext.tuning` + no-repeat event-pool selection.
- Split into Plan A (foundation + 4 simpler twists + harmonization) and Plan B (Lowest Chips Picks async UI + Sudden Death Jackpot per-event hooks).
- **Cumulative target after Plan A merge:** ~536 unit + 5 integration (+32 new unit).
- **Cumulative target after Plan B merge:** ~551 unit + 6 integration (+15 new unit + 1 new integration).

## 3. Non-Goals

- **Weighted event-pool selection.** No-repeat ships; weighting is sub-project #7 polish.
- **Twist animation + audio.** A 3-second static banner suffices for MVP; juice is #7.
- **Multiple concurrent twists.** Exactly 0 or 1 twist active at a time. Spec §8.1: "stack into unreadable chaos" is an explicit anti-goal.
- **Player-tunable twist frequency** (every-event vs probabilistic) — locked to every-event-after-first per design decision.
- **Twist exclusion based on match length.** All 6 twists eligible across all 5 events of a Quick Clash. Sub-project decoration is sufficient.
- **Twist undo.** Once selected and announced, a twist runs to completion at the next event. No mid-event cancel.
- **Custom curse variant per Leader Starts Cursed.** MVP locks to "Reduced reward: chip_delta × 0.75 for the leader survivor." Other variants from design doc §8.2 deferred.

## 4. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope | All 6 design-doc MVP twists | Full design doc §26.3 list; completes the MVP House Twist commitment |
| Frequency | Every event 2-5 (4 twists / match) | Maximum variety; every event feels distinct |
| Selection | Uniform random, no-repeat | Cleanest variety guarantee; weighted is #7 territory |
| Twist data carrier | Single `state.house_twist: Dictionary` field | One twist active at a time; consumers read by key; round-trips cleanly via existing dict-duplicate pattern |
| Plan split | Plan A (4 simpler + harmonization) + Plan B (2 harder) | Mirrors sub-project #4 pattern; Plan A is shippable on its own |
| Power Surge definition | Bonus card to every hand at next event's HOUSE_REVEAL | Design doc didn't define; this matches §19.1's "mild, opening-floor" framing |
| Leader Cursed variant | Reduced reward: chip_delta × 0.75 | Symmetric across all 3 events; doesn't punish busted leaders (already lost wager); pure event_modifiers read |
| Lowest Chips Picks timeout | 10 seconds | Mid-range; mirrors existing BET_LOADOUT_TIMEOUT_SEC style |
| Tie-break for "lowest chips" / "chip leader" | Lowest seat_index | Matches existing pattern from Bomb Pot Crown + Card Cannon Crown |
| Sudden Death conditions per event | Cash-out > 5.0× (RC), pull-out after 80% of bomb time (BP), score = 21 (CC) | One condition per event; matches event-specific suspense moments |
| Twist announcement | `_rpc_house_twist_announced(twist_dict)` broadcast + 3-second HouseTwistOverlay banner | Mirrors sub-project #3's resolution-step broadcast pattern |
| Event tunable refactor | `EventContext.tuning: Dictionary` populated by each event's `_run`; overridable via `state.house_twist.params.tuning_overrides` | Plan A wires the infrastructure; Plan B's Sudden Death may use it |
| Events-pattern harmonization | Hoist `_send_rpc`/`_send_rpc_to_peer` + self-wire into `event_node.gd` base class; unify scene paths to `scenes/events/<event>/` | Closes M1+M2 carry-forwards from sub-project #5 final review |
| No-repeat event-pool selection | Skip `state.previous_event_id` when picking event 2-5 | Closes the smart event-pool selection carry-forward from sub-project #5 spec §12 |

## 5. Architecture

### 5.1 State layer

New fields on `MatchState`:
- `house_twist: Dictionary = {}` — currently active twist: `{type: String, params: Dictionary}` or empty
- `last_twist_type: String = ""` — most recent twist type, used for no-repeat filter
- `previous_event_id: String = ""` — most recent event scene path, used for no-repeat event selection

All three round-trip via `to_dict()` / `from_dict()` using the established `.duplicate(true)` pattern for `house_twist`.

### 5.2 Selection layer

New helper class `scripts/match/house_twist_controller.gd` (extracted in the Plan B-style collaborator pattern from sub-project #4 — pure-static `extends Object`, no class_name):

```gdscript
const TWIST_POOL: Array = [
    "double_bounty",
    "no_insurance",
    "leader_cursed",
    "power_surge",
    "lowest_chips_picks",      # Plan B
    "sudden_death_jackpot",    # Plan B
]

static func select_next_twist(state) -> Dictionary
static func compute_twist_params(twist_type: String, state) -> Dictionary
static func apply_pre_event_effects(state, twist: Dictionary) -> void
```

`select_next_twist` algorithm:
1. Build candidate pool from `TWIST_POOL`
2. Filter: remove `state.last_twist_type` if non-empty
3. Filter: if `lowest_chips_picks` in pool and all peers have equal chips, remove it
4. Filter: if `leader_cursed` in pool and all peers have equal chips, remove it
5. If filtered pool is empty (defensive — shouldn't happen with 6 entries), fall back to full pool
6. Pick uniformly via `state.rng.randi() % pool.size()`
7. Return `{type, params: compute_twist_params(type, state)}`

### 5.3 Control layer

`MatchController.HOUSE_TWIST` phase handler (currently `await _schedule_advance()` no-op) becomes:

```gdscript
MatchPhase.Phase.HOUSE_TWIST:
    _process_house_twist()
    await _schedule_advance()
```

```gdscript
func _process_house_twist() -> void:
    if not is_host:
        return
    if state.event_index == 0:
        # No twist before event 1; players need a baseline
        state.house_twist = {}
        return
    var twist = HouseTwistController.select_next_twist(state)
    state.house_twist = twist
    state.last_twist_type = twist.type
    HouseTwistController.apply_pre_event_effects(state, twist)
    _send_rpc("_rpc_house_twist_announced", [twist])
    house_twist_announced.emit(twist)
```

New signal: `signal house_twist_announced(twist_dict: Dictionary)`

New RPC: `@rpc("authority", "call_remote", "reliable") func _rpc_house_twist_announced(twist_dict: Dictionary)` — clients mirror `state.house_twist`, emit local signal for UI.

### 5.4 Twist consumers (Plan A)

Existing collaborators read `state.house_twist` keys directly. No new dispatcher branches; no new effect types.

**`BountyResolver.resolve(state, result)` reads twist multiplier; `Bounty.compute_reward(bounty)` stays pure.** The existing pure static at `Bounty.compute_reward(bounty)` (in `scripts/match/bounty.gd`) is called from `BountyResolver.resolve(state, result)` at `bounty_resolver.gd:56`. `BountyResolver.resolve` already has access to state — apply the double_bounty multiplier in the resolver, not in the pure helper:

```gdscript
# In BountyResolver.resolve(state, result), inside the loop:
var reward = Bounty.compute_reward(bounty)
if state.house_twist.get("type", "") == "double_bounty":
    var mult = float(state.house_twist.params.get("reward_multiplier", 1.0))
    reward = int(reward * mult)
# ...continue with existing single-claimant / split-on-tie logic
```

`Bounty.compute_reward` signature unchanged; all existing Bounty tests pass unmodified. Plan A Task 12 modifies `scripts/match/bounty_resolver.gd` only.

**`CardEffectDispatcher.apply(state, peer_id, effect, is_host)`** (already accepts state):

```gdscript
match t:
    "insurance_pre":
        if state.house_twist.get("type", "") == "no_insurance":
            return  # short-circuit; effect ignored under twist
        _ensure_modifiers(state, peer_id)
        state.event_modifiers[peer_id]["insurance_pre"] = true
    # ...
```

Wrapper in MatchController checks the twist before broadcasting `_rpc_card_effect_applied` — for `insurance_pre` under `no_insurance` twist, broadcasts `_rpc_card_play_rejected(card_id, "no_insurance_twist")` instead. UI surfaces the rejection reason.

**All 3 events' `compute_event_result`** read `state.house_twist` via `context.house_twist` (new EventContext field — see §5.5):

For Leader Cursed:
```gdscript
if pid == ctx.house_twist.params.get("leader_peer_id", 0):
    var leader_mult = float(ctx.house_twist.params.get("reward_multiplier", 1.0))
    chip_delta = int(chip_delta * leader_mult)
```

Applied AFTER existing wager_multiplier + underdog_multiplier; documented as multiplicative stacking.

### 5.5 Context layer

`EventContext` gains two new fields (both round-trip):
- `house_twist: Dictionary = {}` — copy of `state.house_twist` snapshotted at MAIN_EVENT entry
- `tuning: Dictionary = {}` — per-event tunable values populated by each event's `_run`

`MatchController._build_event_context` adds 2 lines:
```gdscript
ctx.house_twist = state.house_twist.duplicate(true)
# tuning is event-populated in _run; tuning_overrides merged here as a courtesy
```

Each event's `_run` populates `ctx.tuning` with its own defaults:
- Rocket Clash: `{growth_rate, instabust_prob, max_crash_at, ...}`
- Bomb Pot: `{pot_growth_per_sec, min_detonation_sec, max_detonation_sec, instabust_prob}`
- Card Cannon: `{target_score, payout_bands: {low, medium, strong, heavy, perfect}}`

Events read `ctx.tuning.get(key, MatchConfig.DEFAULT)` — backward-compatible.

Plan A wires the infrastructure but no twist uses it; Plan B may use `tuning_overrides` for Sudden Death condition thresholds if any need tuning.

### 5.6 Events pattern harmonization (Plan A)

Closes sub-project #5 final review carry-forwards M1+M2:

**M1 — scene-path unification.** Rocket Clash's scene lives at `scripts/events/rocket_clash/rocket_clash_event.tscn` (legacy from sub-project #3 — script and scene co-located). Bomb Pot and Card Cannon scenes live at `scenes/events/<event>/<event>.tscn`. Pick the latter convention; move Rocket Clash's scene to `scenes/events/rocket_clash/rocket_clash_event.tscn`; update `MatchConfig.EVENT_POOL` entry.

**M2 — `_send_rpc` deduplication.** All 3 event scripts have near-identical `_send_rpc` (arity 0-3, or 0-4 for Card Cannon) + `_send_rpc_to_peer` (arity 0-2). Hoist into `scripts/events/event_node.gd`:

```gdscript
extends Node

var _multiplayer_node = null

signal event_complete(result)
signal event_progress(payload: Dictionary)  # existing — preserved for event UIs

func get_event_id() -> String:
    return ""

func _run(context) -> void:
    if _multiplayer_node == null and is_inside_tree():
        _multiplayer_node = self

func _send_rpc(method_name: String, args: Array = []) -> void:
    if _multiplayer_node == null:
        return
    match args.size():
        0: _multiplayer_node.rpc(method_name)
        1: _multiplayer_node.rpc(method_name, args[0])
        2: _multiplayer_node.rpc(method_name, args[0], args[1])
        3: _multiplayer_node.rpc(method_name, args[0], args[1], args[2])
        4: _multiplayer_node.rpc(method_name, args[0], args[1], args[2], args[3])
        _:
            push_error("EventNode._send_rpc: unsupported arity %d" % args.size())

func _send_rpc_to_peer(peer_id: int, method_name: String, args: Array = []) -> void:
    # same shape with rpc_id
```

The 3 event scripts strip their copies and call `super._run(context)` from their overrides. All prior tests must continue to pass.

### 5.7 Smart event-pool selection (Plan A)

Closes sub-project #5 spec §12 carry-forward: no-repeat policy.

`MatchController._process_event_selection` is modified:
- Build pool = `MatchConfig.EVENT_POOL.duplicate()`
- Remove `state.previous_event_id` if non-empty
- Fall back to full pool if filter empties
- Pick uniformly via `state.rng.randi() % pool.size()`
- Set `state.previous_event_id = state.current_event_id`

Plus: if `state.house_twist.type == "lowest_chips_picks"`, the selection function early-returns and defers to the Plan B async picker flow (a new RPC pair + EventPickerOverlay UI).

Weighted selection deferred to sub-project #7.

## 6. Components

### 6.1 `scripts/match/house_twist_controller.gd` (NEW — Plan A Task 9)
Static-only `extends Object`. `TWIST_POOL` constant + `select_next_twist`, `compute_twist_params`, `apply_pre_event_effects` statics.

### 6.2 `scripts/match/match_state.gd` (MODIFY — Plan A Task 1)
Add `house_twist: Dictionary = {}`, `last_twist_type: String = ""`, `previous_event_id: String = ""` fields. Extend to_dict/from_dict.

### 6.3 `scripts/match/match_controller.gd` (MODIFY — many Plan A + Plan B tasks)
- `_process_house_twist()` (Plan A Task 11)
- `house_twist_announced` signal
- `_rpc_house_twist_announced` receiver
- `_process_event_selection` no-repeat + lowest_chips_picks deferral (Plan A Task 10)
- `_resolve_bounties` reads `state.house_twist` for double_bounty multiplier (Plan A Task 12)
- `_apply_effect_result` wrapper short-circuits insurance_pre under no_insurance (Plan A Task 13)
- `_rpc_event_picker_choice` host receiver + 10s timeout fallback (Plan B Task 3)

### 6.4 `scripts/match/bounty_resolver.gd` (MODIFY — Plan A Task 12)
`BountyResolver.resolve` reads `state.house_twist.params.reward_multiplier` and applies it to the value returned by `Bounty.compute_reward(bounty)` inside the existing loop. `Bounty.compute_reward` is unchanged (stays pure); all existing tests pass without modification.

### 6.5 `scripts/match/card_effect_dispatcher.gd` (MODIFY — Plan A Task 13)
`apply(state, peer_id, effect, is_host)` short-circuits `insurance_pre` when `state.house_twist.type == "no_insurance"`.

### 6.6 `scripts/events/event_node.gd` (MODIFY — Plan A Task 3)
Hoist `_send_rpc`/`_send_rpc_to_peer` + `_multiplayer_node` field + in-tree self-wire into base class. M2 harmonization.

### 6.7 `scripts/events/rocket_clash/rocket_clash_event.gd` + `bomb_pot_event.gd` + `card_cannon_event.gd` (MODIFY — Plan A Tasks 3, 5-7, 14; Plan B Tasks 7-9)
- Strip `_send_rpc`/`_send_rpc_to_peer` (use inherited)
- `_run` populates `ctx.tuning` defaults (Plan A Tasks 5-7)
- `compute_event_result` reads `ctx.house_twist` for `leader_cursed` per-peer multiplier (Plan A Task 14)
- `compute_event_result` reads `ctx.house_twist` for `sudden_death_jackpot` condition → bonus crown_delta (Plan B Tasks 7-9)

### 6.8 `scripts/events/event_context.gd` (MODIFY — Plan A Task 2)
Add `house_twist: Dictionary = {}` and `tuning: Dictionary = {}` fields. Extend round-trip.

### 6.9 `scenes/events/rocket_clash/rocket_clash_event.tscn` (MOVE — Plan A Task 4)
Move from `scripts/events/rocket_clash/rocket_clash_event.tscn`. M1 harmonization. Update EVENT_POOL.

### 6.10 `scripts/ui/house_twist_overlay.gd` + `.tscn` (NEW — Plan A Task 16)
PanelContainer with title + description label. Subscribes to `controller.house_twist_announced`. Static formatters `format_twist_title`, `format_twist_description`.

### 6.11 `scripts/ui/event_picker_overlay.gd` + `.tscn` (NEW — Plan B Task 4)
PanelContainer shown to picker_peer_id during EVENT_SELECTION when `state.house_twist.type == "lowest_chips_picks"`. 3 buttons; 10s countdown. Non-pickers see passive waiting banner.

### 6.12 `scripts/ui/match_scene.gd` + `match_scene.tscn` (MODIFY — Plan A Task 17; Plan B Task 5)
Add `HouseTwistSlot` + `EventPickerSlot` containers. Builder methods wire each overlay.

### 6.13 `docs/PLAYTEST_CHECKLIST.md` (MODIFY — Plan A Task 19; Plan B Task 11)
Append per-twist scenarios.

## 7. Twist Catalog

### 7.1 Double Bounty Round (Plan A)
- `type: "double_bounty"`
- `params: {reward_multiplier: 2.0, place_bounty_discount: 0.25}`
- Consumer: `BountyResolver.resolve` applies the `× 2` multiplier to the value returned by `Bounty.compute_reward(bounty)` (Bounty stays pure); Place Bounty card's effect dict reads discount and reduces `reward_chips` to 112 (150 × 0.75) at apply time

### 7.2 No Insurance (Plan A)
- `type: "no_insurance"`
- `params: {}`
- Consumer: `CardEffectDispatcher.apply` short-circuits `insurance_pre`; MatchController wrapper broadcasts `_rpc_card_play_rejected(card_id, "no_insurance_twist")`

### 7.3 Leader Starts Cursed (Plan A)
- `type: "leader_cursed"`
- `params: {leader_peer_id: int, reward_multiplier: 0.75}`
- `leader_peer_id` = `BountyResolver.find_chip_leader_peer_id(state)` at HOUSE_TWIST entry
- Consumer: all 3 events' `compute_event_result` apply multiplier to leader's chip_delta if not bust

### 7.4 Power Surge (Plan A)
- `type: "power_surge"`
- `params: {cards_dealt: Dictionary}` (peer_id → card_id)
- `apply_pre_event_effects` deals `state.rng`-drawn cards from `CardRegistry.starter_pool()`; cards appended to player.hand bypassing `MAX_HAND_SIZE` (intentional)
- Broadcasts via `_rpc_starter_pack_dealt(serialized_hands, action: "power_surge_bonus")` — extending the existing RPC's payload

### 7.5 Lowest Chips Picks The Game (Plan B)
- `type: "lowest_chips_picks"`
- `params: {picker_peer_id: int, options: Array[String], timeout_sec: 10}`
- `picker_peer_id` = player with lowest chips (seat_index tie-break)
- `options` = 3-shuffled `MatchConfig.EVENT_POOL`
- Consumer: `MatchController._process_event_selection` defers; broadcasts `_rpc_event_picker_started(picker_peer_id, options)`; awaits `_rpc_event_picker_choice(peer_id, chosen_path)` or 10s timeout; host fallback picks uniformly

### 7.6 Sudden Death Jackpot (Plan B)
- `type: "sudden_death_jackpot"`
- `params: {condition: String}` — populated **lazily** (see below). One of: `"cash_out_over_5x"`, `"pull_out_after_80_pct"`, `"locked_at_perfect"`
- **Condition selection timing** (locked decision): at HOUSE_TWIST entry, `compute_twist_params` returns `{condition: ""}` (empty — we don't yet know which event will follow). After the next EVENT_SELECTION picks `state.current_event_id`, `MatchController._process_event_selection` calls `HouseTwistController.finalize_pending_params(state)` which maps event id → condition:
  - `rocket_clash_event.tscn` → `"cash_out_over_5x"`
  - `bomb_pot_event.tscn` → `"pull_out_after_80_pct"`
  - `card_cannon_event.tscn` → `"locked_at_perfect"`
- Finalized condition is written to `state.house_twist.params.condition` and broadcast via `_rpc_event_selected(event_id, twist_params_updated)` (extending the existing event-selection broadcast)
- Consumer: each event's `compute_event_result` adds `crown_delta += 1` for any survivor meeting the condition (stacks with regular Crown). Reads from `ctx.house_twist.params.condition` snapshotted at MAIN_EVENT entry by `_build_event_context`

## 8. Data Flow

### 8.1 HOUSE_TWIST phase (Plan A)

```
Host enters HOUSE_TWIST:
  if state.event_index == 0: state.house_twist = {}; advance
  twist = HouseTwistController.select_next_twist(state)
  state.house_twist = twist
  state.last_twist_type = twist.type
  HouseTwistController.apply_pre_event_effects(state, twist)
    (power_surge: deal bonus cards via state.rng + broadcast _rpc_starter_pack_dealt)
  _send_rpc("_rpc_house_twist_announced", [twist])
  house_twist_announced.emit(twist)
  _schedule_advance → next event's HOUSE_REVEAL

Clients receive _rpc_house_twist_announced:
  state.house_twist = twist
  state.last_twist_type = twist.type
  house_twist_announced.emit(twist)
  HouseTwistOverlay shows 3-second banner, then corner chip
```

### 8.2 EVENT_SELECTION with no-repeat (Plan A)

```
Host enters EVENT_SELECTION:
  if state.house_twist.type == "lowest_chips_picks":
    return  # Plan B handler routes through _rpc_event_picker_started
  pool = MatchConfig.EVENT_POOL.duplicate()
  if state.previous_event_id non-empty: pool.erase(state.previous_event_id)
  if pool empty (defensive): pool = MatchConfig.EVENT_POOL.duplicate()
  idx = state.rng.randi() % pool.size()
  state.current_event_id = pool[idx]
  state.previous_event_id = state.current_event_id
```

### 8.3 EVENT_SELECTION with Lowest Chips Picks (Plan B)

```
Host enters EVENT_SELECTION (twist=lowest_chips_picks):
  picker_peer_id = state.house_twist.params.picker_peer_id
  options = state.house_twist.params.options
  _send_rpc("_rpc_event_picker_started", [picker_peer_id, options])
  start 10-second timer + await choice or timeout

Picker peer's EventPickerOverlay shows 3 buttons.
Non-picker peers see passive waiting banner.

Picker submits:
  submit_event_pick(chosen_path)
  -> _rpc_event_picker_choice(peer_id, chosen_path)
  Host validates: peer_id == picker_peer_id AND chosen_path in options
  Set state.current_event_id = chosen_path
  Set state.previous_event_id = chosen_path
  _send_rpc("_rpc_event_picker_resolved", [chosen_path])
  advance

Timer expires (no choice):
  Host: idx = state.rng.randi() % options.size()
  chosen = options[idx]
  Set state.current_event_id + state.previous_event_id
  _send_rpc("_rpc_event_picker_resolved", [chosen, "timeout"])
  advance
```

### 8.4 MAIN_EVENT with active twist

```
Host _build_event_context:
  Existing: players, event_index, rng_seed, is_host, wagers, event_modifiers
  NEW: ctx.house_twist = state.house_twist.duplicate(true)
  NEW: ctx.tuning = {}  (event populates in _run)

Event _run:
  ctx.tuning = {growth_rate: ..., ...}  # event-specific defaults
  # No twist-specific consumption at _run; happens in compute_event_result

Event compute_event_result(ctx, ...):
  Existing per-player chip_delta math
  NEW: if ctx.house_twist.type == "leader_cursed":
    leader_id = ctx.house_twist.params.leader_peer_id
    if pid == leader_id and not bust:
      chip_delta = int(chip_delta * ctx.house_twist.params.reward_multiplier)
  NEW: if ctx.house_twist.type == "sudden_death_jackpot":
    if _meets_condition(pid, ctx.house_twist.params.condition):
      result.per_player[pid].crown_delta += 1
```

## 9. Error Handling

| Trigger | Behavior |
|---|---|
| `state.last_twist_type` unset (event 2 first selection) | Selection pool = full 6 twists |
| All twists filtered out | Fallback to full pool (defensive; impossible with 6 entries) |
| `lowest_chips_picks` selected when all chips equal | Re-roll (filter handles this) |
| `leader_cursed` selected when all chips equal | Re-roll (filter handles this) |
| `power_surge` overflows MAX_HAND_SIZE | Intentional; bypassed. Documented |
| `no_insurance` active + Insurance played | Dispatcher short-circuits; `_rpc_card_play_rejected(card_id, "no_insurance_twist")`; UI toast |
| `leader_cursed` leader busts | Multiplier ignored (only applies to survivors) |
| `leader_cursed` leader plays Multiplier Booster | Both multipliers stack sequentially (`× 1.25 × 0.75 = × 0.9375`). Documented |
| `double_bounty` × bounty reward overflow | `int(reward × 2.0)` — no overflow at MVP chip ranges |
| `lowest_chips_picks` picker disconnects mid-pick | `NetSessionState.PAUSED` freezes; 30s expiry → host fallback picks |
| `lowest_chips_picks` picker times out (10s) | Host picks uniformly random from options. Broadcasts `_rpc_event_picker_resolved(chosen, "timeout")` |
| `lowest_chips_picks` picker selects invalid event_id | Host silent reject (picker UI should have only shown 3 buttons) |
| `sudden_death_jackpot` condition matches busted player | Bust precludes bonus Crown (non-survivor) |
| `sudden_death_jackpot` condition matches Crown winner | Bonus Crown stacks: `crown_delta = 2`. Documented as the only crown_delta=2 scenario |
| Twist active during reconnect | Existing late-RPC catch-up sends `state.house_twist` to new peer |
| `state.house_twist` round-trip via to_dict/from_dict | `.duplicate(true)` handles nested params dict safely |

## 10. Testing

### 10.1 Tier 1 — `HouseTwistController` selection + params

`tests/unit/test_house_twist_controller.gd`:
- test_select_next_twist_picks_from_full_pool_when_no_history
- test_select_next_twist_excludes_last_twist_type
- test_select_next_twist_excludes_lowest_chips_picks_when_equal_chips
- test_select_next_twist_excludes_leader_cursed_when_equal_chips
- test_select_next_twist_deterministic_with_same_seed
- test_compute_twist_params_leader_cursed_identifies_chip_leader
- test_compute_twist_params_double_bounty_carries_multipliers
- test_apply_pre_event_effects_power_surge_deals_bonus_cards
- test_apply_pre_event_effects_no_op_for_state_only_twists

### 10.2 Tier 2 — State field round-trip

`tests/unit/test_match_state_house_twist_field.gd`:
- 4 tests: defaults + previous_event_id + last_twist_type + round-trip preserves

### 10.3 Tier 3 — Controller integration (Plan A)

`tests/unit/test_match_controller_house_twist_phase.gd`:
- 5 tests: select+broadcast, no-op at event 1, advance after announce, no-repeat selection, fallback to full pool

### 10.4 Tier 4 — Twist consumers (Plan A)

- `test_bounty_resolver_double_bounty.gd` — 2 tests
- `test_card_effect_dispatcher_no_insurance.gd` — 2 tests
- `test_rocket_clash_event_leader_cursed.gd` + Bomb Pot + Card Cannon — 3 files, 1 test each

### 10.5 Tier 5 — UI (Plan A)

`tests/unit/test_house_twist_overlay.gd` — 2 static formatter tests (title + description per twist)

### 10.6 Tier 6 — Tunable constants prep (Plan A)

`tests/unit/test_event_context_tuning_field.gd`:
- 5 tests: defaults + round-trip + 3 event _run-populates tests

### 10.7 Tier 7 — Lowest Chips Picks (Plan B)

- `test_event_picker_overlay.gd` — 3-4 static formatter tests
- `test_match_controller_event_picker.gd` — 5-6 RPC flow tests (picker submit, host validation, timeout fallback, non-picker reject, disconnect)

### 10.8 Tier 8 — Sudden Death Jackpot (Plan B)

- `test_rocket_clash_event_sudden_death.gd` + Bomb Pot + Card Cannon — 3 files, 2 tests each

### 10.9 Integration test (Plan B — PENDING stub)

`tests/integration/test_lowest_chips_picks_flow.gd` — host + joiner end-to-end picker flow. PENDINGs without signaling server per sub-project #3/#4/#5 precedent.

### 10.10 Cumulative targets

- **Baseline:** 504 unit + 5 integration (post sub-project #5)
- **After Plan A:** ~536 unit + 5 integration (+32 new unit; tier-by-tier: 9+4+5+7+2+5 = 32)
- **After Plan B:** ~551 unit + 6 integration (+15 new unit + 1 new integration; tier-by-tier: 9 picker + 6 sudden death = 15)
- **Total sub-project #6:** +47 new unit + 1 new integration

## 11. Open Questions / Future Work

- **Weighted event-pool selection** — Plan A ships no-repeat; weighting is sub-project #7. Could be House-Twist-overridable.
- **Twist animation + audio** — sub-project #7 polish.
- **Curse variant selection** (design doc lists 4) — MVP locks to "reduced reward." Future tuning may want runtime-selectable curse types.
- **Twist intensity scaling by Floor** — design doc §19.1 ("Opening Floor: House Twists are mild") vs §19.2 ("High Roller Floor: stronger swings"). MVP treats all events 2-5 identically. Future #7 could weight pool by event_index.
- **Power Surge stacking with starter pack** — Power Surge fires at HOUSE_TWIST phase before next event's HOUSE_REVEAL; starter pack is only dealt at match start. They don't conflict but the same `_rpc_starter_pack_dealt` payload is reused for both.
- **Sudden Death + Crown stacking math** — `crown_delta = 2` is the only place crown stacks. UI rendering of "2 crowns" needs polish-pass attention.

## 12. Contract Summary for Downstream Sub-Projects

**For sub-project #7 (Polish):**
- Weighted event-pool selection lands here. The infrastructure to do this is already in `_process_event_selection`; #7 just needs to read weights from `MatchConfig.EVENT_WEIGHTS` or `state.event_weights`.
- Twist announce animation + audio. The `house_twist_announced` signal carries the full twist dict; #7's animation layer hooks here.
- Per-Floor twist intensity (mild vs strong) — could plug into `HouseTwistController.select_next_twist` via an intensity tier filter.
- Sudden Death bonus Crown UI (`crown_delta = 2` rendering).

**For future sub-projects adding twists:**
- Add entry to `HouseTwistController.TWIST_POOL` constant.
- Define `compute_twist_params(twist_type, state)` branch.
- Add filter rules in `select_next_twist` if the twist has prerequisites (e.g. "lowest_chips_picks requires unequal chips").
- Add `apply_pre_event_effects` branch if the twist eagerly mutates state.
- Add reader logic to the relevant consumer (BountyResolver, CardEffectDispatcher, or event's compute_event_result).

**For future sub-projects adding events:**
- `extends event_node.gd` and call `super._run(context)` first to get the `_multiplayer_node` self-wire.
- Populate `ctx.tuning` in `_run` with event-specific defaults so House Twists can override.
- Read `ctx.house_twist` in `compute_event_result` for any twist-condition handling.
- Place the `.tscn` under `scenes/events/<event>/<event>.tscn` (unified per sub-project #6).

**Contract that does NOT change:**
- `EventNode.event_complete` signal shape.
- `EventResult` shape (chip_delta, crown_delta, heat_delta, bust, cash_out_at, painful_reveal).
- `CardEffectDispatcher.apply` signature.
- RESOLUTION pipeline substep ordering.
- The 12-card library and its compatibility matrix.
- `BountyResolver.auto_place` algorithm unchanged. `BountyResolver.resolve` gains a state-read for the double_bounty multiplier; `Bounty.compute_reward(bounty)` signature unchanged (stays pure).
