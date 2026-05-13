extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start(player_count: int) -> RefCounted:
	var ms = MatchStart.new()
	for i in player_count:
		var s = PlayerSlot.new()
		s.peer_id = i + 1; s.seat_index = i; s.name = "P%d" % (i + 1)
		ms.seats.append(s)
	ms.host_peer_id = 1; ms.rng_seed = 1
	return ms

func test_build_event_context_carries_house_twist_snapshot():
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(2))
	c.state.house_twist = {"type": "double_bounty", "params": {"reward_multiplier": 2.0}}
	var ctx = c._build_event_context()
	assert_eq(ctx.house_twist.get("type", ""), "double_bounty")
	assert_almost_eq(float(ctx.house_twist.get("params", {}).get("reward_multiplier", 0.0)), 2.0, 0.001)
