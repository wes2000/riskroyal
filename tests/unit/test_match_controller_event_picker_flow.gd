extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")
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

func _new_controller() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.event_picker_timeout_sec_override = 0.0  # bypass timer entirely in this test
	c.start_match(_build_match_start(2))
	return {"controller": c, "fake": fake}

func test_event_selection_no_twist_uses_existing_no_repeat_path():
	# Plan A path untouched: no twist → uniform pick with no-repeat filter.
	var d = _new_controller()
	var c = d.controller
	c.state.house_twist = {}
	c.state.previous_event_id = ""
	c._process_event_selection()
	assert_true(MatchConfig.EVENT_POOL.has(c.state.current_event_id),
		"non-twist path picks a valid event_id")
	assert_eq(c.state.current_event_id, c.state.previous_event_id,
		"non-twist path sets previous_event_id")

func test_event_selection_lowest_chips_picks_broadcasts_picker_started():
	# Twist active → broadcasts _rpc_event_picker_started and does NOT
	# eagerly set state.current_event_id (deferred to picker submit or
	# timeout).
	var d = _new_controller()
	var c = d.controller
	c.state.house_twist = {
		"type": "lowest_chips_picks",
		"params": {
			"picker_peer_id": 2,
			"options": [
				"res://scenes/events/rocket_clash/rocket_clash_event.tscn",
				"res://scenes/events/bomb_pot/bomb_pot_event.tscn",
				"res://scenes/events/card_cannon/card_cannon_event.tscn",
			],
			"timeout_sec": 10,
		},
	}
	d.fake.rpc_calls.clear()
	c._process_event_selection()
	# Verify the broadcast went out
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_event_picker_started":
			found = true
			assert_eq(int(call.args[0]), 2, "picker_peer_id forwarded")
			assert_eq(call.args[1].size(), 3, "options forwarded with 3 entries")
			break
	assert_true(found, "_rpc_event_picker_started broadcast")

func test_event_selection_lowest_chips_picks_timeout_fallback_picks_from_options():
	# Same setup, but the timer (override=0.0) bypasses immediately and
	# host should pick uniformly from options + broadcast resolved.
	var d = _new_controller()
	var c = d.controller
	c.state.rng.seed = 42
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
	d.fake.rpc_calls.clear()
	await c._process_event_selection()
	# Host fallback should have set state.current_event_id from options
	assert_true(c.state.house_twist.params.options.has(c.state.current_event_id),
		"timeout fallback picks from options")
	# And broadcast _rpc_event_picker_resolved with reason="timeout"
	var resolved_call = null
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_event_picker_resolved":
			resolved_call = call
			break
	assert_true(resolved_call != null, "_rpc_event_picker_resolved broadcast")
	assert_eq(String(resolved_call.args[1]), "timeout",
		"reason=timeout on host fallback")
