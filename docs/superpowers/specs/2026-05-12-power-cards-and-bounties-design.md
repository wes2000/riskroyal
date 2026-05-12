# Power Cards & Bounties — Design Spec

**Project:** Risk Royal (Godot 4.6)
**Sub-project:** #4 of ~7 — Power Cards & Bounties
**Date:** 2026-05-12
**Status:** Approved for planning

---

## 1. Context

Sub-projects #1-3 delivered: networking + lobby (tags: `subproject-1-complete`), a 9-phase match engine + scheduler + HUD + RPC layer (`subproject-2-complete`), and the first real EventNode — Rocket Clash — with cash-out RPC pipeline and BET_LOADOUT phase upgrade (`subproject-3-complete`). The MVP can run a 5-event Quick Clash with real cash-out mechanics and consistent two-peer state, but every event is mechanically identical: ante → wager → cash-out → resolve. The match has no social-pressure lever beyond the chip economy.

This sub-project introduces the two design pillars that make Risk Royal a *party battle* rather than a co-located gambling app: **power cards** (the table-talk layer) and **bounties** (the social-permission layer). Cards let players sabotage, defend, gamble harder, or steal from rivals. Bounties create automatic targets — the chip leader and the highest-Heat player are public enemies every round, with rewards that scale by Heat per design doc §6.5.

After this lands, the MVP has the full set of cross-player mechanics the design doc calls "table talk." Sub-projects #5 (Bomb Pot, Card Cannon), #6 (House Twists), and #7 (polish) all layer on this foundation without restructuring it.

**Position in the MVP decomposition:**
1. ✅ Networking & Lobby Foundation
2. ✅ Match Loop & Economy Core
3. ✅ Rocket Clash
4. ← **this spec**
5. Bomb Pot + Card Cannon
6. House Twists
7. Polish pass

## 2. Goals

- Players hold a hand of up to 5 power cards and equip a per-event loadout of up to 2 active slots, with cards persisting across events in a single match.
- 12 cards ship across 4 categories (Sabotage / Defense / Greed / Social-Comeback), each with a single well-defined effect that integrates with the existing Rocket Clash event.
- Two card timing windows: **BET_LOADOUT** (pre-event modifiers, defense prep, bounty placement, peek) and **CASH_OUT** (Cash-Out Jammer, Emergency Eject — reactive defense + sabotage during the rocket).
- Auto-placed Leader + Heat bounties at the start of each event (skipped at event 0). Bounty reward scales by target's Heat per design §6.5 (+25% at 3-5, +50% at 6-8, +100% at 9-10).
- Manual bounty placement via the Place Bounty card (no chip-buy UI in MVP).
- Bounty resolution in the existing BOUNTY_HEAT_UPDATE phase, after heat application, before SHOP.
- A real SHOP phase replacing sub-project #2's no-op pass-through: 3 cards offered per round, players buy at most 1 each, chip cost per rarity (common 50, rare 150, royal 400 — though MVP cards are all common/rare).
- Starter pack: each player begins the match with 3 random common cards excluding Sabotage (keeps event 1 calm).
- The Rocket Clash event-level RPC pipeline gains card-effect interception points (cash-out delay for Jammer, auto-cash-out for Emergency Eject). All other cards apply through `EventContext.event_modifiers` (a new field) and `EventResult` post-processing.
- The sub-project #2 / #3 contracts (NetSession, EventNode, MatchController public surface) require **no breaking changes** — sub-project #4 is purely additive plus one MatchController refactor task at end of Plan B.

## 3. Non-Goals

- **No combat / Reputation / Damage / HP systems.** Design doc §5.4 lists Reputation as a comeback resource and §6.3 lists a damage table. Neither is on the 7-sub-project list. MVP cards specifically avoid damage-dependent effects. Future sub-project work.
- **No Debt / black-market cards.** Design doc §5.5 (Debt) and §7.2 (Black Market rarity tier). Both depend on a comeback resource MVP doesn't have.
- **No Revenge / House / Event bounty types.** Design doc §6.4 lists 6 bounty types. MVP ships 3 (Leader auto, Heat auto, Place Bounty card).
- **No bounty condition variety.** MVP bounty condition is `"bust"` only. Design doc lists "beat target's cash_out", "hit for 20+ damage", "outlast", etc. Add to `Bounty.satisfies` switch in a future sub-project.
- **No card rarity weighting in SHOP.** Every card has equal probability in the offer shuffle. Rarity affects chip cost only.
- **No card discard UI.** Hand full = can't buy. UX gap; revisit in polish.
- **No card animations, sound, hover tooltips, drag-and-drop.** All polish-sub-project items.
- **No card-vs-card detection (Bodyguard mechanics).** The MVP card library was specifically chosen to avoid sabotage-detection complexity.
- **No card persistence across matches.** Cards are discarded at MATCH_END.

