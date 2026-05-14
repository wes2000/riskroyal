# Risk Royal Alpha Feel Remediation Design

Date: 2026-05-14  
Status: Design / implementation plan  
Companion docs:

- `docs/RiskRoyal_DesignDoc.md`
- `docs/RiskRoyal_AlphaValidation.md`

## 1. Purpose

This document defines the concrete changes needed to move the current Risk Royal public alpha from "systems prototype" to the intended "battle casino party game" feel described in the main design document.

The current alpha has the right foundation:

- 5-event Quick Clash loop
- Rocket Clash, Bomb Pot, and Card Cannon
- Chips, Crowns, Heat
- Power cards
- Bounties
- Shop
- House Twists
- Announcer / status / painful reveal UI

The problem is not that the design failed to reach code. The problem is that several high-impact details currently blunt the intended emotional arc:

- Busting can remove a player from active play for the rest of the match.
- Two of three MVP events do not pay off their painful reveal moments.
- Heat is too flat to create a "public enemy" arc.
- Bounties reward passive survival more than targeted rivalry.
- Card Cannon works mechanically but does not yet feel like a battle event.
- The build/test gate emits runtime errors that reduce confidence.

This doc focuses on exact implementation changes, expected behavior, file-level targets, test requirements, and manual playtest criteria.

## 2. Desired Feel

The intended Risk Royal feel is:

1. Every round creates public suspense.
2. Players are tempted to be greedy.
3. Busting hurts, but is funny and does not end the player's night.
4. Big wins create Heat, which creates table pressure.
5. Bounties create permission to attack friends.
6. Power cards create readable, social moments.
7. Comebacks require risk, not charity.
8. The House feels like a dramatic host, not just a rules engine.

The remediation work should be judged by whether players say things like:

- "I should have cashed out."
- "You did that to me."
- "I am putting a bounty on you."
- "The leader is way too hot right now."
- "I am broke, but I have one terrible way back."
- "Run it again."

## 3. Priority Summary

### P0: Feel-Breaking Fixes

These should happen before calling the alpha representative of the intended game.

1. Event busts must not create match-long spectator mode.
2. Bomb Pot and Card Cannon need event-specific painful reveal formatting.
3. Runtime test errors need investigation and cleanup.

### P1: Core Feel Improvements

These make the alpha feel like Risk Royal instead of a basic mini-game rotation.

4. Heat must scale with dramatic greed.
5. Bounties need attribution-aware conditions.
6. Card Cannon needs target firing and face-card combat effects.
7. Card plays and House Twists need stronger public feedback.

### P2: Comeback and Public Alpha Depth

These make the alpha more durable across repeated play.

8. Add a simple Debt-lite or comeback loan path.
9. Add black-market style offers for trailing players.
10. Add a Last Chance event-5 modifier or mini-finale variant.

## 4. Current Architecture Reference

### 4.1 Match Flow

Primary file:

- `scripts/match/match_controller.gd`

Relevant methods:

- `_process_ante_phase`
- `_process_event_selection`
- `_process_bet_loadout`
- `_process_main_event`
- `_process_resolution_phase`
- `_process_bounty_heat_update`
- `_process_shop`
- `_process_house_twist`
- `_process_match_end`

Current phase order:

1. `HOUSE_REVEAL`
2. `ANTE`
3. `EVENT_SELECTION`
4. `BET_LOADOUT`
5. `MAIN_EVENT`
6. `RESOLUTION`
7. `BOUNTY_HEAT_UPDATE`
8. `SHOP`
9. `HOUSE_TWIST`
10. repeat or `MATCH_END`

### 4.2 Match Config

Primary file:

- `scripts/match/match_config.gd`

Current MVP constants:

- `QUICK_CLASH_EVENT_COUNT = 5`
- `ANTE_BY_EVENT_INDEX = [25, 25, 25, 50, 100]`
- `EVENT_POOL = [Rocket Clash, Bomb Pot, Card Cannon]`
- `MAX_HAND_SIZE = 5`
- `MAX_LOADOUT_SIZE = 2`
- `SHOP_OFFER_SIZE = 3`
- `BOUNTY_BASE_REWARD = 150`

### 4.3 Player State

Primary file:

- `scripts/match/match_player.gd`

Current player fields:

- `peer_id`
- `seat_index`
- `name`
- `color_index`
- `chips`
- `crowns`
- `heat`
- `is_active_this_event`
- `hand`
- `loadout`
- `played_this_event`

Potential new fields:

- `debt`
- `last_event_busted`
- `comeback_offer_used`
- `event_bust_count`
- `last_sabotaged_by`

### 4.4 Event Result Contract

Primary file:

- `scripts/events/event_result.gd`

Current fields:

- `event_id`
- `per_player`
- `painful_reveal`

