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

func _new_host() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(2))
	c.state.house_twist = {
		"type": "lowest_chips_picks",
		"params": {
			"picker_peer_id": 2,
			"options": [
				"res://scenes/events/rocket_clash/rocket_clash_event.tscn",
				"res://scenes/events/bomb_pot/bomb_pot_event.tscn",
			],
			"timeout_sec": 10,
		},
	}
	return {"controller": c, "fake": fake}

func test_rpc_event_picker_choice_happy_path_sets_state():
	var d = _new_host()
	var c = d.controller
	c._rpc_event_picker_choice(2, "res://scenes/events/bomb_pot/bomb_pot_event.tscn")
	assert_eq(c.state.current_event_id,
		"res://scenes/events/bomb_pot/bomb_pot_event.tscn",
		"valid pick from picker sets state.current_event_id")

func test_rpc_event_picker_choice_rejects_wrong_peer():
	# Player 1 is NOT the picker (picker is peer 2). Submitting should
	# be silently ignored — state.current_event_id stays empty.
	var d = _new_host()
	var c = d.controller
	c.state.current_event_id = ""
	c._rpc_event_picker_choice(1, "res://scenes/events/bomb_pot/bomb_pot_event.tscn")
	assert_eq(c.state.current_event_id, "",
		"non-picker submission ignored")

func test_rpc_event_picker_choice_rejects_invalid_path():
	# Picker submits a path NOT in options. Silently rejected.
	var d = _new_host()
	var c = d.controller
	c.state.current_event_id = ""
	c._rpc_event_picker_choice(2, "res://scenes/events/card_cannon/card_cannon_event.tscn")
	# Card Cannon is not in this test's options (only Rocket Clash + Bomb Pot)
	assert_eq(c.state.current_event_id, "",
		"out-of-options submission ignored")

func test_rpc_event_picker_choice_duplicate_submit_ignored():
	# Once a choice lands, subsequent submits from the picker do nothing.
	# Reason: state.current_event_id is locked once set.
	var d = _new_host()
	var c = d.controller
	c.state.current_event_id = ""
	c._rpc_event_picker_choice(2, "res://scenes/events/rocket_clash/rocket_clash_event.tscn")
	# Submit again with a different valid option
	c._rpc_event_picker_choice(2, "res://scenes/events/bomb_pot/bomb_pot_event.tscn")
	assert_eq(c.state.current_event_id,
		"res://scenes/events/rocket_clash/rocket_clash_event.tscn",
		"duplicate submit ignored; first pick wins")
