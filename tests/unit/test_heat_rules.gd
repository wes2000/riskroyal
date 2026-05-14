extends GutTest

const HeatRules = preload("res://scripts/match/heat_rules.gd")

# --- Rocket Clash heat scaling ---

func test_rocket_heat_10x_legendary():
	assert_eq(HeatRules.rocket_heat(10.0, true), 4)

func test_rocket_heat_5x_greedy():
	assert_eq(HeatRules.rocket_heat(5.0, true), 3)

func test_rocket_heat_2_5x_solid():
	assert_eq(HeatRules.rocket_heat(2.5, true), 2)

func test_rocket_heat_low_winner_just_safe():
	assert_eq(HeatRules.rocket_heat(1.5, true), 1, "winning but low cash-out = 1 Heat")

func test_rocket_heat_low_non_winner():
	assert_eq(HeatRules.rocket_heat(1.5, false), 0, "non-winning low cash-out = 0 Heat")

# --- Bomb Pot heat scaling ---

func test_bomb_pot_heat_95_percent_legendary():
	# 9.5s of 10s bomb -> ratio 0.95
	assert_eq(HeatRules.bomb_pot_heat(9500, 10.0, true, 200), 4)

func test_bomb_pot_heat_80_percent_late_pull():
	assert_eq(HeatRules.bomb_pot_heat(8000, 10.0, true, 200), 3)

func test_bomb_pot_heat_winner_low_ratio():
	# Won the crown but pulled early (50% ratio)
	assert_eq(HeatRules.bomb_pot_heat(5000, 10.0, true, 100), 2)

func test_bomb_pot_heat_non_winner_with_share():
	assert_eq(HeatRules.bomb_pot_heat(5000, 10.0, false, 100), 1)

func test_bomb_pot_heat_busted():
	# Did not pull (or busted) -> 0
	assert_eq(HeatRules.bomb_pot_heat(0, 10.0, false, 0), 0)

# --- Card Cannon heat scaling ---

func test_card_cannon_heat_perfect_21():
	assert_eq(HeatRules.card_cannon_heat(21, true), 3)

func test_card_cannon_heat_high_lock():
	assert_eq(HeatRules.card_cannon_heat(19, true), 2)

func test_card_cannon_heat_low_winner():
	assert_eq(HeatRules.card_cannon_heat(15, true), 1)

func test_card_cannon_heat_non_winner():
	assert_eq(HeatRules.card_cannon_heat(17, false), 0)

# --- Heat Shield ---

func test_apply_heat_shield_halves_base():
	assert_eq(HeatRules.apply_heat_shield(4, {"heat_shield": true}), 2)

func test_apply_heat_shield_floors_odd():
	# floor(3/2) = 1
	assert_eq(HeatRules.apply_heat_shield(3, {"heat_shield": true}), 1)

func test_apply_heat_shield_no_modifier_returns_base():
	assert_eq(HeatRules.apply_heat_shield(4, {}), 4)