Current per-player shape:

```gdscript
{
	"chip_delta": int,
	"crown_delta": int,
	"heat_delta": int,
	"bust": bool,
	"cash_out_at": float,
}
```

Recommended expanded per-player shape:

```gdscript
{
	"chip_delta": int,
	"crown_delta": int,
	"heat_delta": int,
	"bust": bool,
	"cash_out_at": float,
	"score": int,
	"locked_score": int,
	"pull_out_ms": int,
	"risk_tier": String,
	"sabotaged_by": Array[int],
	"finisher_peer_id": int,
}
```

Do not require every event to fill every field. The result should remain a flexible dictionary, but the common vocabulary should be documented and tested.

## 5. Change 1: Event Busts Must Not Cause Match-Long Spectator Mode

### 5.1 Problem

Current behavior:

- `MatchController._build_busts_payload` calls `notify_local_spectator_if_busted(pid)`.
- `MatchScene._on_local_spectator_mode_entered` hides play widgets.
- The comment says reversal is not supported in MVP.

This directly conflicts with the design pillar that losing should be painful but entertaining. A player who busts in event 1 should still be able to wager, buy cards, use bounties, and chase a comeback in event 2.

### 5.2 Desired Behavior

Event busts should:

- Show bust animation.
- Show painful reveal.
- Apply chip loss.
- Remove the player from only the current event's active action.
- Let the player participate in future events if they can pay ante or accept a comeback path.

Event busts should not:

- Hide the player's play widgets for the rest of the match.
- Disable shop forever.
- Disable bet/loadout forever.
- Convert the player into a permanent spectator.

### 5.3 New State Model

Separate these concepts:

- `busted_this_event`: player failed the current event.
- `inactive_this_event`: player cannot act in the current event.
- `spectator_mode`: player is not playing the match.

In the current code, `is_active_this_event` already covers event participation. Do not overload spectator mode.

Recommended additions to `MatchPlayer`:

```gdscript
var busted_this_event: bool = false
var disconnected: bool = false
```

Add both fields to `to_dict()` and `from_dict()`.

### 5.4 Implementation Plan

File: `scripts/match/match_controller.gd`

Change `_build_busts_payload`:

- Keep `player_busted.emit(pid, loss)`.
- Remove or gate `notify_local_spectator_if_busted(pid)`.
- Mark `p.busted_this_event = true` if the field is added.

Do not call `local_player_spectator_mode_entered` for normal event busts.

File: `scripts/ui/match_scene.gd`

Change `_on_local_spectator_mode_entered`:

- Rename or reinterpret as `_on_local_match_spectator_mode_entered`.
- It should only respond to:
  - disconnect/drop
  - future hard-elimination modes
  - explicit spectator join

Add a new temporary event-bust UI state only if needed:

- `show_event_busted_overlay(reason)`
- Hide only event action controls during current `MAIN_EVENT`.
- Restore at next `HOUSE_REVEAL` or `BET_LOADOUT`.

File: `scripts/ui/spectator_overlay.gd`

Change top comment:

- Remove "busted mid-match" from permanent spectator description.
- Keep "dropped" or "hard eliminated."

### 5.5 UI Behavior

If a local player busts during Rocket Clash:

- Cash-out button is disabled for that event.
- Status grid shows `BUSTED`.
- PainfulReveal shows the loss.
- The player can still watch the remaining event.
- At the next event's Bet/Loadout phase, all normal play widgets return.

If a local player disconnects or is truly eliminated:

- SpectatorOverlay appears.
- Play widgets remain hidden.

### 5.6 Tests

Add or update unit tests:

- `test_match_controller_event_bust_not_spectator.gd`
  - Given local player busts in event result.
  - Assert `player_busted` emitted.
  - Assert `local_player_spectator_mode_entered` not emitted.

- `test_match_scene_event_bust_widgets_restore.gd`
  - Simulate temporary event bust.
  - Advance to next `HOUSE_REVEAL` or `BET_LOADOUT`.
  - Assert play widgets visible.

Update existing spectator tests:

- Rename expectations so spectator mode is tied to disconnect/hard elimination, not regular bust.

### 5.7 Playtest Criteria

Scenario:

1. Start 2-player Quick Clash.
2. Player A busts in event 1.
3. Player A sees bust feedback.
4. Event 2 begins.
5. Player A can wager, equip cards, and play normally.

Pass condition:

- Player A says "I am getting revenge next round," not "I am out."

## 6. Change 2: Event-Specific Painful Reveals

### 6.1 Problem

Rocket Clash reveal is formatted. Bomb Pot and Card Cannon generate payloads but fall through to a generic fallback in `ResolutionOverlay`.

Current `ResolutionOverlay.format_resolution_step` only detects:

