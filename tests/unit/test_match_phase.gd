extends GutTest

const MatchPhase = preload("res://scripts/match/match_phase.gd")

func test_phase_enum_values():
	assert_eq(MatchPhase.Phase.HOUSE_REVEAL, 0)
	assert_eq(MatchPhase.Phase.ANTE, 1)
	assert_eq(MatchPhase.Phase.EVENT_SELECTION, 2)
	assert_eq(MatchPhase.Phase.BET_LOADOUT, 3)
	assert_eq(MatchPhase.Phase.MAIN_EVENT, 4)
	assert_eq(MatchPhase.Phase.RESOLUTION, 5)
	assert_eq(MatchPhase.Phase.BOUNTY_HEAT_UPDATE, 6)
	assert_eq(MatchPhase.Phase.SHOP, 7)
	assert_eq(MatchPhase.Phase.HOUSE_TWIST, 8)
	assert_eq(MatchPhase.Phase.MATCH_END, 9)

func test_phase_name_returns_string():
	assert_eq(MatchPhase.name_for(MatchPhase.Phase.ANTE), "ANTE")
	assert_eq(MatchPhase.name_for(MatchPhase.Phase.MAIN_EVENT), "MAIN_EVENT")
	assert_eq(MatchPhase.name_for(-1), "UNKNOWN")
