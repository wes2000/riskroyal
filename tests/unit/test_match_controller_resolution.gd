extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
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

func _new_controller_synchronous() -> MatchController:
	var c = MatchController.new(true, null)
	c.resolution_step_delay_ms_override = 0  # synchronous
	c.start_match(_build_match_start(2))
	return c

func _result_with_chips(p1_delta: int, p2_delta: int) -> RefCounted:
	var r = EventResult.new()
	r.per_player = {
		1: {"chip_delta": p1_delta, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 0.0},
		2: {"chip_delta": p2_delta, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 0.0},
	}
	return r

func test_resolution_emits_substeps_in_order():
	var c = _new_controller_synchronous()
	c.state.current_result = _result_with_chips(0, 0)
	c.state.phase = MatchPhase.Phase.RESOLUTION
	var steps: Array = []
	c.resolution_step.connect(func(name, _payload): steps.append(name))
	c._enter_phase_behavior()
	assert_eq(steps, ["busts", "cash_outs", "chip_changes", "crown_awards", "painful_reveal"])

func test_resolution_applies_chip_deltas():
	var c = _new_controller_synchronous()
	var pre_chips_p1 = c.state.players[0].chips
	var pre_chips_p2 = c.state.players[1].chips
	c.state.current_result = _result_with_chips(100, -50)
	c.state.phase = MatchPhase.Phase.RESOLUTION
	c._enter_phase_behavior()
	assert_eq(c.state.players[0].chips, pre_chips_p1 + 100)
	assert_eq(c.state.players[1].chips, pre_chips_p2 - 50)

func test_resolution_applies_crown_deltas():
	var c = _new_controller_synchronous()
	var r = EventResult.new()
	r.per_player = {
		1: {"chip_delta": 0, "crown_delta": 1, "heat_delta": 0, "bust": false, "cash_out_at": 0.0},
		2: {"chip_delta": 0, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 0.0},
	}
	c.state.current_result = r
	c.state.phase = MatchPhase.Phase.RESOLUTION
	c._enter_phase_behavior()
	assert_eq(c.state.players[0].crowns, 1)
	assert_eq(c.state.players[1].crowns, 0)

func test_resolution_emits_player_resources_changed_per_delta():
	var c = _new_controller_synchronous()
	c.state.current_result = _result_with_chips(10, -10)
	c.state.phase = MatchPhase.Phase.RESOLUTION
	var changed: Array = []
	c.player_resources_changed.connect(func(pid): changed.append(pid))
	c._enter_phase_behavior()
	# 2 chip_changes emissions + 0 crown_awards emissions (deltas were 0) = 2
	assert_eq(changed.size(), 2)

func test_resolution_advances_to_bounty_heat_update():
	var c = _new_controller_synchronous()
	c.state.current_result = _result_with_chips(0, 0)
	c.state.phase = MatchPhase.Phase.RESOLUTION
	c._enter_phase_behavior()
	# Synchronous delay -> immediately advances
	assert_eq(c.state.phase, MatchPhase.Phase.BOUNTY_HEAT_UPDATE)