```gdscript
payload.has("crash_at") and payload.has("cash_outs_summary")
```

Bomb Pot payload includes:

- `bomb_at_sec`
- `winner_peer_id`
- `winner_pull_out_ms`
- `pulls_summary`

Card Cannon payload includes:

- `winner_peer_id`
- `winner_score`
- `scores_summary`

### 6.2 Desired Behavior

Every MVP event should end with a clear regret/comedy reveal:

- Rocket Clash: "Rocket exploded at 4.72x."
- Bomb Pot: "Bomb popped at 14.6s. You left 0.8s early. Jordan got greedy and exploded."
- Card Cannon: "You locked 17. Next card would have made 21." or "You drew 9 and overloaded to 24."

### 6.3 Bomb Pot Reveal Spec

Add to `ResolutionOverlay`:

```gdscript
static func _format_painful_reveal_bomb_pot(payload: Dictionary) -> String
```

Input:

```gdscript
{
	"bomb_at_sec": float,
	"winner_peer_id": int,
	"winner_pull_out_ms": int,
	"pulls_summary": Array[Dictionary],
}
```

Each summary entry currently has:

- `peer_id`
- `name`
- `locked_share`
- `pull_out_ms`
- `chip_delta`
- `busted`
- `wager`

Output should include:

- Bomb detonation time.
- Winner / last safe pull.
- For pullers: pull time, locked share, chip delta.
- For busted players: lost wager and "still in when it popped."
- If possible, "left X seconds before the blast."

Example:

```text
BOMB! Pot popped at 14.6s
  Maya pulled at 13.9s +220 chips, last safe pull
  Alex pulled at 8.1s +95 chips
  Jordan busted, still grabbing when it blew (-100 chips)
```

### 6.4 Card Cannon Reveal Spec

Add to `ResolutionOverlay`:

```gdscript
static func _format_painful_reveal_card_cannon(payload: Dictionary) -> String
```

Input:

```gdscript
{
	"winner_peer_id": int,
	"winner_score": int,
	"scores_summary": Array[Dictionary],
}
```

Each summary entry currently has:

- `peer_id`
- `name`
- `score`
- `locked_score`
- `chip_delta`
- `busted`
- `wager`

Output should include:

- Winning score.
- Locked safe scores.
- Bust scores.
- Perfect 21 callout.

Example:

```text
CANNONS LOCKED! Maya wins with 20
  Maya locked 20 +200 chips, Crown
  Alex locked 17 +150 chips
  Jordan overloaded at 24 (-100 chips)
```

### 6.5 Optional Event Payload Expansion

For stronger reveals, expand event payloads.

Bomb Pot:

- `elapsed_before_blast_sec` for each puller.
- `would_have_locked_at_bomb` estimate for players who pulled early.

Card Cannon:

- `bust_rank`
- `hand`
- `next_rank_if_locked`

Implementation note:

- For deterministic "next card would have been" reveals, the event must preserve RNG state or draw a reveal-only rank after finish.
- Keep this optional for now. Do not block the core formatter on it.

### 6.6 Tests

Add tests:

- `test_resolution_overlay_bomb_pot_reveal.gd`
- `test_resolution_overlay_card_cannon_reveal.gd`

Test cases:

- Bomb Pot all bust.
- Bomb Pot one last puller.
- Card Cannon perfect 21.
- Card Cannon bust.
- Card Cannon no winner.

### 6.7 Playtest Criteria

After each MVP event, at least one player should immediately understand:

- why they lost,
- what they almost got,
- who got away with greed.

## 7. Change 3: Heat Must Scale With Greed

### 7.1 Problem

Current events generally award +1 Heat to the event winner. This implements Heat as a score marker, not a drama marker.

Design intent:

- Big wins create Heat.
- High Heat makes the player valuable to attack.
- Heat creates a leader/villain arc.

### 7.2 Desired Behavior

Heat should reflect how loudly the player succeeded.

Safe success:

- Low or no Heat.

Greedy success:

- More Heat.

Legendary success:

- Big Heat and maybe bonus reward.

Bust:

- Usually no Heat gain.
- Optional Heat loss for public humiliation.

### 7.3 Shared Helper

Create a helper file:

- `scripts/match/heat_rules.gd`

Suggested API:

