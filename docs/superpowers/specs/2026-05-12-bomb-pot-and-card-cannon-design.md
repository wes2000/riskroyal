# Bomb Pot + Card Cannon — Design Spec

**Sub-project:** #5 of 7
**Date:** 2026-05-12
**Status:** Design (pre-implementation)
**Depends on:** Sub-projects #1 (networking) / #2 (match loop) / #3 (Rocket Clash + EventNode contract) / #4 (Power Cards + Bounties)

## 1. Context

Risk Royal's MVP needs more than one event to feel like a varied party game. Sub-project #3 shipped Rocket Clash as the first event and validated the `EventNode` contract. Sub-project #4 shipped the 12-card library that operates via `EventContext.event_modifiers` and post-event `pending_card_effects`. Sub-project #5 ships two more events (Bomb Pot, Card Cannon) so the rotation has variety. No new cards; the events consume the existing 12-card contract.

The design doc (`docs/RiskRoyal_DesignDoc.md`) §11 (Bomb Pot) and §14 (Card Cannon) describe the fantasy and full vision. This spec scopes those to MVP.

## 2. Goals

- Implement two new events that satisfy the `EventNode` contract from sub-project #2.
- Both events emit `EventResult` consumed unchanged by the existing RESOLUTION → BOUNTY_HEAT_UPDATE pipeline.
- Both events respect `EventContext.event_modifiers` so the 10 universal cards from sub-project #4 work without code changes to those cards.
- Append two scene paths to `MatchConfig.EVENT_POOL`; selection logic unchanged (uniform random).
- Cumulative test target after merge: **~475 unit + 5 integration** (453 + ~22 new unit + 1 new integration).

## 3. Non-Goals

- **No new cards.** The two Rocket-Clash-specific cards (Cash-Out Jammer, Emergency Eject) and one numeric-trigger card (Late Cash) silently no-op in the new events. Documented in §6.
- **No new dispatcher branches.** `CardEffectDispatcher.apply` is unchanged.
- **No event selection refactor.** Uniform random across the now-3-event pool; no-repeat policy / weighting / shuffle-without-replacement deferred to sub-project #6 (House Twists).
- **No Card Cannon face cards (J/Q/K/Joker).** Design doc §14.5 lists them but they require intra-event sabotage mechanics that violate the no-new-cards scope. Defer.
- **No Bomb Pot Power Card hooks** (Lockout, Blast Suit, Fuse Peek, etc. from §11.7) — same reason.
- **No bomb-danger UI hints** (cold/warm/critical from §11.5). Pure pressure UI: pot grows, ticking audio is sub-project #7 polish.
- **No animations, audio, or polish.** Sub-project #7.
- **No multi-deck Card Cannon / card counting.** Infinite-deck distribution.

## 4. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Sub-project scope | Both events in one sub-project, zero new cards | Two events are similar architectural surface (EventNode + RPC pattern). Splitting would duplicate context-loading overhead. |
| Bomb Pot share-tracking | Shared Pot Drain (recommended by design doc §11.4) | Creates table tension: stay longer to out-wait others. More dramatic than independent meters. |
| Bomb Pot starting posture | All active players grabbing by default; only action is "pull out" | Mirrors Rocket Clash's "everyone rides; cash out is the choice". No idle/active toggle UI needed. |
| Bomb timer model | Hidden seeded `bomb_at_sec` drawn from a 5-25s distribution with 5% instabust at 5.0s | Mirrors `RocketClashEvent.compute_crash_at` pattern; same determinism guarantees; reuses Rocket Clash's test seam idiom. |
| Card Cannon face cards | None (number cards 2-10 + Ace only) | Scope decision per "no new cards"; face card effects (Jack/Queen/King intra-event sabotage) require mechanisms that don't exist in the global card system. |
| Card Cannon deck | Infinite-deck (independent per-draw probability) | Simpler than multi-deck; no card counting in MVP. Each rank 2-10 equally likely; Ace separate. |
| Card Cannon payout | Score-band tiers per §14.6: 1-10→×0.5, 11-15→×1.0, 16-18→×1.5, 19-20→×2.0, 21→×3.0 | Matches design doc's mental model. Discrete thresholds players can plan around. |
| Card Cannon turn model | Async per-player draws/locks | Each player drives their own pace; event finishes when all settle. No lockstep round synchronization needed. |
| Card × event compatibility | Late Cash + Jammer + Eject silently no-op in new events | Document the matrix (§6); players learn applicability. Cheaper than reinterpretation; less defensive than UI-level blocking. |
| Event pool selection | Keep uniform random unchanged | Sub-project #6 (House Twists) territory; out of scope here. |
| Heat distribution | Crown winner +1 heat (halved to 0 by Heat Shield) — same as Rocket Clash | Consistent across all 3 events. |