## 4. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope envelope | Full MVP, single sub-project (split into Plan A + Plan B) | Cards and bounties are intertwined design-wise; splitting them ships an interim state where one is functional without the other. Two plans keeps each tractable while delivering a coherent feature set. |
| Card representation | Registry of pure functions | Static `CARDS` dict + one `apply(ctx, target, params)` function per card in `scripts/cards/effects/<card_id>.gd`. Mirrors the static-formatter TDD pattern that worked in sub-projects #2-3. No class hierarchy. New cards in sub-project #5+ just append. |
| Card acquisition | Starter pack (3 commons, no Sabotage) + SHOP buy-from-offer (3 offered, 1 buy max per visit) | Balances event 1 calmness (no sabotage early) with SHOP-driven progression. Each player ends the 5-event match with ~4-6 cards. |
| Bounty types | Leader auto + Heat auto + Place Bounty card | Three placement origins, one condition (`bust`). Place Bounty card replaces the chip-buy UI (one less surface). Heat-bounty value scales per design §6.5. |
| Card timing windows | BET_LOADOUT + CASH_OUT | Two windows cover all 12 MVP cards. Skip Resolution and Shop windows — no MVP card needs them. Sub-project #5 may add a third (mid_event for Bomb Pot). |
| Card library | Adapted 12-card MVP (3 Sabotage / 3 Defense / 3 Greed / 3 Social-Comeback) | Replace design doc's combat-dependent cards (Shove, Misfire, Bodyguard) with Heat/economy/bounty equivalents (Heat Spike, Wager Tax, Heat Shield). Every card has a well-defined effect on Rocket Clash. |
| Effect application pattern | Static effect returns `{type, applied, ...params}` dict; MatchController switches on `type` to mutate state | Keeps effects pure and unit-testable. State mutation lives in one place (`_apply_effect_result`). |
| Card play validation | Host-authoritative, mirroring sub-project #2/#3 RPC pattern | Client UI prevents invalid plays via `is_card_playable` formatter; host validates again on `_rpc_card_play_requested` and silently rejects or sends `_rpc_card_play_rejected` with a reason. |
| MatchController growth | Refactor task in Plan B Phase 4 (extract collaborators) | After sub-project #4 lands, MatchController will be ~950 lines without cleanup. Plan B's final phase extracts `MatchRpcRouter`, `BountyResolver`, `ShopController`, and `CardEffectDispatcher` into separate files. |

## 5. Architecture

Three layers building on existing sub-project #2-3 infrastructure.

### 5.1 Card data layer

`CardRegistry` (`scripts/cards/card_registry.gd`) is script-only, no state, no scene. Const `CARDS: Dictionary` keyed by `card_id` (e.g. `"cash_out_jammer"`). Each entry has `name`, `rarity`, `category`, `timing`, `target_required: bool`, `cost_chips`, `description`, `effect: Callable` preloaded from `scripts/cards/effects/<card_id>.gd`.

Each effect file exposes a single `static apply(context, target_peer_id, params) -> Dictionary` function returning an `EffectResult` dict:
```gdscript
{"type": String, "applied": bool, ...effect_specific_fields}
```

`MatchController._apply_effect_result(effect_result, peer_id)` switches on `type` and mutates state:
- `"insurance_pre"` → `state.event_modifiers[peer_id]["insurance_pre"] = true`
- `"heat_shield"` → `state.event_modifiers[peer_id]["heat_shield"] = true`
- `"wager_multiplier"` → `state.event_modifiers[peer_id]["wager_multiplier"] = 1.25`
- `"double_or_nothing"` → mutates `state.pending_wagers[peer_id] = min(wager * 2, player.chips)`; flags doubled
- `"late_cash_bonus"` → `state.event_modifiers[peer_id]["late_cash_bonus"] = true`
- `"underdog_multiplier"` → `state.event_modifiers[peer_id]["underdog_multiplier"] = 1.5`
- `"cash_out_delay"` → host populates `_pending_cash_out_delays[target] = delay_ms` on the active event
- `"emergency_eject"` → loadout-only flag; rocket event reads from player.loadout in `_process`
- `"heat_delta"` → queues post-event mutation: `result.per_player[target].heat_delta += delta`
- `"wager_tax"` → queues post-event redirect from target to source
- `"bounty_placement"` → appends to `state.bounties`
- `"copycat_wager"` → snapshots `state.pending_wagers[target]` and sets caller's wager equal

### 5.2 State layer