```gdscript
extends Object

static func rocket_heat(cash_out_at: float, won_crown: bool) -> int:
	if cash_out_at >= 10.0:
		return 4
	if cash_out_at >= 5.0:
		return 3
	if cash_out_at >= 2.5:
		return 2
	if won_crown:
		return 1
	return 0

static func bomb_pot_heat(pull_out_ms: int, bomb_at_sec: float, won_crown: bool, locked_share: int) -> int:
	var ratio = float(pull_out_ms) / max(1.0, bomb_at_sec * 1000.0)
	if ratio >= 0.95:
		return 4
	if ratio >= 0.80:
		return 3
	if won_crown:
		return 2
	if locked_share > 0:
		return 1
	return 0

static func card_cannon_heat(locked_score: int, won_crown: bool) -> int:
	if locked_score == 21:
		return 3
	if locked_score >= 19:
		return 2
	if won_crown:
		return 1
	return 0

static func apply_heat_shield(base: int, modifiers: Dictionary) -> int:
	if modifiers.get("heat_shield", false):
		return int(floor(float(base) * 0.5))
	return base
```

### 7.4 Event Changes

Rocket Clash:

- Replace flat winner `heat_delta = 1`.
- Use `HeatRules.rocket_heat(cash_out_at, winner_peer_id == pid)`.
- Apply Heat Shield.

Bomb Pot:

- Winner should not always be the only Heat source.
- Late pullers should gain Heat.
- Last puller should gain at least 2 Heat if they pulled near danger.

Card Cannon:

- Perfect 21 should gain significant Heat.
- 19-20 should gain moderate Heat.
- Low-score event winner should gain only 1 Heat.

### 7.5 Heat UI Requirements

When Heat changes, the player panel should make it readable:

- A small Heat pulse when Heat increases.
- Stronger pulse for +3 or more.
- Announcer callout for Heat 6+ and Heat 9+.

Potential announcer text:

- "Maya is on the Hot Seat."
- "Alex is now Public Enemy."
- "Jordan hit 21 and the House noticed."

### 7.6 Bounty Interaction

Heat is already used by `CardRegistry.heat_multiplier`.

Expected effect:

- Big Rocket cash-outs make future bounties worth more.
- Dramatic Bomb Pot pulls mark the winner.
- Perfect Card Cannon locks make players targets.

### 7.7 Tests

Add tests:

- `test_heat_rules.gd`
- `test_rocket_clash_heat_scaling.gd`
- `test_bomb_pot_heat_scaling.gd`
- `test_card_cannon_heat_scaling.gd`

Test examples:

- Rocket 1.4x winner -> +1 Heat.
- Rocket 5.1x survivor -> +3 Heat.
- Rocket 10x survivor -> +4 Heat.
- Bomb Pot 85% pull -> +3 Heat.
- Card Cannon 21 -> +3 Heat.
- Heat Shield halves Heat.

## 8. Change 4: Bounties Need Attribution and Better Conditions

### 8.1 Problem

Current bounty condition is only `bust`. Any surviving non-target claimant can satisfy it if the target busted.

This makes bounties too passive:

- "They busted" matters more than "I got them."
- Sabotage does not feel connected to reward.
- Multiple players can receive bounty value without social causality.

### 8.2 Desired Behavior

There should be two bounty families:

1. Public Bounties
2. Personal Bounties

Public Bounties:

- Auto-placed by House.
- Reward can split among survivors.
- Condition can remain broad.

Personal Bounties:

- Placed by a player or power card.
- Should reward the placer or the player who caused the target failure.
- Should feel like a declared rivalry.

### 8.3 Bounty Data Model

Expand `scripts/match/bounty.gd`:

```gdscript
var claim_mode: String = "survivors" # "survivors" | "placer" | "saboteur" | "best"
var event_id: String = ""            # optional event restriction
var condition_params: Dictionary = {}
```

Add fields to `to_dict()` and `from_dict()`.

Supported conditions:

- `bust`
- `bust_after_sabotage`
- `beat_cash_out`
- `outlast`
- `highest_score_over_target`
- `forced_failure`

Recommended MVP subset:

- `bust` for auto bounties.
- `bust_after_sabotage` for Place Bounty or Cash-Out Jammer combo.
- `beat_cash_out` for Rocket Clash.

### 8.4 Attribution Tracking

Add to `EventResult` or `per_player`:

```gdscript
"sabotaged_by": Array[int],
"last_sabotage_by": int,
"failure_caused_by": int,
```

For current cards:

- Cash-Out Jammer should record caller as a saboteur on the target.
- Heat Spike may count as non-failure sabotage but not failure-causing.
- Wager Tax should not count as failure-causing.

Current `cash_out_jammer.gd` returns target and delay but does not include source. Add:

```gdscript
"source": caller_peer_id
```

`CardEffectDispatcher` should preserve source in `pending_card_effects`:

```gdscript
{
	"type": "cash_out_delay",
	"source": int(effect.get("source", 0)),
	"target": int(effect.get("target", 0)),
	"delay_ms": int(effect.get("delay_ms", 750)),
}
```

`RocketClashEvent.set_cash_out_delay` should accept source:

