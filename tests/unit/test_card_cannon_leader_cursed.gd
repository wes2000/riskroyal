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

func test_leader_cursed_reduces_survivor_band_payout():
	# P2 locks 20 → heavy band (× 2.0) → 100 × 2.0 × 0.75 = 150
	var ctx = _make_context(2, {1: 100, 2: 100})
	ctx.house_twist = {"type": "leader_cursed", "params": {"leader_peer_id": 2, "reward_multiplier": 0.75}}
	var hands = {1: [10, 10], 2: [10, 10]}
	var locked = {1: 20, 2: 20}
	var busted = {}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	assert_eq(result.per_player[1].chip_delta, 200, "P1 not cursed: 100 × 2.0 = 200")
	assert_eq(result.per_player[2].chip_delta, 150, "P2 cursed: 100 × 2.0 × 0.75 = 150")
