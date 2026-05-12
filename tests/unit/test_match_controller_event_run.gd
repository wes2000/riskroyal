extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MockEvent = preload("res://tests/fakes/mock_event.gd")
const EventResult = preload("res://scripts/events/event_result.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start(player_count: int) -> RefCounted:
	var ms = MatchStart.new()
	for i in player_count:
		var s = PlayerSlot.new()
		s.peer_id = i + 1; s.seat_index = i; s.name = "P%d" % (i + 1)
		ms.seats.append(s)
	ms.host_peer_id = 1; ms.rng_seed = 0xCAFE
	return ms

func _new_controller_with_mock() -> Dictionary:
	var c = MatchController.new(true, null)
	var mock = MockEvent.new()
	# Inject the factory so MatchController uses the mock instead of loading a scene.
	c._event_factory = func(_path): return mock
	c.start_match(_build_match_start(2))
	# start_match cascades into MAIN_EVENT via the scheduler; the mock._run
	# was called once and event_complete was connected. Reset so each test
	# starts from a clean state: no stale event node or run_call entries.
	if c._current_event_node != null and is_instance_valid(c._current_event_node):
		c._current_event_node.queue_free()
	c._current_event_node = null
	var on_complete = Callable(c, "_on_event_complete")
	if mock.event_complete.is_connected(on_complete):
		mock.event_complete.disconnect(on_complete)
	mock.run_calls.clear()
	return {"controller": c, "mock": mock}

func test_event_selection_picks_from_pool():
	var d = _new_controller_with_mock()
	var c = d.controller
	c.state.phase = MatchPhase.Phase.EVENT_SELECTION
	c._enter_phase_behavior()
	assert_eq(c.state.current_event_id, "res://scripts/events/test_event/test_event.tscn")

func test_main_event_instantiates_via_factory_and_calls_run():
	var d = _new_controller_with_mock()
	var c = d.controller
	var mock = d.mock
	c.state.current_event_id = "res://scripts/events/test_event/test_event.tscn"
	c.state.phase = MatchPhase.Phase.MAIN_EVENT
	c._enter_phase_behavior()
	assert_eq(mock.run_calls.size(), 1, "_run called once with context")
	var ctx = mock.run_calls[0]
	assert_eq(ctx.event_index, 0)
	assert_eq(ctx.players.size(), 2)

func test_event_complete_stores_result_and_advances_past_main_event():
	var d = _new_controller_with_mock()
	var c = d.controller
	var mock = d.mock
	c.state.current_event_id = "res://scripts/events/test_event/test_event.tscn"
	c.state.phase = MatchPhase.Phase.MAIN_EVENT
	# Set event_index to final slot so the post-RESOLUTION cascade terminates
	# at MATCH_END rather than looping back to MAIN_EVENT.
	c.state.event_index = 4
	c._enter_phase_behavior()
	# Now drive event completion.
	var result = EventResult.new()
	result.event_id = "mock_event"
	mock.emit_complete(result)
	# RESOLUTION pipeline runs, cascades through BOUNTY_HEAT_UPDATE -> SHOP ->
	# HOUSE_TWIST (final) -> MATCH_END. current_result was stored by
	# _on_event_complete; assert it's still the mock result.
	assert_ne(c.state.phase, MatchPhase.Phase.MAIN_EVENT)
	assert_eq(c.state.current_result, result)

func test_event_starting_signal_fired():
	var d = _new_controller_with_mock()
	var c = d.controller
	var starts: Array = []
	c.event_starting.connect(func(eid, idx): starts.append([eid, idx]))
	c.state.current_event_id = "res://scripts/events/test_event/test_event.tscn"
	c.state.phase = MatchPhase.Phase.MAIN_EVENT
	c._enter_phase_behavior()
	assert_eq(starts.size(), 1)
	assert_eq(starts[0][1], 0)

func test_context_includes_only_active_players():
	var d = _new_controller_with_mock()
	var c = d.controller
	c.state.players[0].is_active_this_event = false  # P1 sat out ante
	c.state.current_event_id = "res://scripts/events/test_event/test_event.tscn"
	c.state.phase = MatchPhase.Phase.MAIN_EVENT
	c._enter_phase_behavior()
	var ctx = d.mock.run_calls[0]
	assert_eq(ctx.players.size(), 1)
	assert_eq(ctx.players[0].peer_id, 2)
