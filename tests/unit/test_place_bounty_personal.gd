extends GutTest

const PlaceBounty = preload("res://scripts/cards/effects/place_bounty.gd")
const CardEffectDispatcher = preload("res://scripts/match/card_effect_dispatcher.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const MatchState = preload("res://scripts/match/match_state.gd")

# When P1 plays Place Bounty on P3, the effect must include claim_mode="placer"
# + placed_by=1 so BountyResolver routes the reward to P1 only.
func test_place_bounty_apply_returns_personal_claim_mode():
	var ctx = EventContext.new()
	var p = MatchPlayer.new(); p.peer_id = 3; p.is_active_this_event = true; p.heat = 2
	ctx.players.append(p)
	var effect = PlaceBounty.apply(ctx, 3, {"caller_peer_id": 1, "event_index": 2})
	assert_true(effect.applied)
	assert_eq(String(effect.get("type", "")), "place_bounty")
	assert_eq(int(effect.get("target", 0)), 3)
	assert_eq(String(effect.get("claim_mode", "")), "placer",
		"Place Bounty card creates personal bounties")
	assert_eq(int(effect.get("placed_by", 0)), 1,
		"placed_by tracks the caller")

# Dispatcher must propagate claim_mode into the created Bounty.
func test_dispatcher_builds_bounty_with_placer_claim_mode():
	var s = MatchState.new()
	for i in 3:
		var pl = MatchPlayer.new()
		pl.peer_id = i + 1; pl.is_active_this_event = true; pl.chips = 500
		s.players.append(pl)
	s.event_index = 1
	CardEffectDispatcher.apply(s, 1, {
		"type": "place_bounty",
		"applied": true,
		"target": 3,
		"placed_by": 1,
		"placed_at_target_heat": 2,
		"placed_at_event": 1,
		"reward_chips": 150,
		"claim_mode": "placer",
	}, true)
	assert_eq(s.bounties.size(), 1)
	var b = s.bounties[0]
	assert_eq(b.origin, "placed")
	assert_eq(int(b.target), 3)
	assert_eq(int(b.placed_by), 1)
	assert_eq(b.claim_mode, "placer", "claim_mode propagated to Bounty")

# Default claim_mode fallback when dispatcher receives an effect dict without
# the key — should default to "placer" so legacy callers stay personal.
func test_dispatcher_defaults_to_placer_when_claim_mode_omitted():
	var s = MatchState.new()
	for i in 3:
		var pl = MatchPlayer.new()
		pl.peer_id = i + 1; pl.is_active_this_event = true; pl.chips = 500
		s.players.append(pl)
	s.event_index = 1
	CardEffectDispatcher.apply(s, 1, {
		"type": "place_bounty",
		"applied": true,
		"target": 3,
		"placed_by": 1,
		"reward_chips": 150,
	}, true)
	assert_eq(s.bounties.size(), 1)
	assert_eq(s.bounties[0].claim_mode, "placer",
		"player-paid bounties default personal via dispatcher")
