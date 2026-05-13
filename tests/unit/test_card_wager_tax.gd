extends GutTest

const WagerTax = preload("res://scripts/cards/effects/wager_tax.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func test_wager_tax_meta():
	var m = WagerTax.CARD_META
	assert_eq(m.name, "Wager Tax")
	assert_eq(m.rarity, "common")
	assert_eq(m.category, "sabotage")
	assert_eq(m.timing, "bet_loadout")
	assert_eq(m.target_required, true)
	assert_eq(m.cost_chips, 50)

func test_apply_returns_post_event_wager_tax():
	# Use params dict to convey caller_peer_id (Plan B convention for
	# self-target-aware cards). Will be supplied by the dispatcher.
	var ctx = EventContext.new()
	var p = MatchPlayer.new(); p.peer_id = 3; p.is_active_this_event = true
	ctx.players.append(p)
	var result = WagerTax.apply(ctx, 3, {"caller_peer_id": 1})
	assert_true(result.applied)
	assert_eq(result.type, "post_event_wager_tax")
	assert_eq(result.source, 1, "caller is the tax recipient")
	assert_eq(result.target, 3, "target loses 20% chip gain")

func test_apply_no_op_when_target_not_active():
	var ctx = EventContext.new()
	var p = MatchPlayer.new(); p.peer_id = 3; p.is_active_this_event = false
	ctx.players.append(p)
	var result = WagerTax.apply(ctx, 3, {"caller_peer_id": 1})
	assert_false(result.applied)

func test_apply_no_op_when_caller_targets_self():
	var ctx = EventContext.new()
	var p = MatchPlayer.new(); p.peer_id = 1; p.is_active_this_event = true
	ctx.players.append(p)
	var result = WagerTax.apply(ctx, 1, {"caller_peer_id": 1})
	assert_false(result.applied)