`MatchPlayer` (sub-project #2) grows three fields:
- `hand: Array = []` — card_ids the player owns (max 5)
- `loadout: Array = []` — subset of hand, max 2, the cards active this event
- `played_this_event: Array = []` — card_ids already played this event (cleared at next HOUSE_REVEAL)

`MatchState` (sub-project #2) grows:
- `bounties: Array = []` — array of Bounty refcounted instances (round-tripped as dicts)
- `current_shop_offer: Array = []` — card_ids in the active SHOP offer (cleared on shop_closed)
- `shop_done_peers: Array = []` — peer_ids who have finalized this SHOP visit
- `event_modifiers: Dictionary = {}` — per-peer-id dict of pre-event card flags; cleared at next HOUSE_REVEAL
- `pending_card_effects: Array = []` — array of `{type, source, target, ...}` for post-event mutations (Wager Tax, Heat Spike); cleared after RESOLUTION

`Bounty` (`scripts/match/bounty.gd`, RefCounted data class):
- `origin: String` — "leader" | "heat" | "placed"
- `target: int` — peer_id
- `condition: String` — "bust" (only condition in MVP)
- `reward_chips: int` — base reward (pre-multiplier for Place Bounty; final for auto)
- `placed_by: int` — peer_id of placer (0 for auto)
- `placed_at_event: int` — event_index at placement
- `placed_at_target_heat: int` — captured at placement for Heat-bounty scaling (prevents Heat Shield from suppressing bounty rewards)

Plus statics: `satisfies(bounty, result, claimant_peer_id) -> bool`, `compute_reward(bounty) -> int` (uses `placed_at_target_heat` × heat_multiplier).

### 5.3 RPC + control layer

`MatchController` gains four new RPC pairs:

```
Card play:
  submit_card_play(card_id, target, params)
  @rpc("any_peer", "call_local", "reliable") _rpc_card_play_requested(peer_id, card_id, target, params)
    Host validates: card ∈ player.loadout, ∉ player.played_this_event, timing matches phase, target valid
    Host: effect = CardRegistry.apply_card(card_id, ctx, target, params)
    Host: _apply_effect_result(effect, peer_id)
    Host: player.played_this_event.append(card_id)
    Host: rpc _rpc_card_effect_applied(peer_id, card_id, effect_result_dict)
    Host (on reject): rpc_id(peer_id, _rpc_card_play_rejected, card_id, reason)
  @rpc("authority", "call_remote", "reliable") _rpc_card_effect_applied(peer_id, card_id, effect)
    Clients mirror state via the same _apply_effect_result switch.

Loadout management:
  submit_loadout_change(loadout: Array)
  @rpc("any_peer", "call_local", "reliable") _rpc_loadout_set(peer_id, loadout)
    Host validates: loadout ⊆ player.hand, size ≤ MAX_LOADOUT_SIZE
    Host: player.loadout = clamped value
    Host: rpc _rpc_loadout_acknowledged(peer_id, loadout)

Shop:
  submit_shop_buy(card_id) + submit_shop_done()
  @rpc("any_peer", "call_local", "reliable") _rpc_shop_buy_requested(peer_id, card_id)
  @rpc("any_peer", "call_local", "reliable") _rpc_shop_done(peer_id)
  @rpc("authority", "call_remote", "reliable") _rpc_shop_purchase_confirmed(peer_id, card_id, cost)
  @rpc("authority", "call_remote", "reliable") _rpc_shop_opened(offered: Array)
  @rpc("authority", "call_remote", "reliable") _rpc_shop_closed

Bounty broadcasts:
  @rpc("authority", "call_remote", "reliable") _rpc_bounties_placed(serialized_bounties: Array)
  @rpc("authority", "call_remote", "reliable") _rpc_bounty_claimed(claimant_peer_id, bounty_dict, reward_chips)
  @rpc("authority", "call_remote", "reliable") _rpc_bounty_unclaimed(bounty_dict)
```

Plus new local signals: `bounty_placed(bounty_dict)`, `bounty_claimed(claimant, bounty_dict, reward)`, `bounty_unclaimed(bounty_dict)`, `shop_opened(offered)`, `shop_closed`, `card_effect_applied(peer_id, card_id, effect)`, `loadout_acknowledged(peer_id, loadout)`.

### 5.4 Bounty resolution layer

Auto-placement happens at HOUSE_REVEAL of events 2-5 (event 0 is skipped because no rankings exist yet). `_auto_place_bounties()` computes the chip leader and Heat leader (tiebreakers: earliest seat_index wins), appends two `Bounty` instances to `state.bounties`, captures each target's heat in `placed_at_target_heat`, and broadcasts.

Resolution extends the existing `_process_bounty_heat_update` (which currently just applies heat deltas). After heat application:
```
for bounty in state.bounties:
  claimants = [p.peer_id for p in state.players
               if Bounty.satisfies(bounty, state.current_result, p.peer_id)]
  if claimants.empty():
    rpc _rpc_bounty_unclaimed(bounty.to_dict())
  elif claimants.size() == 1:
    reward = Bounty.compute_reward(bounty)
    state.find_player(claimants[0]).chips += reward
    rpc _rpc_bounty_claimed(claimants[0], bounty.to_dict(), reward)
  else:
    split = reward // claimants.size()
    for c in claimants:
      state.find_player(c).chips += split
      rpc _rpc_bounty_claimed(c, bounty.to_dict(), split)
state.bounties = []
```

`Bounty.satisfies(bounty, result, claimant_id)`:
- claimant ≠ target
- claimant did not bust themselves (`result.per_player[claimant].bust == false`)
- condition holds: for `"bust"`, `result.per_player[target].bust == true`

### 5.5 Rocket Clash event hooks (Plan B)

Plan A's 6 cards (Insurance, Heat Shield, Multiplier Booster, Double or Nothing, Late Cash, Underdog Odds) all apply pre-event modifiers to `state.event_modifiers`. `RocketClashEvent.compute_event_result` accepts a 5th argument `event_modifiers: Dictionary` and applies per-player flags during chip_delta computation. No event-runtime changes needed for these.

Plan B's 4 reactive cards need event-level integration:
- **Cash-Out Jammer**: `_pending_cash_out_delays: Dictionary` field on RocketClashEvent. Populated by MatchController before `_run`. `_rpc_cash_out_requested` host handler checks the dict; if present, `await get_tree().create_timer(delay).timeout`, consume the entry, re-evaluate the current multiplier against the snapshot with a relaxed tolerance (CASH_OUT_TOLERANCE × 5 = 0.25).
- **Emergency Eject**: per-frame check in `_process(delta)` (host-only):
  ```
  for player in state.players:
    if player.is_active_this_event AND
       "emergency_eject" in player.loadout AND
       "emergency_eject" not in player.played_this_event AND
       not _cash_outs.has(player.peer_id) AND
       current_mult >= 3.0 AND current_mult < _crash_at:
         _cash_outs[player.peer_id] = current_mult
         player.played_this_event.append("emergency_eject")
         rpc _rpc_card_effect_applied(player.peer_id, "emergency_eject", {auto_eject_at: current_mult})
  ```
- **Heat Spike + Wager Tax**: post-event, applied to `EventResult.per_player` before chip_changes broadcast. MatchController extends `_apply_and_emit` (sub-project #2 RESOLUTION pipeline) with `_apply_card_effects_to_result(result)` that walks `state.pending_card_effects` and mutates result deltas.
- **Place Bounty**: pure state mutation in MatchController's `_apply_effect_result`. Appends to `state.bounties`.
- **Copycat Bet**: snapshots `state.pending_wagers[target]` at apply time and sets caller's `state.pending_wagers[caller] = snapshot`. Broadcasts `_rpc_wager_acknowledged` for both.

## 6. Components

### 6.1 `scripts/cards/card_registry.gd` (NEW)

Static-only script. Holds the 12-card library + utility statics:
```gdscript
const CARDS: Dictionary = {
    "insurance": {
        name = "Insurance", rarity = "common", category = "defense",
        timing = "bet_loadout", target_required = false,
        cost_chips = 50,
        description = "If you bust, recover 50% of your wager.",
        effect = preload("res://scripts/cards/effects/insurance.gd").apply,
    },
    "heat_shield": { ... },  # similar shape
    ...12 total
}

static func get_card(card_id: String) -> Dictionary
static func apply_card(card_id, context, target, params) -> Dictionary
static func starter_pool() -> Array  # commons excluding sabotage
static func shop_pool() -> Array  # all 12
static func heat_multiplier(heat: int) -> float
    # 0-2: 1.0, 3-5: 1.25, 6-8: 1.5, 9-10: 2.0
```

### 6.2 `scripts/cards/effects/*.gd` (NEW, 12 files)

One file per card. Each has a single `static apply(context, target_peer_id, params) -> Dictionary`. Pure functions, no state. Files:
- `insurance.gd`, `heat_shield.gd`, `multiplier_booster.gd`, `double_or_nothing.gd`, `late_cash.gd`, `underdog_odds.gd` (Plan A — 6 bet_loadout cards)
- `cash_out_jammer.gd`, `emergency_eject.gd`, `heat_spike.gd`, `wager_tax.gd`, `place_bounty.gd`, `copycat_bet.gd` (Plan B — 6 more)

### 6.3 `scripts/match/bounty.gd` (NEW)

RefCounted data class. Fields as in §5.2. Statics: `satisfies(bounty, result, claimant_id) -> bool`, `compute_reward(bounty) -> int`, `to_dict() / from_dict(d)`.

### 6.4 `scripts/match/match_player.gd` (MODIFY)

Add `hand`, `loadout`, `played_this_event` fields with round-trip.

### 6.5 `scripts/match/match_state.gd` (MODIFY)

Add `bounties`, `current_shop_offer`, `shop_done_peers`, `event_modifiers`, `pending_card_effects` fields with round-trip.

### 6.6 `scripts/match/match_config.gd` (MODIFY)

Append:
```
const SHOP_TIMEOUT_SEC: int = 10
const MAX_HAND_SIZE: int = 5
const MAX_LOADOUT_SIZE: int = 2
const STARTER_PACK_SIZE: int = 3
const SHOP_OFFER_SIZE: int = 3
const CARD_COST_COMMON: int = 50
const CARD_COST_RARE: int = 150
const CARD_COST_ROYAL: int = 400  # no royals in MVP but reserved
const BOUNTY_BASE_REWARD: int = 150
```

### 6.7 `scripts/match/match_controller.gd` (MODIFY — biggest change)

Five additions in Plan A:
1. **Card play pipeline:** `submit_card_play`, `_rpc_card_play_requested`, `_rpc_card_effect_applied`, `_rpc_card_play_rejected`. `_apply_effect_result(effect, peer_id)` dispatcher.
2. **Loadout management:** `submit_loadout_change`, `_rpc_loadout_set`, `_rpc_loadout_acknowledged`.
3. **SHOP phase upgrade:** Replaces no-op pass-through. `_process_shop()` async handler with `shop_timeout_sec_override: float = -1.0` test seam.
4. **Bounty auto-placement + resolution:** `_auto_place_bounties()` called from HOUSE_REVEAL handler. Extension to `_process_bounty_heat_update` for resolution.
5. **Pre-event card effect application:** `_apply_loadout_effects_to_context(ctx)` walks each active player's loadout for `bet_loadout`-timing cards and mutates `ctx.event_modifiers`.

Plus in Plan B:
6. **Post-event card effects:** `_apply_card_effects_to_result(result)` runs before the `chip_changes` substep.
7. **MatchController refactor task** (Plan B Phase 4): extract `MatchRpcRouter` (RPC sender + receiver helpers), `BountyResolver` (auto-placement + resolution), `ShopController` (SHOP phase async handler), `CardEffectDispatcher` (`_apply_effect_result` switch) into collaborator files. Each ~150-200 lines. MatchController retains the phase machine + signal coordination only.

### 6.8 `scripts/events/event_context.gd` (MODIFY)

Add `event_modifiers: Dictionary = {}` field. Round-trip. Holds `{peer_id: {flag_name: value, ...}}`.

### 6.9 `scripts/events/rocket_clash/rocket_clash_event.gd` (MODIFY — Plan B)

Two additions:
1. `_pending_cash_out_delays: Dictionary` field. `_rpc_cash_out_requested` consumes delays.
2. Emergency Eject per-frame check in `_process(delta)`.

Plus `compute_event_result` extended with a 5th argument `event_modifiers` and per-player flag application.

### 6.10 `scripts/ui/loadout_overlay.gd` + `.tscn` (NEW)

Shown during BET_LOADOUT alongside BetLoadoutOverlay. Renders:
- Hand row (up to 5 CardSlotButton widgets)
- Loadout row (2 active slots)
- Target picker overlay (for `target_required` cards)

Static formatters:
- `format_card_label(card_id) -> String`
- `is_card_playable(card_id, phase, played_this_event_set) -> bool`
- `available_targets(local_peer_id, players, card_meta) -> Array`

### 6.11 `scripts/ui/cash_out_card_drawer.gd` + `.tscn` (NEW — Plan B)

Lives inside RocketClashEvent's scene (or beneath the multiplier display). Filters local loadout to `cash_out`-timing cards. Same CardSlotButton widget as LoadoutOverlay.

### 6.12 `scripts/ui/shop_overlay.gd` + `.tscn` (NEW)

Shown during SHOP phase. Renders 3 offered cards (name, description, price), Buy button per card (disabled if can't afford or hand full), Done button.

Static formatters:
- `format_shop_offer(offered_card_ids) -> Array[Dictionary]`
- `can_afford(chips, cost) -> bool`

### 6.13 `scripts/ui/bounty_panel.gd` + `.tscn` (NEW)

Shown alongside PlayerPanels in MatchScene. Renders active `state.bounties` as rows.

Static formatter: `format_bounty_summary(bounty_dict, target_player) -> String`.

### 6.14 `scripts/ui/match_scene.gd` + `match_scene.tscn` (MODIFY)

Add `LoadoutSlot` (between EventSlot and ResolutionSlot), `ShopSlot` (sibling), `BountyPanel` (top header). Wire new signals: `shop_opened`, `shop_closed`, `bounty_placed`, `bounty_claimed`.

## 7. Data Flow

### 7.1 Match start (Plan A — starter pack)

```
Host start_match(match_start):
  Existing: build state.players from seats, init chips, seed RNG, → HOUSE_REVEAL
  NEW: for each player p:
    starter = host.rng.shuffle(CardRegistry.starter_pool())[:STARTER_PACK_SIZE]
    p.hand = starter
    p.loadout = []
    p.played_this_event = []
  rpc _rpc_starter_pack_dealt(serialized_hands)

All peers: mirror hands; LoadoutOverlay shows local hand at first BET_LOADOUT.
```

### 7.2 HOUSE_REVEAL (Plan A — bounty auto-placement)

```
Host _enter_phase_behavior(HOUSE_REVEAL):
  if state.event_index > 0:
    leader_id, heat_id = compute via state.players
    state.bounties = [Bounty(leader), Bounty(heat with scaling)]
    rpc _rpc_bounties_placed(serialized_bounties)
  for p in state.players: p.played_this_event = []
  state.event_modifiers = {}
  state.pending_card_effects = []
```

### 7.3 BET_LOADOUT (Plan A — wager + card play + loadout)

```
Host enters BET_LOADOUT:
  Existing: emit bet_loadout_started, 15s timer
  NEW: LoadoutOverlay shows hand + loadout slots

Local interactions (any peer):
  Set wager: submit_wager → existing pipeline
  Change loadout: submit_loadout_change → _rpc_loadout_set
                  Host validates, broadcasts acknowledged
  Play card: submit_card_play(card_id, target_peer_id)
             → _rpc_card_play_requested
             Host validates, applies effect, broadcasts _rpc_card_effect_applied
             OR sends _rpc_card_play_rejected to originator

Phase advance: all active ready OR timer expires
  → _build_event_context populates ctx.event_modifiers from state
  → _apply_loadout_effects_to_context(ctx) (any cards equipped but not played
    that have passive effects can apply here in future; MVP has no passives)
  → MAIN_EVENT
```

### 7.4 MAIN_EVENT (Plan B — Rocket Clash with card hooks)

```
Host: existing _process_main_event instantiates RocketClashEvent and calls _run.
NEW: ctx.event_modifiers passed via context.
NEW: any Cash-Out Jammer effects from BET_LOADOUT populate
     event._pending_cash_out_delays = {target_peer_id: delay_ms}

Cash-out:
  Existing: client _rpc_cash_out_requested(peer_id, snapshot)
  Host: existing validation
  NEW: if _pending_cash_out_delays.has(peer_id):
    delay = _pending_cash_out_delays[peer_id]
    _pending_cash_out_delays.erase(peer_id)
    await get_tree().create_timer(delay / 1000.0).timeout
    Re-evaluate host_mult; accept if abs(snapshot - host_mult) < CASH_OUT_TOLERANCE * 5
    else reject

Emergency Eject (host-only per-frame in _process):
  for player in active_peers:
    if "emergency_eject" in player.loadout AND ∉ played_this_event AND
       not _cash_outs.has(peer_id) AND
       current_mult >= 3.0 AND current_mult < _crash_at:
      _cash_outs[peer_id] = current_mult
      player.played_this_event.append("emergency_eject")
      rpc _rpc_card_effect_applied(peer_id, "emergency_eject", {auto_eject_at: m})

When crash fires: _finish() calls compute_event_result(ctx, crash_at, _cash_outs, busted, event_modifiers)
  Per-player application:
    if insurance_pre and busted: chip_delta = -int(wager / 2) not -wager
    if wager_multiplier and survived: chip_delta = int(chip_delta * 1.25)
    if heat_shield: heat_delta halved (mirrored into result; applied in BOUNTY_HEAT_UPDATE)
    if underdog_multiplier and survived: chip_delta *= 1.5
    if late_cash_bonus and cash_out_at > 5.0: chip_delta += 200
```

### 7.5 RESOLUTION → BOUNTY_HEAT_UPDATE (Plan A + B)

```
RESOLUTION substep pipeline:
  Existing: busts → cash_outs → chip_changes → crown_awards → painful_reveal
  NEW: before chip_changes, _apply_card_effects_to_result(result):
    for effect in state.pending_card_effects:
      if effect.type == "wager_tax":
        if not result.bust_for(effect.target):
          tax = int(result.per_player[effect.target].chip_delta * 0.20)
          result.per_player[effect.target].chip_delta -= tax
          result.per_player[effect.source].chip_delta += tax
      if effect.type == "heat_delta":
        result.per_player[effect.target].heat_delta += effect.delta
    state.pending_card_effects = []

BOUNTY_HEAT_UPDATE:
  Existing: apply heat_delta from result.per_player; broadcast deltas
  NEW: after heat applied, resolve bounties (see §5.4 pseudocode)
  → schedule advance to SHOP
```

### 7.6 SHOP phase (Plan A — buy-from-offer)

```
Host enters SHOP:
  state.current_shop_offer = host.rng.shuffle(CardRegistry.shop_pool())[:3]
  state.shop_done_peers = []
  rpc _rpc_shop_opened(offered)
  shop_opened.emit(offered)
  Start SHOP_TIMEOUT_SEC timer

Buy: submit_shop_buy(card_id) → _rpc_shop_buy_requested
  Host validates: card_id ∈ current_shop_offer AND peer ∉ shop_done_peers AND
                  chips ≥ cost AND hand.size() < MAX_HAND_SIZE
  Host: player.chips -= cost; player.hand.append(card_id);
        state.shop_done_peers.append(peer_id)
  Host broadcasts _rpc_shop_purchase_confirmed + _rpc_apply_deltas

Done: submit_shop_done → _rpc_shop_done
  Host: state.shop_done_peers.append(peer_id)

Advance: all active ∈ shop_done_peers OR timer fires
  rpc _rpc_shop_closed
  shop_closed.emit()
  state.current_shop_offer = []
  → schedule advance to HOUSE_TWIST
```

## 8. Error Handling

### 8.1 Card play failures

| Trigger | Behavior |
|---|---|
| Card outside timing window | Host silent reject. UI's `is_card_playable` should have grayed out the button. |
| Card not in loadout | Host silent reject. |
| Card already played this event | Host silent reject (idempotent). |
| Target invalid (null when required, busted, self when forbidden) | Host sends `_rpc_card_play_rejected(reason)`; local UI re-enables and toasts. |
| Effect returns `applied: false` | Host does NOT add to played_this_event; player can retry. |
| Conflicting effects on same target | Both apply additively. Documented; revisit if playtest reveals problems. |

### 8.2 Loadout management failures

| Trigger | Behavior |
|---|---|
| Loadout contains card not in hand | Host clamps: drops invalid card_ids; broadcasts the clamped value. |
| Loadout size > MAX | Host truncates. |
| Loadout change outside BET_LOADOUT | Host silent reject. |
| Player disconnects mid-change | Existing PAUSED machinery freezes phase; reconnect resumes. 30s timeout: loadout cleared. |

### 8.3 SHOP failures

| Trigger | Behavior |
|---|---|
| Card not in offer | Host silent reject. |
| Second buy in one visit | Host rejects second. |
| Insufficient chips | Host sends `_rpc_shop_buy_rejected(reason)`. UI toast. |
| Hand at MAX | Host rejects. UI shows "Hand full" (no discard UI in MVP). |
| Disconnect during SHOP | PAUSED machinery; 30s timeout auto-marks done. |
| Timer expires | Phase advances; non-buyers get nothing. |

### 8.4 Bounty resolution failures

| Trigger | Behavior |
|---|---|
| No claimants (target was sole survivor or all busted) | `_rpc_bounty_unclaimed`; no chip movement. |
| Multiple claimants | Equal split; integer division truncates fractional chips. |
| Self-bounty | Allowed; placer can't claim (satisfies excludes target = claimant). |
| Place Bounty + auto-bounty on same target | Both coexist; each resolves independently. |
| Stale bounties from prior event | Defensively cleared in `_auto_place_bounties` and at end of `_process_bounty_heat_update`. |
| Target's heat changed during event | Reward uses `placed_at_target_heat` captured at placement — Heat Shield doesn't suppress bounty reward. |

### 8.5 Disconnect / pause / cross-system

Existing sub-project #2 §8.2 machinery applies. New cases:

| Trigger | Behavior |
|---|---|
| Player with Cash-Out Jammer's delay flag disconnects | Flag stays in `_pending_cash_out_delays`; harmless. |
| Player with Emergency Eject disconnects mid-rocket | Auto-eject still fires (host synthesizes cash_out); chips received on rejoin / final result. |
| Player with active loadout effects disconnects mid-event | Modifiers already in event_modifiers; resolution applies them regardless. |
| Reconnect mid-SHOP | Existing late-RPC catch-up sends shop_opened snapshot; player can buy if not in shop_done_peers. |

### 8.6 Card effect math edge cases

| Trigger | Behavior |
|---|---|
| Wager Tax on busted target | Effect returns `applied: false`; no chip redirect. |
| Multiplier Booster on busted player | No-op (guard: only if not busted). |
| Heat Shield with `heat_delta = 0` | No-op (`int(0/2) = 0`). |
| Heat Shield with negative heat_delta (cooling card) | Halved magnitude; cooling becomes weaker. Acceptable per Heat Shield's defensive theme. |
| Underdog Odds on non-last player | Effect returns `applied: false`. |
| Insurance applied but player survived | Flag set, branch never fires. Harmless. |
| Cash-Out Jammer on non-cashing target | Flag stays in dict; cleared at event end. Harmless. |
| Emergency Eject threshold reached past crash | Won't happen — `_process` gates crash trigger first. Defensive: include `current_mult < _crash_at` in eject condition. |
| Double or Nothing wager × 2 > chips | Capped at chip count via `min(wager * 2, player.chips)`. |

## 9. Testing

### 9.1 Tier 1 — Card effects (per-card pure-math GUT)

12 test files (`test_card_<card_id>.gd`), one per card. Plus `test_card_registry.gd` for registry shape, lookup, heat_multiplier banding, starter_pool exclusion.

Target: ~30 tests across Plan A (15) + Plan B (15).

### 9.2 Tier 2 — Bounty system

- `test_bounty.gd` — `satisfies` cases (target ≠ claimant, no self-bust, condition holds); `compute_reward` per-band scaling.
- `test_match_controller_bounties.gd` — auto-placement at event 1+ (skipped at 0); resolution awards reward_chips; split on tie; clears state.bounties.

Target: ~10 tests Plan A.

### 9.3 Tier 3 — Card play pipeline (controller GUT against FakeMultiplayerNode)

- `test_match_controller_card_play.gd` — timing validation, loadout membership, played_this_event idempotency, target validation, effect-failed retry, multi-card BET_LOADOUT.
- `test_match_controller_loadout.gd` — set valid loadout; clamp invalid ids; truncate over-size; reject outside BET_LOADOUT.

Target: ~12 tests Plan A.

### 9.4 Tier 4 — SHOP phase

- `test_match_controller_shop.gd` — entry offers 3 cards; valid buy; insufficient chips reject; card not in offer reject; hand full reject; double-buy reject; done; all-done fast-advance; timer expiry.

New test seam: `shop_timeout_sec_override: float = -1.0` mirroring established pattern.

Target: ~9 tests Plan A.

### 9.5 Tier 5 — UI widgets (static formatters)

- `test_loadout_overlay.gd` — format_card_label, is_card_playable, available_targets.
- `test_shop_overlay.gd` — format_shop_offer, can_afford.
- `test_bounty_panel.gd` — format_bounty_summary.
- `test_cash_out_card_drawer.gd` (Plan B) — filter loadout by timing.

Target: ~8 tests Plan A (6) + Plan B (2).

### 9.6 Tier 6 — Integration + Rocket Clash card hooks (Plan B)

- `tests/integration/test_rocket_clash_with_cards.gd` — host + joiner with cards in loadouts; play Cash-Out Jammer + Multiplier Booster; both peers see consistent painful_reveal with card-modified deltas.
- `test_rocket_clash_event.gd` extends (Plan B) — direct tests of `_pending_cash_out_delays` consumption + Emergency Eject auto-trigger.

Target: 1 integration + ~4 unit tests Plan B.

### 9.7 Manual playtest additions

8 scenarios to append to `docs/PLAYTEST_CHECKLIST.md`:

| # | Scenario |
|---|----------|
| 1 | Starter pack of 3 commons distributed at match start |
| 2 | SHOP offers 3 cards; player buys 1 |
| 3 | Leader Bounty auto-placed event 2; bust target → claimer collects 150 chips |
| 4 | Heat Bounty scales: 150 × 1.5 at Heat 6 target |
| 5 | Insurance halves bust penalty |
| 6 | Cash-Out Jammer delays target's cash-out 750ms |
| 7 | Emergency Eject auto-triggers at 3.0x |
| 8 | Place Bounty + bust target |

### 9.8 Out of scope for #4's testing

- Real-network latency stress for card RPCs
- Card UI drag-and-drop interactions (MVP is click-to-play)
- Concurrent shop-buy race conditions across 8 peers (host-authoritative single-threaded validation; bounded by Godot's frame loop)

**Cumulative target after sub-project #4 merge:** 292 + 3 (baseline) → ~360 + 4 (~68 new unit + 1 new integration).

## 10. Open Questions / Future Work

- **Card discard UI** — hand-full silently blocks buys. UX gap.
- **Card description tooltips** — full descriptions in CardRegistry but no UI surfacing. Polish.
- **Bounty condition variety** — only `"bust"` ships; "beat cash_out", "outlast", etc. via new branches in `Bounty.satisfies`.
- **Heat-bounty scaling tuning** — playtest may want different multipliers.
- **Card rarity weighting in SHOP** — every card equally probable in MVP. Easy future tweak.

**Future sub-project hooks:**
- **#5 Bomb Pot + Card Cannon** — adds events that consume cards via the existing timing windows + EventContext.event_modifiers. May add a third timing window (`mid_event`).
- **#6 House Twists** — rotates bounty conditions, modifies SHOP costs, restricts card categories. Hooks via EventContext.
- **#7 Polish** — animations, sounds, tooltips, drag-and-drop, painful_reveal that names card plays.

**Bundled with sub-project #4:**
- **Plan B Phase 4: MatchController refactor.** Extract `MatchRpcRouter`, `BountyResolver`, `ShopController`, `CardEffectDispatcher` into collaborator files. MatchController retains the phase machine + signal coordination only. Tackles the size follow-up that sub-projects #2 and #4 both flagged.

**Deferred (NOT bundled):**
- `*.uid` cleanup (separate cleanup pass)
- PlayerPanel.set_player vs set_peer spec drift
- return_to_lobby orchestration split between MatchScene and MatchController
- Sub-project #3's StatusGrid + BetLoadoutOverlay countdown UX gaps

## 11. Contract Summary for Downstream Sub-Projects

Sub-project #5 (Bomb Pot + Card Cannon) consumes the card + bounty contracts this spec defines:

**For new cards:**
- Add an entry to `CardRegistry.CARDS` with a unique `card_id`.
- Write a single `static apply(context, target, params) -> Dictionary` in `scripts/cards/effects/<card_id>.gd`.
- The effect dict's `type` field must be handled by `CardEffectDispatcher._apply_effect_result` (sub-project #4 Plan B extracts this from MatchController). Add a new branch if the effect type is new.
- Decide a timing window from `{"bet_loadout", "cash_out"}` or add a new window with corresponding integration in `_enter_phase_behavior`.
- Add a unit test in `tests/unit/test_card_<card_id>.gd` following the pure-function in/out template.
- Cards do NOT carry state across events except via `state.event_modifiers` or `state.pending_card_effects`.

**For events:**
- Events read `EventContext.event_modifiers` for per-player pre-event flags during their result computation.
- Events may declare additional timing windows by adding a new value to the `timing` field convention and an integration point in their `_process` loop.
- Events MUST NOT mutate `state.bounties` directly — only Place Bounty (or future bounty cards) does that.
- Events SHOULD use the established `_send_rpc` pattern (sub-project #2 → #3) for any event-specific RPCs they introduce.

**For bounties:**
- Add a new `condition` value to `Bounty.satisfies` switch + a unit test branch.
- Bounty placement origins beyond Leader / Heat / Placed (e.g., Revenge, House, Event) extend the `origin` field's enum-like contract — add to MatchController's auto-placement logic for any new origin.
- Bounty rewards always scale via `Bounty.compute_reward` which reads `placed_at_target_heat`.

Sub-projects #5+ should NOT:
- Add card RPCs to MatchController. New cards go through the existing `submit_card_play` → `_rpc_card_play_requested` → `CardEffectDispatcher` pipeline.
- Restructure the SHOP phase. Add new card_ids to `CardRegistry.shop_pool()` to enrich the offer.
- Persist card state across matches.
- Introduce card-vs-card interactions that require detection (sabotage blockers, etc.) without a separate spec for the detection layer.
