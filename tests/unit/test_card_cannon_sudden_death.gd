extends GutTest

const CardCannonEvent = preload("res://scripts/events/card_cannon/card_cannon_event.gd")
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

func test_sudden_death_locked_at_perfect_awards_bonus_crown_and_stacks():
	# P1 locks 18 (no bonus). P2 locks exactly 21 (perfect — bonus AND
	# wins regular Crown via highest locked score). P2 → crown_delta = 2.
	var ctx = _make_context(2, {1: 100, 2: 100})
	ctx.house_twist = {
		"type": "sudden_death_jackpot",
		"params": {"condition": "locked_at_perfect"},
	}
	var hands = {1: [10, 8], 2: [10, 11]}
	var locked = {1: 18, 2: 21}
	var busted = {}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	assert_eq(result.per_player[1].crown_delta, 0, "P1 below 21")
	assert_eq(result.per_player[2].crown_delta, 2, "P2 perfect + winner = 2")
