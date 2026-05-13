extends GutTest

const PlaceBounty = preload("res://scripts/cards/effects/place_bounty.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func test_place_bounty_meta():
	var m = PlaceBounty.CARD_META
	assert_eq(m.name, "Place Bounty")
	assert_eq(m.rarity, "rare")
	assert_eq(m.category, "social")
	assert_eq(m.timing, "bet_loadout")
	assert_eq(m.target_required, true)
	assert_eq(m.cost_chips, 150)

func test_apply_returns_place_bounty_effect():
	var ctx = EventContext.new()
	var p = MatchPlayer.new(); p.peer_id = 4; p.is_active_this_event = true; p.heat = 3
	ctx.players.append(p)
	var result = PlaceBounty.apply(ctx, 4, {"caller_peer_id": 1, "event_index": 2})
	assert_true(result.applied)
	assert_eq(result.type, "place_bounty")
	assert_eq(result.target, 4)
	assert_eq(result.placed_by, 1)
	assert_eq(result.placed_at_target_heat, 3)
	assert_eq(result.placed_at_event, 2)
	assert_eq(result.reward_chips, 150)

func test_apply_no_op_when_self_target():
	var ctx = EventContext.new()
	var p = MatchPlayer.new(); p.peer_id = 1; p.is_active_this_event = true
	ctx.players.append(p)
	var result = PlaceBounty.apply(ctx, 1, {"caller_peer_id": 1})
	assert_false(result.applied)
