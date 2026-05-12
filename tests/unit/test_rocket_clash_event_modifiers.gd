extends GutTest

const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(peer_id: int, name: String, chips: int = 800) -> RefCounted:
	var p = MatchPlayer.new()
	p.peer_id = peer_id
	p.name = name
	p.chips = chips
	p.is_active_this_event = true
	return p

func _make_context(player_count: int, wagers: Dictionary, modifiers: Dictionary) -> RefCounted:
	var ctx = EventContext.new()
	for i in player_count:
		ctx.players.append(_make_player(i + 1, "P%d" % (i + 1)))
	ctx.wagers = wagers
	ctx.event_modifiers = modifiers
	return ctx

func test_insurance_halves_bust_penalty():
	var ctx = _make_context(2, {1: 100, 2: 100}, {1: {"insurance_pre": true}})
	var cash_outs = {}
	var busted = [1, 2]
	var result = RocketClashEvent.compute_event_result(ctx, 1.5, cash_outs, busted)
	assert_eq(result.chip_delta_for(1), -50, "P1 with insurance loses 50 not 100")
	assert_eq(result.chip_delta_for(2), -100, "P2 without insurance loses 100")

func test_wager_multiplier_boosts_survivor_chip_gain():
	var ctx = _make_context(2, {1: 100, 2: 100}, {1: {"wager_multiplier": 1.25}})
	var cash_outs = {1: 2.0, 2: 2.0}
	var busted = []
	var result = RocketClashEvent.compute_event_result(ctx, 3.0, cash_outs, busted)
	assert_eq(result.chip_delta_for(1), 250)
	assert_eq(result.chip_delta_for(2), 200)

func test_underdog_multiplier_boosts_survivor_chip_gain():
	var ctx = _make_context(2, {1: 100, 2: 100}, {1: {"underdog_multiplier": 1.5}})
	var cash_outs = {1: 2.0, 2: 2.0}
	var busted = []
	var result = RocketClashEvent.compute_event_result(ctx, 3.0, cash_outs, busted)
	assert_eq(result.chip_delta_for(1), 300)

func test_late_cash_bonus_applies_above_threshold():
	var ctx = _make_context(2, {1: 100, 2: 100},
		{1: {"late_cash_bonus": true, "late_cash_threshold": 5.0, "late_cash_bonus_chips": 200}})
	var cash_outs = {1: 6.0, 2: 6.0}
	var busted = []
	var result = RocketClashEvent.compute_event_result(ctx, 7.0, cash_outs, busted)
	assert_eq(result.chip_delta_for(1), 800)
	assert_eq(result.chip_delta_for(2), 600)

func test_late_cash_bonus_skipped_below_threshold():
	var ctx = _make_context(1, {1: 100},
		{1: {"late_cash_bonus": true, "late_cash_threshold": 5.0, "late_cash_bonus_chips": 200}})
	var cash_outs = {1: 4.0}
	var busted = []
	var result = RocketClashEvent.compute_event_result(ctx, 5.0, cash_outs, busted)
	assert_eq(result.chip_delta_for(1), 400)

func test_heat_shield_halves_heat_delta():
	var ctx = _make_context(1, {1: 100}, {1: {"heat_shield": true}})
	var cash_outs = {1: 2.0}
	var busted = []
	var result = RocketClashEvent.compute_event_result(ctx, 3.0, cash_outs, busted)
	assert_eq(result.per_player[1].heat_delta, 0)

func test_compute_event_result_with_no_modifiers_unchanged():
	var ctx = _make_context(2, {1: 100, 2: 100}, {})
	var cash_outs = {1: 2.5, 2: 1.5}
	var busted = []
	var result = RocketClashEvent.compute_event_result(ctx, 3.0, cash_outs, busted)
	assert_eq(result.chip_delta_for(1), 250)
	assert_eq(result.chip_delta_for(2), 150)
