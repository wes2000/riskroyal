extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MockEvent = preload("res://tests/fakes/mock_event.gd")
const EventResult = preload("res://scripts/events/event_result.gd")
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

func _new_host_with_fake() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.resolution_step_delay_ms_override = 0
	return {"controller": c, "fake": fake}

func _rpc_methods_called(fake) -> Array:
	var out: Array = []
	for call in fake.rpc_calls:
		out.append(call.method)
	return out

func test_start_match_emits_rpc_phase_changed():
	var d = _new_host_with_fake()
	d.controller.start_match(_build_match_start(2))
	var methods = _rpc_methods_called(d.fake)
	assert_true("_rpc_phase_changed" in methods, "phase_changed broadcast on start")

func test_ante_emits_rpc_apply_deltas():
	var d = _new_host_with_fake()
	d.controller.start_match(_build_match_start(2))
	var methods = _rpc_methods_called(d.fake)
	var apply_deltas_count = 0
	for m in methods:
		if m == "_rpc_apply_deltas":
			apply_deltas_count += 1
	assert_gt(apply_deltas_count, 0, "ante deltas broadcast")

func test_resolution_pipeline_emits_rpc_resolution_step_per_substep():
	var d = _new_host_with_fake()
	d.controller.start_match(_build_match_start(2))
	d.fake.rpc_calls.clear()  # reset after start_match noise
	d.controller.state.current_result = EventResult.new()
	d.controller.state.phase = MatchPhase.Phase.RESOLUTION
	await d.controller._process_resolution_phase()
	var step_calls = 0
	for c in d.fake.rpc_calls:
		if c.method == "_rpc_resolution_step":
			step_calls += 1
	assert_eq(step_calls, 5, "five substeps broadcast")

func test_match_end_emits_rpc_match_ended():
	var d = _new_host_with_fake()
	d.controller.start_match(_build_match_start(2))
	d.fake.rpc_calls.clear()
	d.controller.state.phase = MatchPhase.Phase.MATCH_END
	d.controller._enter_phase_behavior()
	var methods = _rpc_methods_called(d.fake)
	assert_true("_rpc_match_ended" in methods)

func test_joiner_does_not_emit_rpcs():
	# Non-host controller should not broadcast.
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(false, fake)
	c.start_match(_build_match_start(2))  # no-op for non-host
	assert_eq(fake.rpc_calls.size(), 0, "non-host doesn't broadcast")
