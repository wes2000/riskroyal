extends GutTest

const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(peer_id: int, name: String, seat_index: int = -1) -> RefCounted:
	var p = MatchPlayer.new()
	p.peer_id = peer_id; p.name = name; p.is_active_this_event = true
	p.seat_index = seat_index if seat_index >= 0 else peer_id
	return p

func _make_context(player_count: int, wagers: Dictionary, modifiers: Dictionary) -> RefCounted:
	var ctx = EventContext.new()
	for i in player_count:
		ctx.players.append(_make_player(i + 1, "P%d" % (i + 1), i))
	ctx.wagers = wagers
	ctx.event_modifiers = modifiers
	return ctx

func test_leader_cursed_reduces_survivor_chip_delta():
	# P2 is the cursed leader; survives at 2.0x → chip_delta = 100 × 2.0 = 200, × 0.75 = 150
	var ctx = _make_context(2, {1: 100, 2: 100}, {})
	ctx.house_twist = {"type": "leader_cursed", "params": {"leader_peer_id": 2, "reward_multiplier": 0.75}}
	var cash_outs = {1: 2.0, 2: 2.0}
	var busted: Array = []
	var result = RocketClashEvent.compute_event_result(ctx, 3.0, cash_outs, busted)
	assert_eq(result.per_player[1].chip_delta, 200, "P1 not cursed: 100 × 2.0 = 200")
	assert_eq(result.per_player[2].chip_delta, 150, "P2 cursed: 100 × 2.0 × 0.75 = 150")
