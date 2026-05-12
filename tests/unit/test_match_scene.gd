extends GutTest

const MatchScene = preload("res://scripts/ui/match_scene.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")

func test_format_phase_indicator_event_one_of_five():
	var s = MatchScene.format_phase_indicator(0, 5, MatchPhase.Phase.HOUSE_REVEAL)
	assert_true(s.contains("Event 1/5"))
	assert_true(s.contains("HOUSE_REVEAL"))

func test_format_phase_indicator_event_three_of_five():
	var s = MatchScene.format_phase_indicator(2, 5, MatchPhase.Phase.MAIN_EVENT)
	assert_true(s.contains("Event 3/5"))
	assert_true(s.contains("MAIN_EVENT"))

func test_format_phase_indicator_match_end():
	var s = MatchScene.format_phase_indicator(4, 5, MatchPhase.Phase.MATCH_END)
	assert_true(s.contains("Match End"))

func test_format_phase_indicator_unknown_phase():
	var s = MatchScene.format_phase_indicator(0, 5, 999)
	assert_true(s.contains("UNKNOWN"))
