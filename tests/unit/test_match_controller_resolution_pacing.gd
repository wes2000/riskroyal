extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")
const EventResult = preload("res://scripts/events/event_result.gd")
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

func _new_controller(delay_override: int) -> MatchController:
	var c = MatchController.new(true, null)
	c.no_op_phase_delay_ms_override = 0  # don't pace no-op phases in tests
	c.resolution_step_delay_ms_override = delay_override
	c.start_match(_build_match_start(2))
	return c

func test_resolution_synchronous_when_override_zero():
	# delay 0 → no awaits; pipeline completes within the call.
	var c = _new_controller(0)
	c.state.current_result = EventResult.new()
	c.state.phase = MatchPhase.Phase.RESOLUTION
	await c._process_resolution_phase()
	# After pipeline, BOUNTY_HEAT_UPDATE handler will have run (also no-op
	# delay 0) and chained through. Just assert phase is past RESOLUTION.
	assert_ne(c.state.phase, MatchPhase.Phase.RESOLUTION)

func test_resolution_resolution_step_emits_substeps_in_order_with_paced_delay():
	# With override=10ms, the pipeline emits 5 substeps with 4 timer awaits
	# between them. Verify order is preserved.
	var c = _new_controller(10)
	c.state.current_result = EventResult.new()
	c.state.phase = MatchPhase.Phase.RESOLUTION
	var steps: Array = []
	c.resolution_step.connect(func(name, _payload): steps.append(name))
	await c._process_resolution_phase()
	assert_eq(steps, ["busts", "cash_outs", "chip_changes", "crown_awards", "painful_reveal"])

func test_resolution_uses_match_config_when_override_negative():
	# override=-1 → use MatchConfig.RESOLUTION_STEP_DELAY_MS. We can't time
	# the run in a test, but we can verify the controller picks the right
	# delay value via _resolution_step_delay_ms() helper.
	var c = _new_controller(-1)
	assert_eq(c._resolution_step_delay_ms(), MatchConfig.RESOLUTION_STEP_DELAY_MS)
