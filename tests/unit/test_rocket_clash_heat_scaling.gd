extends GutTest

const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(peer_id: int) -> RefCounted:
	var p = MatchPlayer.new()
	p.peer_id = peer_id
	p.seat_index = peer_id - 1
	p.name = "P%d" % peer_id
	p.is_active_this_event = true
	return p

func _make_context(player_count: int, wagers: Dictionary) -> RefCounted:
	var ctx = EventContext.new()
	for i in player_count:
		ctx.players.append(_make_player(i + 1))
	ctx.wagers = wagers
	return ctx

func test_rocket_clash_10x_winner_gets_4_heat():
	# P1 cashes at 10x, P2 cashes at 1.5x -> P1 wins (highest cash_out).
	var ctx = _make_context(2, {1: 100, 2: 100})
	var cash_outs = {1: 10.0, 2: 1.5}
	var busted: Array = []
	var result = RocketClashEvent.compute_event_result(ctx, 15.0, cash_outs, busted)
	assert_eq(int(result.per_player[1].heat_delta), 4, "10x winner = +4 Heat")

func test_rocket_clash_5x_survivor_gets_3_heat():
	var ctx = _make_context(2, {1: 100, 2: 100})
	var cash_outs = {1: 5.5, 2: 2.0}
	var busted: Array = []
	var result = RocketClashEvent.compute_event_result(ctx, 10.0, cash_outs, busted)
	assert_eq(int(result.per_player[1].heat_delta), 3, "5x+ survivor = +3 Heat")

func test_rocket_clash_low_winner_gets_1_heat():
	var ctx = _make_context(2, {1: 100, 2: 100})
	var cash_outs = {1: 1.5, 2: 1.2}
	var busted: Array = []
	var result = RocketClashEvent.compute_event_result(ctx, 2.0, cash_outs, busted)
	assert_eq(int(result.per_player[1].heat_delta), 1, "low-multiplier winner = +1 Heat")

func test_rocket_clash_bust_gets_0_heat():
	var ctx = _make_context(2, {1: 100, 2: 100})
	var cash_outs = {2: 3.0}
	var busted: Array = [1]
	var result = RocketClashEvent.compute_event_result(ctx, 2.5, cash_outs, busted)
	assert_eq(int(result.per_player[1].heat_delta), 0, "busted player gets 0 Heat")

func test_rocket_clash_heat_shield_halves():
	# P1 cashes at 10x (would be 4 Heat) but has heat_shield modifier.
	var ctx = _make_context(2, {1: 100, 2: 100})
	ctx.event_modifiers = {1: {"heat_shield": true}}
	var cash_outs = {1: 10.0, 2: 1.5}
	var busted: Array = []
	var result = RocketClashEvent.compute_event_result(ctx, 15.0, cash_outs, busted)
	assert_eq(int(result.per_player[1].heat_delta), 2, "heat_shield halves 4 -> 2")