## 5. Architecture

Both events extend `scripts/events/event_node.gd` (the contract from sub-project #2) and implement:
- `get_event_id() -> String`
- `_run(context)` — host kicks off the event
- `event_complete(result)` signal — fired with the `EventResult` at end
- `compute_event_result(context, ...) -> EventResult` static — pure-math result builder testable without scene
- `set_cash_out_delay(peer_id, delay_ms)` — **NOT implemented** (Cash-Out Jammer's hook). `MatchController._inject_pending_event_effects` is already type-guarded (`if not event.has_method("set_cash_out_delay"): return`), so Jammer's queued delay sits unconsumed in `state.pending_card_effects`. RESOLUTION's `_apply_card_effects_to_result` consumes only `wager_tax` and `heat_delta` entries during its loop, then unconditionally clears `state.pending_card_effects = []` at the end — so leftover `cash_out_delay` entries get cleaned up correctly without being applied.

**RPC pattern:** Both events follow Rocket Clash's pattern. Host receives `_rpc_<action>_requested` via `@rpc("any_peer", "call_local", "reliable")`; broadcasts confirmation via `@rpc("authority", "call_remote", "reliable")` mirrors. `_send_rpc` + `_send_rpc_to_peer` helpers added to each event script (mirror of Rocket Clash).

**State storage:** Both events keep per-round transient state in instance fields (not `state.something`). The `EventResult` returned from `compute_event_result` is the only thing that crosses back into match state via the existing RESOLUTION pipeline.

## 6. Card × Event Compatibility Matrix

| Card | Plan A/B | Rocket Clash | Bomb Pot | Card Cannon |
|---|---|---|---|---|
| Insurance | A | ✓ halves bust | ✓ halves bust | ✓ halves bust |
| Heat Shield | A | ✓ halves winner heat | ✓ halves winner heat | ✓ halves winner heat |
| Multiplier Booster | A | ✓ survivor × 1.25 | ✓ survivor × 1.25 | ✓ survivor × 1.25 |
| Late Cash | A | ✓ +200 if cash_out > 5.0× | no-op | no-op |
| Underdog Odds | A | ✓ chip-minimum × 1.5 | ✓ chip-minimum × 1.5 | ✓ chip-minimum × 1.5 |
| Double or Nothing | A | ✓ wager × 2 | ✓ wager × 2 (ante doubled) | ✓ wager × 2 |
| Heat Spike | B | ✓ post-event +2 heat | ✓ post-event +2 heat | ✓ post-event +2 heat |
| Wager Tax | B | ✓ 20% redirect | ✓ 20% redirect | ✓ 20% redirect |
| Place Bounty | B | ✓ state-level | ✓ state-level | ✓ state-level |
| Copycat Bet | B | ✓ wager copy | ✓ wager copy | ✓ wager copy |
| Cash-Out Jammer | B | ✓ 750ms delay | no-op | no-op |
| Emergency Eject | B | ✓ auto-cash at 3.0× | no-op | no-op |

**No-op rationale:** Late Cash's threshold is "cash_out_at > 5.0" (in multiplier units that only Rocket Clash uses). Jammer + Eject both reference Rocket Clash's mid-event cash-out mechanic. None of these read or affect anything new events touch. The cards' `apply()` still executes during BET_LOADOUT; their `event_modifiers` flags are written; the new events just don't read those keys. `compute_event_result` for Bomb Pot / Card Cannon ignores `late_cash_bonus` / `auto_eject_loaded`. Cash-Out Jammer's `cash_out_delay` pending entry sits unconsumed in `state.pending_card_effects` until RESOLUTION clears the list.

## 7. Bomb Pot Event

### 7.1 File structure

- `scripts/events/bomb_pot/bomb_pot_event.gd` — script extending `EventNode`
- `scenes/events/bomb_pot/bomb_pot_event.tscn` — scene with `PotLabel`, `TickerLabel`, `PullOutButton`

### 7.2 Constants (added to `MatchConfig`)

```gdscript
const BOMB_POT_POT_GROWTH_PER_SEC: float = 50.0  # chips/sec total distributed
const BOMB_POT_MIN_DETONATION_SEC: float = 5.0
const BOMB_POT_MAX_DETONATION_SEC: float = 25.0
const BOMB_POT_INSTABUST_PROB: float = 0.05  # 5% chance of bomb at MIN_DETONATION
```

### 7.3 Fields

```gdscript
var _bomb_at_sec: float = 0.0           # hidden; set in _run via compute_bomb_at
var _start_time_ms: int = 0
var _pulled_out_peers: Array = []       # peer_ids who pulled out
var _pull_out_timestamps: Dictionary = {} # peer_id -> int elapsed_ms at pull-out (host populates; clients mirror)
var _locked_shares: Dictionary = {}     # peer_id -> int chips locked at pull-out
var _shares_accumulator: Dictionary = {} # peer_id -> float fractional chips since last frame
var _active_peers: Array = []           # peer_ids active at launch
var _is_host: bool = false
var _finished: bool = false
var _stashed_context = null
var _multiplayer_node = null            # injected for FakeMultiplayerNode tests

# Test seams
var _force_bomb_at_override: float = -1.0   # negative = use RNG
var _pot_growth_rate_override: float = -1.0 # negative = use MatchConfig
```

### 7.4 Lifecycle

**`_run(context)`:**
1. `_stashed_context = context`; `_is_host = context.is_host`
2. Active peers = `context.players` where `is_active_this_event`
3. Host: roll `_bomb_at_sec = compute_bomb_at(rng)` (or use override)
4. Host: broadcast `_rpc_bomb_pot_started(start_time_ms, bomb_at_sec_NOT_BROADCAST_kept_secret)` — only `start_time_ms` is shared so clients can render the elapsed-time tick. Bomb time stays host-side.
5. Set `set_process(true)`

**`_process(_delta)`:**
1. If `_finished` or `_start_time_ms == 0`: return
2. Update `TickerLabel` text with elapsed time / pot value (for HUD pressure)
3. Host: accumulate per-peer shares:
   - `active_count = _active_peers.size() - _pulled_out_peers.size()`
   - If `active_count == 0`: skip accumulation (no grabbers)
   - Per-tick chips = `_delta * pot_growth_rate / active_count`
   - For each active grabber (not pulled out): `_shares_accumulator[pid] += per_tick_chips`
4. Host: check bomb fire: `elapsed_sec = (now - _start_time_ms) / 1000.0`; if `elapsed_sec >= _bomb_at_sec`: call `_finish()`
5. Host: check early finish: if all active peers pulled out: call `_finish()`

**`submit_pull_out()` (public, called by local UI):**
```gdscript
var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
_send_rpc("_rpc_pull_out_requested", [my_peer_id])
```

**`_rpc_pull_out_requested(peer_id)` `@rpc("any_peer", "call_local", "reliable")`:**
1. Host-only; return if not host
2. Return if `_finished` or `_start_time_ms == 0`
3. Return if `peer_id in _pulled_out_peers` (silent double-tap drop)
4. Compute `elapsed_ms = Time.get_ticks_msec() - _start_time_ms`
5. Lock share: `_locked_shares[peer_id] = int(_shares_accumulator.get(peer_id, 0.0))`
6. Record timestamp on host: `_pull_out_timestamps[peer_id] = elapsed_ms`
7. Append to `_pulled_out_peers`
8. Broadcast `_rpc_pull_out_confirmed(peer_id, _locked_shares[peer_id], elapsed_ms)`

**`_rpc_pull_out_confirmed(peer_id, locked_share, pull_out_time_ms)` `@rpc("authority", "call_remote", "reliable")`:**
1. Mirror state on client: `_pulled_out_peers.append(peer_id)`, `_locked_shares[peer_id] = locked_share`, `_pull_out_timestamps[peer_id] = pull_out_time_ms`

**`_finish()`:**
1. `_finished = true`; `set_process(false)`
2. Compute `pull_out_timestamps` dict for Crown determination (host knows; mirror via `_rpc_pull_out_confirmed.pull_out_time_ms` on clients)
3. Call `compute_event_result(_stashed_context, _bomb_at_sec, _locked_shares, _pulled_out_peers, pull_out_timestamps)` → `event_complete.emit(result)`

### 7.5 `compute_bomb_at(rng)` static

```gdscript
static func compute_bomb_at(rng: RandomNumberGenerator) -> float:
    var instabust_roll = rng.randf()
    if instabust_roll < MatchConfig.BOMB_POT_INSTABUST_PROB:
        return MatchConfig.BOMB_POT_MIN_DETONATION_SEC
    var r = rng.randf()  # [0, 1)
    # Distribute over the 5-25s window with rising danger
    var t = MatchConfig.BOMB_POT_MIN_DETONATION_SEC + (MatchConfig.BOMB_POT_MAX_DETONATION_SEC - MatchConfig.BOMB_POT_MIN_DETONATION_SEC) * r
    return clamp(t, MatchConfig.BOMB_POT_MIN_DETONATION_SEC, MatchConfig.BOMB_POT_MAX_DETONATION_SEC)
```

### 7.6 `compute_event_result(context, bomb_at_sec, locked_shares, pulled_out_peers, pull_out_timestamps) -> EventResult` static

```gdscript
static func compute_event_result(context, bomb_at_sec: float, locked_shares: Dictionary,
                                 pulled_out_peers: Array, pull_out_timestamps: Dictionary) -> RefCounted:
    var result = EventResult.new()
    result.event_id = "bomb_pot"
    var summary: Array = []
    var winner_peer_id = 0
    var winner_pull_out_ms = -1
    var winner_seat = INF
    var modifiers = {}
    if context != null and "event_modifiers" in context:
        modifiers = context.event_modifiers
    for player in context.players:
        var pid = player.peer_id
        var wager = int(context.wagers.get(pid, 0))
        var p_mods = modifiers.get(pid, {})
        if pid in pulled_out_peers:
            # Survivor
            var chip_delta = int(locked_shares.get(pid, 0))
            # Apply universal cards
            var wm = float(p_mods.get("wager_multiplier", 1.0))
            if wm != 1.0:
                chip_delta = int(chip_delta * wm)
            var um = float(p_mods.get("underdog_multiplier", 1.0))
            if um != 1.0:
                chip_delta = int(chip_delta * um)
            result.per_player[pid] = {
                "chip_delta": chip_delta,
                "crown_delta": 0,
                "heat_delta": 0,
                "bust": false,
                "cash_out_at": 0.0,  # unused; preserved for shape compat
            }
            summary.append({
                "peer_id": pid, "name": player.name,
                "locked_share": locked_shares.get(pid, 0),
                "pull_out_ms": pull_out_timestamps.get(pid, 0),
                "chip_delta": chip_delta, "busted": false, "wager": wager,
            })
            # Track latest puller for Crown. Ties (extremely unlikely in ms
            # timestamps but defensive): lowest seat_index wins — deterministic.
            var ts = int(pull_out_timestamps.get(pid, 0))
            if ts > winner_pull_out_ms or (ts == winner_pull_out_ms and player.seat_index < winner_seat):
                winner_pull_out_ms = ts
                winner_peer_id = pid
                winner_seat = player.seat_index
        else:
            # Bust (still grabbing when bomb fired)
            var bust_loss = wager
            if p_mods.get("insurance_pre", false):
                bust_loss = int(wager / 2)
            result.per_player[pid] = {
                "chip_delta": -bust_loss,
                "crown_delta": 0,
                "heat_delta": 0,
                "bust": true,
                "cash_out_at": 0.0,
            }
            summary.append({
                "peer_id": pid, "name": player.name,
                "locked_share": 0, "pull_out_ms": 0,
                "chip_delta": -bust_loss, "busted": true, "wager": wager,
            })
    # Crown + heat to last-puller (if any survivor)
    if winner_peer_id != 0:
        result.per_player[winner_peer_id]["crown_delta"] = 1
        var winner_mods = modifiers.get(winner_peer_id, {})
        var heat_delta = 1
        if winner_mods.get("heat_shield", false):
            heat_delta = int(heat_delta / 2)
        result.per_player[winner_peer_id]["heat_delta"] = heat_delta
    result.painful_reveal = {
        "bomb_at_sec": bomb_at_sec,
        "winner_peer_id": winner_peer_id,
        "winner_pull_out_ms": winner_pull_out_ms,
        "pulls_summary": summary,
    }
    return result
```

### 7.7 Crown rule

Crown winner = peer with the **latest pull-out timestamp** among non-busted players. Ties (extremely unlikely in floats but for safety): lowest seat_index wins (deterministic).

## 8. Card Cannon Event

### 8.1 File structure

- `scripts/events/card_cannon/card_cannon_event.gd`
- `scenes/events/card_cannon/card_cannon_event.tscn` — scene with `ScoreLabel`, `HandRow` (HBoxContainer for drawn cards), `DrawButton`, `LockButton`

### 8.2 Constants (added to `MatchConfig`)

```gdscript
const CARD_CANNON_TARGET_SCORE: int = 21
const CARD_CANNON_PAYOUT_BAND_LOW: float = 0.5    # 1-10
const CARD_CANNON_PAYOUT_BAND_MEDIUM: float = 1.0 # 11-15
const CARD_CANNON_PAYOUT_BAND_STRONG: float = 1.5 # 16-18
const CARD_CANNON_PAYOUT_BAND_HEAVY: float = 2.0  # 19-20
const CARD_CANNON_PAYOUT_BAND_PERFECT: float = 3.0 # 21
```

### 8.3 Fields

```gdscript
var _hands: Dictionary = {}             # peer_id -> Array[int] of drawn rank values
var _scores: Dictionary = {}            # peer_id -> int current score (Ace handled per-recompute)
var _locked_scores: Dictionary = {}     # peer_id -> int score at lock
var _busted: Dictionary = {}            # peer_id -> bool
var _active_peers: Array = []
var _is_host: bool = false
var _finished: bool = false
var _stashed_context = null
var _multiplayer_node = null

# Test seams
var _force_next_rank_override: int = -1     # for deterministic draws
var _force_lock_scores_override: Dictionary = {}  # peer_id -> int for fast-resolve tests
```

### 8.4 Lifecycle

**`_run(context)`:**
1. `_stashed_context = context`; `_is_host = context.is_host`
2. `_active_peers = [p.peer_id for p in context.players if is_active_this_event]`
3. Initialize per-peer empty hand + score 0 + bust false
4. Broadcast `_rpc_card_cannon_started()`
5. No `_process` needed — Card Cannon is purely event-driven (RPC-driven)

**`submit_draw()` / `submit_lock()` (public):**
```gdscript
func submit_draw() -> void:
    var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
    _send_rpc("_rpc_draw_requested", [my_peer_id])

func submit_lock() -> void:
    var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
    _send_rpc("_rpc_lock_requested", [my_peer_id])
```

**`_rpc_draw_requested(peer_id)` `@rpc("any_peer", "call_local", "reliable")`:**
1. Host-only
2. Return if `_finished`
3. Return if `peer_id in _locked_scores` or `_busted.get(peer_id, false)` (silent)
4. Return if `peer_id not in _active_peers`
5. Draw rank via `compute_next_rank(_stashed_context.rng)` (or override)
6. Append to `_hands[peer_id]`
7. Recompute score with Ace = 11 unless busted, else 1 (per §14.4)
8. `_scores[peer_id] = new_score`
9. If `new_score > 21`: `_busted[peer_id] = true`
10. Broadcast `_rpc_card_drawn(peer_id, rank, new_score, is_busted)`
11. If `_all_active_settled()`: `_finish()`

**`_rpc_lock_requested(peer_id)` `@rpc("any_peer", "call_local", "reliable")`:**
1. Host-only
2. Return if `_finished` or already locked/busted
3. `_locked_scores[peer_id] = _scores.get(peer_id, 0)`
4. Broadcast `_rpc_locked(peer_id, _locked_scores[peer_id])`
5. If `_all_active_settled()`: `_finish()`

**`_rpc_card_drawn(peer_id, rank, new_score, is_busted)` `@rpc("authority", "call_remote", "reliable")`:**
- Mirror state on client

**`_rpc_locked(peer_id, locked_score)` `@rpc("authority", "call_remote", "reliable")`:**
- Mirror state on client

**`_all_active_settled() -> bool`:**
- All active peers have either locked or busted

**`_finish()`:**
1. `_finished = true`
2. Apply pause-30s-AFK auto-lock for any active peer still mid-draw (mirrors Bomb Pot's pause semantics — see §9)
3. Call `compute_event_result(_stashed_context, _hands, _locked_scores, _busted)` → emit `event_complete`

### 8.5 `compute_next_rank(rng)` static

```gdscript
static func compute_next_rank(rng: RandomNumberGenerator) -> int:
    # Ranks 2-10 + Ace (value 11, lowered to 1 by score recompute if busts).
    # Uniform distribution over {2,3,4,5,6,7,8,9,10,11}.
    # Tens are slightly weighted (10 has only 1 face in the deck normally,
    # but for infinite-deck simplicity we treat all 10 ranks equally weighted).
    return 2 + int(rng.randf() * 10)  # returns 2-11 inclusive
```

Note: rank 11 in the result is the Ace; UI renders it as "A". `compute_score` rule: sum all ranks; if total > 21 and any Ace was counted as 11, drop one Ace's value from 11 to 1; repeat until ≤ 21 or no more Aces convertible.

### 8.6 `compute_score(hand) -> int` static

```gdscript
static func compute_score(hand: Array) -> int:
    var total = 0
    var aces = 0
    for rank in hand:
        if rank == 11:
            aces += 1
        total += rank
    while total > 21 and aces > 0:
        total -= 10  # Convert one Ace from 11 to 1
        aces -= 1
    return total
```

### 8.7 `compute_event_result(context, hands, locked_scores, busted) -> EventResult` static

```gdscript
static func compute_event_result(context, hands: Dictionary, locked_scores: Dictionary, busted: Dictionary) -> RefCounted:
    var result = EventResult.new()
    result.event_id = "card_cannon"
    var summary: Array = []
    var winner_peer_id = 0
    var winner_score = 0
    var winner_seat = INF
    var modifiers = {}
    if context != null and "event_modifiers" in context:
        modifiers = context.event_modifiers
    for player in context.players:
        var pid = player.peer_id
        var wager = int(context.wagers.get(pid, 0))
        var p_mods = modifiers.get(pid, {})
        if busted.get(pid, false):
            var bust_loss = wager
            if p_mods.get("insurance_pre", false):
                bust_loss = int(wager / 2)
            result.per_player[pid] = {
                "chip_delta": -bust_loss, "crown_delta": 0, "heat_delta": 0,
                "bust": true, "cash_out_at": 0.0,
            }
            summary.append({
                "peer_id": pid, "name": player.name, "score": compute_score(hands.get(pid, [])),
                "locked_score": 0, "chip_delta": -bust_loss, "busted": true, "wager": wager,
            })
        else:
            var locked = int(locked_scores.get(pid, 0))
            var band_mult = _band_multiplier(locked)
            var chip_delta = int(wager * band_mult)
            var wm = float(p_mods.get("wager_multiplier", 1.0))
            if wm != 1.0:
                chip_delta = int(chip_delta * wm)
            var um = float(p_mods.get("underdog_multiplier", 1.0))
            if um != 1.0:
                chip_delta = int(chip_delta * um)
            result.per_player[pid] = {
                "chip_delta": chip_delta, "crown_delta": 0, "heat_delta": 0,
                "bust": false, "cash_out_at": 0.0,
            }
            summary.append({
                "peer_id": pid, "name": player.name, "score": locked,
                "locked_score": locked, "chip_delta": chip_delta, "busted": false, "wager": wager,
            })
            # Track winner: highest locked score; tie-break by lowest seat_index
            if locked > winner_score or (locked == winner_score and player.seat_index < winner_seat):
                winner_score = locked
                winner_peer_id = pid
                winner_seat = player.seat_index
    if winner_peer_id != 0 and winner_score > 0:
        result.per_player[winner_peer_id]["crown_delta"] = 1
        var winner_mods = modifiers.get(winner_peer_id, {})
        var heat_delta = 1
        if winner_mods.get("heat_shield", false):
            heat_delta = int(heat_delta / 2)
        result.per_player[winner_peer_id]["heat_delta"] = heat_delta
    result.painful_reveal = {
        "winner_peer_id": winner_peer_id,
        "winner_score": winner_score,
        "scores_summary": summary,
    }
    return result

static func _band_multiplier(score: int) -> float:
    if score == 21:
        return MatchConfig.CARD_CANNON_PAYOUT_BAND_PERFECT  # 3.0
    if score >= 19:
        return MatchConfig.CARD_CANNON_PAYOUT_BAND_HEAVY    # 2.0
    if score >= 16:
        return MatchConfig.CARD_CANNON_PAYOUT_BAND_STRONG   # 1.5
    if score >= 11:
        return MatchConfig.CARD_CANNON_PAYOUT_BAND_MEDIUM   # 1.0
    return MatchConfig.CARD_CANNON_PAYOUT_BAND_LOW          # 0.5
```

### 8.8 Crown rule

Highest non-bust `locked_score`. Ties broken by lowest `seat_index` (deterministic). Crown unawarded if all bust or all locked at 0.

## 9. Error Handling

### 9.1 Bomb Pot

| Trigger | Behavior |
|---|---|
| Pull-out outside MAIN_EVENT | Host silent reject (`_start_time_ms == 0` guard) |
| Pull-out after `_finished` | Host silent reject |
| Double-tap pull-out | Host silent drop (`peer_id in _pulled_out_peers`) |
| Player disconnect mid-event | `NetSessionState.PAUSED` machinery freezes `_process` (set_process(false) when paused, true on resume). On 30s pause expiry, disconnected peer treated as still-grabbing → bust on detonation |
| Bomb fires with zero pull-outs | All bust. `_locked_shares = {}`. No Crown. No Heat. |
| All peers pulled out before bomb | `_finish()` called early; bomb_at_sec never reached |
| Pause during `_process` | `set_process(false)` halts elapsed_ms accumulation; bomb timer effectively pauses (correct) |

### 9.2 Card Cannon

| Trigger | Behavior |
|---|---|
| Draw outside MAIN_EVENT | Host silent reject |
| Draw after locked/busted | Host silent reject |
| Lock with score=0 (immediate lock, no draws) | Allowed; band 1-10 = wager × 0.5 |
| Player disconnect mid-event | Pause machinery same as Bomb Pot. On 30s expiry, host synthesizes `_rpc_lock_requested` for the disconnected peer at their current score |
| All peers busted | Crown unawarded; RESOLUTION still runs |
| Event timeout (120s watchdog from sub-project #3) | Existing watchdog synthesizes empty result; no event-specific change |
| Multiplier Booster + Underdog Odds stacked | Both multipliers apply sequentially per Rocket Clash precedent (chip_delta × wm × um) |

### 9.3 Cross-system

| Trigger | Behavior |
|---|---|
| Cash-Out Jammer played before Bomb Pot/Card Cannon | Cash-Out Jammer's `cash_out_delay` entry sits in `state.pending_card_effects` (event doesn't implement `set_cash_out_delay`, so `_inject_pending_event_effects` skips it). The entry gets cleared by RESOLUTION's `_apply_card_effects_to_result` along with the rest. No bug. |
| Emergency Eject loaded before Bomb Pot/Card Cannon | `state.event_modifiers[peer_id]["auto_eject_loaded"]` set; neither event reads this key. No effect. |
| Late Cash loaded before Bomb Pot/Card Cannon | `late_cash_bonus` flag set; neither event reads it. No effect. |

## 10. Testing

### 10.1 Tier 1 — Per-event pure-math GUT

`tests/unit/test_bomb_pot_event.gd`:
- `test_compute_bomb_at_distribution_within_window` — 1000 samples, all within [5.0, 25.0]
- `test_compute_bomb_at_deterministic_with_same_seed`
- `test_compute_bomb_at_instabust_probability` — sample 1000, count == 5.0; verify ~5% (allow 3-7% range)
- `test_compute_event_result_pulled_out_survivor`
- `test_compute_event_result_busted_grabber`
- `test_compute_event_result_crown_to_last_puller`
- `test_compute_event_result_insurance_halves_bust_penalty`
- `test_compute_event_result_wager_multiplier_boosts_survivor`
- `test_compute_event_result_heat_shield_halves_winner_heat`
- `test_compute_event_result_no_survivor_no_crown`

`tests/unit/test_card_cannon_event.gd`:
- `test_compute_next_rank_distribution` — sample 10000, verify ranks 2-11 inclusive
- `test_compute_next_rank_deterministic_with_same_seed`
- `test_compute_score_basic`
- `test_compute_score_ace_high`
- `test_compute_score_ace_low_to_avoid_bust`
- `test_compute_score_multiple_aces`
- `test_compute_event_result_score_band_payouts` — 5 sub-cases, one per band
- `test_compute_event_result_perfect_21_triple_payout`
- `test_compute_event_result_busted_player_loses_wager`
- `test_compute_event_result_crown_to_highest_locked_score`
- `test_compute_event_result_crown_tie_breaks_by_seat_index`
- `test_compute_event_result_insurance_halves_bust_penalty`
- `test_compute_event_result_underdog_odds_boosts_survivor`

### 10.2 Tier 2 — Controller integration GUT

`tests/unit/test_match_controller_bomb_pot_pull_out.gd`:
- `test_pull_out_during_main_event_locks_share`
- `test_pull_out_outside_main_event_rejected`
- `test_double_pull_out_silently_dropped`

`tests/unit/test_match_controller_card_cannon_draw.gd`:
- `test_draw_during_main_event_updates_score`
- `test_lock_during_main_event_freezes_score`
- `test_draw_after_lock_rejected`
- `test_draw_after_bust_rejected`

### 10.3 Tier 3 — Integration test (PENDING placeholder per sub-project #3/#4 precedent)

`tests/integration/test_three_event_rotation.gd` — host + joiner; run a 3-event Quick Clash; verify all three event_id values appear in the painful_reveal stream across the match; PENDINGs without signaling server.

### 10.4 Cumulative target

- **Baseline:** 453 unit + 4 integration
- **After sub-project #5:** ~475 unit + 5 integration (~22 new unit, 1 new integration)

## 11. Open Questions / Future Work

- Bomb Pot tuning: `POT_GROWTH_PER_SEC = 50.0` and bomb window 5-25s are first-pass. Adjust after playtest.
- Card Cannon `target_score = 21` could be tuned (e.g. 25 for more swing). Constant in `MatchConfig`; House Twists in #6 can override per round.
- Bomb Pot "all peers pulled out early" Crown: currently goes to the **last** puller. Alternative: rotate by seat. MVP keeps last-puller for determinism.
- Bomb Pot danger band UI hints (§11.5: cold/warm/critical): not in MVP. Polish item.
- Face cards for Card Cannon: deferred to a future sub-project or polish pass.
- Power-card hooks from design doc §11.7 (Lockout, Blast Suit, Fuse Peek, etc.) and §14.8 (Loaded Deck, Cut the Deck, Safety Valve, Ricochet, etc.) are catalogued but require intra-event sabotage mechanics. Sub-project #6 (House Twists) and #7 (Polish) are the natural homes.

## 12. Contract Summary for Downstream Sub-Projects

**For sub-project #6 (House Twists):**
- Both events read tunable values (`BOMB_POT_POT_GROWTH_PER_SEC`, `CARD_CANNON_TARGET_SCORE`, etc.) from `MatchConfig`. To enable per-round House Twists, refactor `compute_event_result` to accept an optional `tuning` parameter that overrides defaults. Suggested: pass `state.house_twist` dict into `EventContext` and have events read from it.
- Smart event-pool selection (no-repeat, weighted, rotation) belongs to #6.

**For sub-project #7 (Polish):**
- Both events emit complete `painful_reveal` dicts:
  - Bomb Pot: `{bomb_at_sec, winner_peer_id, winner_pull_out_ms, pulls_summary}`
  - Card Cannon: `{winner_peer_id, winner_score, scores_summary}`
- Animations, audio (Bomb Pot ticking, Card Cannon card-flip), and HUD juice consume these payloads.

**Contract that does NOT change:**
- `EventNode` base contract.
- `EventContext.event_modifiers` shape and existing 10 universal cards' semantics.
- `CardEffectDispatcher.apply` dispatch table.
- `_apply_card_effects_to_result` post-event mutation pipeline (consumes only `wager_tax` and `heat_delta` entries; leftover `cash_out_delay` entries get cleared anyway).
- `BountyResolver.auto_place` and `resolve` (event-agnostic).
- RESOLUTION pipeline substep ordering.
- `MatchController._inject_pending_event_effects` type-guard on `set_cash_out_delay`.

Sub-projects #6+ may ADD:
- New `EventContext` fields (with backward-compat defaults).
- New `_apply_card_effects_to_result` branches (new effect types).
- New events extending `EventNode`.