```gdscript
func set_cash_out_delay(target_peer_id: int, delay_ms: int, source_peer_id: int = 0)
```

Internally store:

```gdscript
_pending_cash_out_delays[target_peer_id] = {
	"delay_ms": delay_ms,
	"source": source_peer_id,
}
```

If target busts after a delayed cash-out attempt or while delay is active, mark source as failure cause.

### 8.5 Bounty Resolver Logic

File:

- `scripts/match/bounty_resolver.gd`

Add resolver branches:

```gdscript
match bounty.condition:
	"bust":
		# existing public mode
	"bust_after_sabotage":
		# claimant must be source/failure_caused_by
	"beat_cash_out":
		# claimant cash_out_at > target cash_out_at and both survived
```

Claim mode rules:

- `survivors`: current split behavior.
- `placer`: placed_by gets reward if condition is satisfied.
- `saboteur`: failure_caused_by gets reward.
- `best`: single best claimant by event metric.

### 8.6 Place Bounty Card

Current Place Bounty:

- "Place a 150-chip bounty on target. Anyone who busts them claims it."

Recommended revised behavior:

- If placed during Bet/Loadout:
  - Creates personal bounty on target.
  - Condition: `bust_after_sabotage` if placer uses sabotage this event.
  - Fallback condition: `target_busts_and_placer_survives`.

Simpler MVP version:

- Place Bounty creates condition `bust`.
- claim_mode = `placer`.
- If target busts and placer survives, placer gets reward.
- Other players do not split a player-paid bounty.

This alone improves rivalry significantly.

### 8.7 UI Requirements

Bounty panel should distinguish:

- House Bounty
- Heat Bounty
- Player Bounty

Example labels:

- `HOUSE: Bust Maya +150`
- `HEAT: Drop Alex +225`
- `JORDAN'S BOUNTY: Make Maya bust +150`

When a personal bounty is claimed:

- Announcer should name both players.
- "Jordan claimed their bounty on Maya."

### 8.8 Tests

Add tests:

- `test_bounty_personal_claim_mode.gd`
- `test_bounty_bust_after_sabotage.gd`
- `test_cash_out_jammer_attribution.gd`
- `test_bounty_public_split_still_works.gd`

## 9. Change 5: Card Cannon Combat Upgrade

### 9.1 Problem

Card Cannon currently has a good push-your-luck foundation but lacks the "cannon battle" layer:

- No target firing.
- No face-card effects.
- No direct player interaction.
- No visible battle output beyond payout/Crown.

### 9.2 Desired Behavior

Card Cannon should feel like this:

1. Players draw to build cannon charge.
2. Players lock when they are brave enough.
3. Locked score becomes a shot.
4. Players choose or preselect a target.
5. Face cards create combat effects.
6. Busting overloads the cannon.

### 9.3 Minimal Combat Version

Do this first.

During `BET_LOADOUT`:

- Let players select a target for Card Cannon.
- If no target selected, auto-target highest Crown/Heat opponent.

During Card Cannon:

- Locking score stores player score.
- At finish, each non-busted player fires at target.
- Damage is represented as chip theft or Heat pressure in MVP, since Reputation/HP is not implemented.

Recommended MVP battle output:

- Locked score 1-10: no attack, payout only.
- Locked score 11-15: target pays 25 chips to pot/attacker.
- Locked score 16-18: target loses 50 chips to attacker.
- Locked score 19-20: target loses 75 chips to attacker.
- Locked score 21: target loses 100 chips to attacker, shooter gets +1 bonus Heat.

Important:

- Do not let a player go negative unless Debt-lite is implemented.
- Clamp target chip loss to available chips.

### 9.4 Event Result Extension

Add to Card Cannon per-player result:

```gdscript
"target_peer_id": int,
"attack_delta": int,
"incoming_attack": int,
```

There are two possible implementation approaches:

Approach A: Fold attacks into `chip_delta`.

- Simpler.
- Harder to explain in reveal.

Approach B: Add `secondary_deltas`.

Example:

```gdscript
result.secondary_deltas = [
	{"source": 2, "target": 3, "chip_delta": -75, "reason": "card_cannon_hit"}
]
```

Recommended for MVP:

- Keep `EventResult` simple.
- Fold into `chip_delta`.
- Add reveal summary fields so UI can explain it.

### 9.5 Face-Card Effects

Current deck uses ranks 2-11 only. Add special card identities without making UI too complex.

Option A: Use rank values with labels:

- 10 = Face
- 11 = Ace

Option B: Switch from int rank to card dictionary:

```gdscript
{"rank": 10, "face": "jack"}
```

Recommended:

- Use card dictionaries for long-term clarity.
- If too much for alpha, use integer rank first and add face labels later.

MVP face effects:

