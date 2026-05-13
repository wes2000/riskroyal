extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const HouseTwistController = preload("res://scripts/match/house_twist_controller.gd")
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

func _new_host() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(2))
	return {"controller": c, "fake": fake}

func test_house_twist_phase_selects_and_sets_state():
	var d = _new_host()
	var c = d.controller
	c.state.event_index = 2  # event 2+ → twist fires
	# Vary chips so leader_cursed + lowest_chips_picks are eligible
	c.state.players[0].chips = 500
	c.state.players[1].chips = 700
	c._process_house_twist()
	assert_true(c.state.house_twist.has("type"), "state.house_twist populated")
	assert_true(c.state.house_twist.type in HouseTwistController.TWIST_POOL)
	assert_eq(c.state.last_twist_type, c.state.house_twist.type, "last_twist_type set")

func test_house_twist_phase_no_op_at_event_0():
	var d = _new_host()
	var c = d.controller
	c.state.event_index = 0
	# Seed last_twist_type with a non-default to verify the no-op
	# preserves it (instead of accidentally asserting the init default).
	c.state.last_twist_type = "prior_value"
	c._process_house_twist()
	assert_eq(c.state.house_twist, {}, "no twist before event 1")
	assert_eq(c.state.last_twist_type, "prior_value",
		"no-op preserves prior last_twist_type")

func test_house_twist_phase_broadcasts_announced():
	var d = _new_host()
	var c = d.controller
	c.state.event_index = 2
	c.state.players[0].chips = 500
	c.state.players[1].chips = 700
	d.fake.rpc_calls.clear()
	c._process_house_twist()
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_house_twist_announced":
			found = true
			assert_true(call.args[0].has("type"), "broadcast carries twist dict")
			break
	assert_true(found, "_rpc_house_twist_announced broadcast")
