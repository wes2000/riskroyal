extends GutTest

const DoubleOrNothing = preload("res://scripts/cards/effects/double_or_nothing.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func test_double_or_nothing_meta():
	var m = DoubleOrNothing.CARD_META
	assert_eq(m.name, "Double or Nothing")
	assert_eq(m.rarity, "rare")
	assert_eq(m.category, "greed")
	assert_eq(m.cost_chips, 150)

func test_apply_returns_doubled_wager():
	var ctx = EventContext.new()
	var p = MatchPlayer.new()
	p.peer_id = 1
	p.chips = 500
	ctx.players.append(p)
	ctx.wagers = {1: 100}
	var result = DoubleOrNothing.apply(ctx, 1, null)
	assert_true(result.applied)
	assert_eq(result.type, "double_or_nothing")
	assert_eq(result.new_wager, 200)

func test_apply_caps_at_chip_count():
	var ctx = EventContext.new()
	var p = MatchPlayer.new()
	p.peer_id = 1
	p.chips = 150
	ctx.players.append(p)
	ctx.wagers = {1: 100}
	var result = DoubleOrNothing.apply(ctx, 1, null)
	assert_true(result.applied)
	assert_eq(result.new_wager, 150, "doubled wager capped at chip count")