- Jack: next shot against target taxes +25 chips if shooter survives.
- Queen: shooter gains shield against one incoming chip attack.
- King: shooter gains +25 attack on lock.
- Ace: flexible score, reduces bust risk as it already does.

Implementation target:

- `scripts/events/card_cannon/card_cannon_event.gd`

New state:

```gdscript
var _face_effects: Dictionary = {} # peer_id -> Array[String]
var _selected_targets: Dictionary = {} # peer_id -> target_peer_id
```

Result summary should include:

- face effects drawn
- target
- attack value
- shield used

### 9.6 UI

Card Cannon scene should show:

- Current score.
- Drawn card row.
- Locked status.
- Target name.
- Cannon charge label.

Resolution should show:

```text
CANNONS FIRED! Maya wins with 21
  Maya locked 21, hit Alex for 100, +300 chips, Crown
  Alex locked 18, hit Maya for 50
  Jordan overloaded at 24
```

### 9.7 Tests

Add tests:

- `test_card_cannon_target_selection.gd`
- `test_card_cannon_attack_chip_transfer.gd`
- `test_card_cannon_face_effects.gd`
- `test_card_cannon_reveal_combat_summary.gd`

## 10. Change 6: Add Comeback Path Before Full Debt

### 10.1 Problem

The design doc depends on Debt/black-market/comeback systems, but the alpha only skips players who cannot pay ante:

```gdscript
if p.chips >= ante:
	p.chips -= ante
	p.is_active_this_event = true
else:
	p.is_active_this_event = false
```

This can create dead air for broke players.

### 10.2 Desired Behavior

Players with low chips should receive a risky way back into play.

This should feel like:

- "The House offers you a terrible deal."
- Not free charity.
- A way to create drama.

### 10.3 Debt-Lite MVP

Add to `MatchPlayer`:

```gdscript
var debt: int = 0
```

Serialize it.

Add constants:

```gdscript
const MAX_DEBT: int = 300
const HOUSE_LOAN_AMOUNT: int = 150
const DEBT_GARNISH_RATE: float = 0.25
```

Ante behavior:

- If player cannot pay ante:
  - Offer House Loan.
  - If accepted or auto-accepted in MVP:
    - player.debt += HOUSE_LOAN_AMOUNT
    - player.chips += HOUSE_LOAN_AMOUNT
    - pay ante
    - player gains +1 Heat or receives "Cursed Debtor" flag

Resolution behavior:

- If player has debt and positive chip_delta:
  - garnish 25% of positive winnings toward debt
  - reduce chip_delta by garnished amount
  - reduce debt

### 10.4 UI

Player panel:

- Show `Debt: 150` or small debt icon.

Resolution:

- Show "House garnished 40 chips from Maya's winnings."

Shop:

- If in debt, show one black-market offer later.

### 10.5 Tests

Add tests:

- `test_match_controller_house_loan.gd`
- `test_debt_garnish_positive_winnings.gd`
- `test_debt_does_not_garnish_losses.gd`
- `test_debt_serialization.gd`

## 11. Change 7: Public Feedback For Cards And Twists

### 11.1 Problem

Some cards affect math without enough public table feedback. Risk Royal needs players to notice betrayal.

### 11.2 Desired Behavior

When a card is played:

- The target sees it.
- The table hears/sees a short callout.
- The result screen explains its effect.

### 11.3 Implementation

Use existing signal:

- `card_effect_applied(peer_id, card_id, effect_result)`

Update `scripts/ui/announcer.gd` to format card callouts:

Examples:

- `Jordan jammed Maya's cash-out.`
- `Maya bought Insurance. Cowardly? Effective.`
- `Alex copied Sam's wager.`
- `Jordan spiked Maya's Heat.`

Add visual tags in resolution:

- Insurance reduced bust loss.
- Wager Tax redirected chips.
- Multiplier Booster increased payout.
- Cash-Out Jammer delayed a cash-out.

### 11.4 Tests

Add tests:

- `test_announcer_card_callouts.gd`
- `test_resolution_overlay_card_modifier_notes.gd`

## 12. Change 8: House Twist Feel Pass

### 12.1 Problem

House Twists are implemented but should feel more like show moments.

### 12.2 Desired Behavior

A twist should answer:

- What changed?
- Who is in trouble?
- What should I do differently?

### 12.3 Twist Presentation

For each twist, define:

```gdscript
{
	"title": "NO INSURANCE",
	"subtitle": "No safety nets next event.",
	"target_peer_id": 0,
	"severity": "medium",
}
```

Specific copy:

- Double Bounty: "Bounties doubled. Make it personal."
- No Insurance: "No Insurance. Greed has no helmet."
- Leader Cursed: "Leader Cursed. Maya's next reward is cut."
- Power Surge: "Power Surge. Everyone gets a fresh trick."
- Lowest Chips Picks: "Underdog's Choice. Alex picks the next table."
- Sudden Death Jackpot: "Bonus Crown live. Take the dangerous route."

