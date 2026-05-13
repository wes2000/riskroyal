extends GutTest

const MatchConfig = preload("res://scripts/match/match_config.gd")

# Bomb Pot constants

func test_bomb_pot_pot_growth_per_sec():
	assert_almost_eq(MatchConfig.BOMB_POT_POT_GROWTH_PER_SEC, 50.0, 0.001)

func test_bomb_pot_min_detonation_sec():
	assert_almost_eq(MatchConfig.BOMB_POT_MIN_DETONATION_SEC, 5.0, 0.001)

func test_bomb_pot_max_detonation_sec():
	assert_almost_eq(MatchConfig.BOMB_POT_MAX_DETONATION_SEC, 25.0, 0.001)

func test_bomb_pot_instabust_prob():
	assert_almost_eq(MatchConfig.BOMB_POT_INSTABUST_PROB, 0.05, 0.001)

# Card Cannon constants

func test_card_cannon_target_score():
	assert_eq(MatchConfig.CARD_CANNON_TARGET_SCORE, 21)

func test_card_cannon_payout_band_low():
	assert_almost_eq(MatchConfig.CARD_CANNON_PAYOUT_BAND_LOW, 0.5, 0.001)

func test_card_cannon_payout_band_medium():
	assert_almost_eq(MatchConfig.CARD_CANNON_PAYOUT_BAND_MEDIUM, 1.0, 0.001)

func test_card_cannon_payout_band_strong():
	assert_almost_eq(MatchConfig.CARD_CANNON_PAYOUT_BAND_STRONG, 1.5, 0.001)

func test_card_cannon_payout_band_heavy():
	assert_almost_eq(MatchConfig.CARD_CANNON_PAYOUT_BAND_HEAVY, 2.0, 0.001)

func test_card_cannon_payout_band_perfect():
	assert_almost_eq(MatchConfig.CARD_CANNON_PAYOUT_BAND_PERFECT, 3.0, 0.001)
