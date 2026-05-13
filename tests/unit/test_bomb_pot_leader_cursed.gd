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

func test_leader_cursed_reduces_survivor_locked_share():
	var ctx = _make_context(2, {1: 100, 2: 100})
	ctx.house_twist = {"type": "leader_cursed", "params": {"leader_peer_id": 2, "reward_multiplier": 0.75}}
	var locked = {1: 200, 2: 200}
	var pulled = [1, 2]
	var timestamps = {1: 8000, 2: 9000}
	var result = BombPotEvent.compute_event_result(ctx, 15.0, locked, pulled, timestamps)
	assert_eq(result.per_player[1].chip_delta, 200, "P1 not cursed: 200 locked share")
	assert_eq(result.per_player[2].chip_delta, 150, "P2 cursed: 200 × 0.75 = 150")