### 12.4 Tests

Add:

- `test_house_twist_overlay_copy.gd`
- `test_announcer_twist_target_name.gd`

## 13. Change 9: Clean Automated Validation Gate

### 13.1 Problem

The unit command exits code 0 but emits runtime errors:

- Duplicate `event_complete` signal connections.
- RPC calls to self or unknown peers.
- GUT loader static init error.
- Resource/RID leaks.

This undermines confidence.

### 13.2 Expected Gate

A public alpha validation gate should satisfy:

- Unit tests exit 0.
- Integration tests exit 0.
- No `SCRIPT ERROR`.
- No `ERROR:` lines except explicitly whitelisted expected errors.
- No uncontrolled RPC errors.

### 13.3 Bug: Duplicate `event_complete` Connections

Observed:

```text
Signal 'event_complete' is already connected to given callable
```

Likely location:

- `MatchController._process_main_event`

Potential causes:

- Reusing `_current_event_node`.
- Test mock event emits or remains connected across phase transitions.
- `_process_main_event` called multiple times without disconnect/free.
- `_schedule_advance` in detached tests advances into main event unexpectedly.

Troubleshooting steps:

1. Inspect `_process_main_event`.
2. Before connecting, check:
   ```gdscript
   if not _current_event_node.event_complete.is_connected(_on_event_complete):
   	_current_event_node.event_complete.connect(_on_event_complete)
   ```
3. Ensure `_clear_event_timeout_watchdog()` and event cleanup happen before replacing nodes.
4. In tests, avoid phase auto-advance into real event unless intended.
5. Add unit test that entering `MAIN_EVENT` twice does not double-connect.

### 13.4 Bug: RPC To Self / Unknown Peers

Observed:

```text
RPC '_rpc_starter_pack_dealt' on yourself is not allowed by selected mode.
Attempt to call RPC with unknown peer ID: 2.
```

Likely location:

- `MatchController._deal_starter_pack`
- `MatchRpcSender.send_to_peer`

Likely context:

- In-tree unit tests with no real multiplayer peers.
- Host attempts `rpc_id` to itself or to fake peer ID 2.

Troubleshooting steps:

1. In `MatchRpcSender.send_to_peer`, if no real multiplayer peer is connected, no-op or call local mirror directly in tests.
2. For host's own starter pack, apply locally without RPC.
3. Only call `rpc_id(peer_id)` when peer is known and connected.
4. Add a test-mode fake sender instead of using real SceneTree RPC.

### 13.5 Bug: GUT Loader Static Init

Observed:

```text
SCRIPT ERROR: Trying to assign value of type 'Nil' to a variable of type 'bool'.
at: _static_init (res://addons/gut/gut_loader.gd:35)
```

Troubleshooting steps:

1. Check GUT plugin compatibility with Godot 4.6.
2. Inspect `gut_loader.gd:35`.
3. If this is plugin-side and harmless, document it as a known warning.
4. If not harmless, update GUT or patch plugin locally.

### 13.6 Bug: Resource/RID Leaks

Observed:

- CanvasItem RIDs leaked.
- ShapedTextData leaked.
- ObjectDB instances leaked.
- Resources in use at exit.

Potential causes:

- UI nodes created in tests and not freed.
- Tweens active at test exit.
- Event nodes or overlays still in scene tree.

Troubleshooting steps:

1. Ensure tests use `add_child_autofree`.
2. Kill active tweens in `_exit_tree` for overlays.
3. Queue/free created event nodes after tests.
4. Add cleanup in `PainfulReveal`, `ResolutionOverlay`, and test fixtures.

### 13.7 Bug: Encoding / Mojibake In Text

Observed in files/output:

- mojibake crown emoji sequence
- mojibake X/checkmark sequence
- mojibake arrow sequence
- mojibake section-symbol sequence

Risk:

- UI text may render incorrectly.
- Test expectations may depend on broken encoding.
- Player-facing polish looks unprofessional.

Decision needed:

- Either standardize all source text to UTF-8 and keep icons.
- Or replace source emoji/symbols with ASCII-safe labels/icons from textures.

Recommended:

- For source code, use ASCII constants:
  - `[CROWN]`
  - `[X]`
  - `->`
- Let UI map these to icons or textures.

### 13.8 Bug: Untracked Generated Files

Observed:

- Many `.uid` files untracked.
- Several temp-output files with malformed names in repo root.

Risk:

- Public alpha repo hygiene suffers.
- Test output may be accidentally committed.

Recommended:

