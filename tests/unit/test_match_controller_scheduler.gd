extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")

func test_no_op_phase_delay_override_default():
	var c = MatchController.new(true, null)
	assert_eq(c.no_op_phase_delay_ms_override, -1, "default: use MatchConfig value")

func test_schedule_advance_synchronous_when_override_zero():
	# With override=0, the helper should call _advance_phase synchronously.
	var c = MatchController.new(true, null)
	c.no_op_phase_delay_ms_override = 0
	c.state.phase = MatchPhase.Phase.HOUSE_REVEAL
	await c._schedule_advance()
	assert_eq(c.state.phase, MatchPhase.Phase.ANTE, "should advance synchronously")
