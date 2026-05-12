extends GutTest

const MatchConfig = preload("res://scripts/match/match_config.gd")

func test_bet_loadout_timeout_sec():
	assert_eq(MatchConfig.BET_LOADOUT_TIMEOUT_SEC, 15)

func test_rocket_clash_max_wager_factor():
	assert_eq(MatchConfig.ROCKET_CLASH_MAX_WAGER_FACTOR, 1.0)

func test_rocket_growth_rate():
	assert_almost_eq(MatchConfig.ROCKET_GROWTH_RATE, 0.06, 0.001)
