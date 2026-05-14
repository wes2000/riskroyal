extends GutTest

const BombPotEvent = preload("res://scripts/events/bomb_pot/bomb_pot_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_context(player_count: int) -> RefCounted:
	var ctx = EventContext.new()
	for i in player_count:
		var p = MatchPlayer.new()
		p.peer_id = i + 1
		p.seat_index = i
		p.name = "P%d" % (i + 1)
		ctx.players.append(p)
		ctx.wagers[i + 1] = 100
	return ctx

func test_no_pullers_no_winner_crowned():
	# All 3 players bust (no one pulls out). The function should NOT
	# crown anyone via the winner_pull_out_ms sentinel comparison.
	var ctx = _make_context(3)
	var result = BombPotEvent.compute_event_result(
		ctx, 10.0,
		{},      # locked_shares — empty (no one pulled)
		[],      # pulled_out_peers — empty
		{}       # pull_out_timestamps — empty
	)
	# All players busted; none should have crown_delta > 0
	for pid in [1, 2, 3]:
		assert_eq(int(result.per_player[pid].get("crown_delta", 0)), 0,
			"P%d should not be crowned when no one pulled out" % pid)
	assert_eq(int(result.painful_reveal.get("winner_peer_id", -1)), 0,
		"winner_peer_id should be 0 when no pullers")
