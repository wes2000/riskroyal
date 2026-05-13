extends GutTest

const BombPotEvent = preload("res://scripts/events/bomb_pot/bomb_pot_event.gd")
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

func test_sudden_death_pull_out_after_80_pct_awards_bonus_crown_and_stacks():
	# bomb_at_sec = 10.0 → 80% threshold = 8000 ms.
	# P1 pulls at 7000 ms (under threshold) → no bonus.
	# P2 pulls at 9500 ms (over threshold AND latest puller → wins regular Crown)
	# → crown_delta = 2.
	var ctx = _make_context(2, {1: 100, 2: 100})
	ctx.house_twist = {
		"type": "sudden_death_jackpot",
		"params": {"condition": "pull_out_after_80_pct"},
	}
	var locked = {1: 100, 2: 100}
	var pulled = [1, 2]
	var timestamps = {1: 7000, 2: 9500}
	var result = BombPotEvent.compute_event_result(ctx, 10.0, locked, pulled, timestamps)
	assert_eq(result.per_player[1].crown_delta, 0, "P1 below threshold")
	assert_eq(result.per_player[2].crown_delta, 2, "P2 winner + bonus = 2")
