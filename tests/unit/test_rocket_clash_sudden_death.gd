extends GutTest

const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(peer_id: int, name: String, seat_index: int = -1) -> RefCounted:
	var p = MatchPlayer.new()
	p.peer_id = peer_id; p.name = name; p.is_active_this_event = true
	p.seat_index = seat_index if seat_index >= 0 else peer_id
	return p

func _make_context(player_count: int, wagers: Dictionary) -> RefCounted:
	var ctx = EventContext.new()
	for i in player_count:
		ctx.players.append(_make_player(i + 1, "P%d" % (i + 1), i))
	ctx.wagers = wagers
	return ctx

func test_sudden_death_cash_out_over_5x_awards_bonus_crown_and_stacks_with_winner():
	# P2 cashes at 6.0× (meets condition AND wins the crown for highest
	# cash-out) → crown_delta = 2. P1 cashes at 4.0× (no condition, no
	# crown) → crown_delta = 0.
	var ctx = _make_context(2, {1: 100, 2: 100})
	ctx.house_twist = {
		"type": "sudden_death_jackpot",
		"params": {"condition": "cash_out_over_5x"},
	}
	var cash_outs = {1: 4.0, 2: 6.0}
	var busted: Array = []
	var result = RocketClashEvent.compute_event_result(ctx, 10.0, cash_outs, busted)
	assert_eq(result.per_player[1].crown_delta, 0,
		"P1 cashed at 4.0× - below threshold")
	assert_eq(result.per_player[2].crown_delta, 2,
		"P2 winner + sudden death bonus = 1 + 1 = 2")
