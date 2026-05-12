extends GutTest

const MatchConfig = preload("res://scripts/match/match_config.gd")

func test_no_op_phase_delay_ms_default():
	assert_eq(MatchConfig.NO_OP_PHASE_DELAY_MS, 300)