- Add temp output patterns to `.gitignore`.
- Decide whether `.uid` files are intentionally committed for Godot.
- Remove or relocate root temp logs.

## 14. Implementation Roadmap

### Phase A: Stop Feel Breakage

Goal:

- Busting no longer ends player participation.
- Test gate no longer emits core runtime errors.

Tasks:

1. Remove match-long spectator transition from event bust.
2. Add/adjust tests for event-local bust.
3. Fix duplicate event signal connection.
4. Fix test-mode RPC self/unknown-peer errors.

Success criteria:

- A player can bust event 1 and play event 2.
- Unit and integration tests have no unexpected `ERROR:` output.

### Phase B: Pay Off Every Event

Goal:

- Every MVP event has a satisfying reveal.

Tasks:

1. Add Bomb Pot reveal formatter.
2. Add Card Cannon reveal formatter.
3. Add tests.
4. Add optional payload details if simple.

Success criteria:

- Players understand what happened in every event.
- Reveals create regret and laughter.

### Phase C: Make Heat And Bounties Matter

Goal:

- Big greedy plays create table pressure.
- Bounties create rivalry.

Tasks:

1. Add `HeatRules`.
2. Update all three event result functions.
3. Add bounty `claim_mode`.
4. Make Place Bounty personal.
5. Add attribution for Cash-Out Jammer.
6. Update bounty panel copy.

Success criteria:

- A high Rocket cash-out makes that player a target.
- A player-placed bounty feels personal.

### Phase D: Make Card Cannon A Battle Event

Goal:

- Card Cannon has a distinct combat identity.

Tasks:

1. Add target selection.
2. Add chip attack output.
3. Add face-card effects.
4. Update reveal summary.
5. Add tests.

Success criteria:

- Players talk about who they are shooting.
- Drawing/locking creates social pressure, not only payout optimization.

### Phase E: Add Comeback Pressure

Goal:

- Broke players stay emotionally alive.

Tasks:

1. Add `debt` field.
2. Add House Loan in ante.
3. Add debt garnish.
4. Show Debt in UI.
5. Add tests.

Success criteria:

- A broke player gets one dangerous route back.
- Debt feels tempting but painful.

## 15. Updated Manual Playtest Scenarios

### Scenario 1: Bust And Return

Players: 2

Steps:

1. Player A busts in Rocket Clash.
2. Player B finishes event.
3. Event 2 starts.

Pass:

- Player A can wager and play event 2.

### Scenario 2: Bomb Pot Regret

Players: 3

Steps:

1. Player A pulls early.
2. Player B pulls close to bomb.
3. Player C busts.

Pass:

- Reveal shows bomb time, pull times, last safe pull, and bust.

### Scenario 3: Card Cannon Battle

Players: 3

Steps:

1. Players select targets.
2. Player A locks 20.
3. Player B busts.
4. Player C locks 16.

Pass:

- Reveal shows locked scores, target hits, chip attack results, and bust.

### Scenario 4: Heat Villain

Players: 3

Steps:

1. Player A cashes Rocket Clash above 5x.
2. Next event begins.

Pass:

- Player A has visibly higher Heat.
- Bounty value or panel reflects that Heat.
- Other players understand Player A is now a good target.

### Scenario 5: Personal Bounty

Players: 3

Steps:

1. Player A places bounty on Player B.
2. Player B busts.
3. Player A survives.

Pass:

- Player A claims the bounty.
- Other surviving players do not split Player A's personal bounty.

### Scenario 6: Debt-Lite Comeback

Players: 2

Steps:

1. Player A runs out of chips before ante.
2. House Loan triggers.
3. Player A wins event.

Pass:

- Player A can play.
- Some winnings are garnished.
- Debt UI updates.

## 16. Acceptance Criteria For Desired Feel

The remediation is successful when:

- Busting creates laughter/regret, not disengagement.
- Every event has a clear "you almost had it" reveal.
- Heat changes are visible enough to alter player behavior.
- Bounties create named rivalries.
- Card Cannon feels like a battle table, not a quiet score table.
- Broke players have a risky comeback option.
- Tests run without unexpected runtime errors.

## 17. Non-Goals

Do not implement these as part of this remediation unless separately scheduled:

- Full 10-event standard mode.
- Full Royal Run finale.
- Reputation/HP combat layer.
- All mini-games from the design doc.
- Full black-market economy.
- Real-money gambling features.
- Cosmetic season systems.

## 18. Final Recommendation

Fix the bust/spectator issue first. It is the one problem that actively fights the soul of the game. Then make Bomb Pot and Card Cannon reveals land, because the current alpha already has enough event variety to feel much better if the endings are sharp. After that, scale Heat and make bounties personal. Those four improvements should move Risk Royal from "prototype with good systems" to "friends yelling at a battle casino," which is the actual target.
