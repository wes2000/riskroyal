extends GutTest

const MultiplierBooster = preload("res://scripts/cards/effects/multiplier_booster.gd")

func test_multiplier_booster_meta_is_rare_greed():
	var m = MultiplierBooster.CARD_META
	assert_eq(m.name, "Multiplier Booster")
	assert_eq(m.rarity, "rare")
	assert_eq(m.category, "greed")
	assert_eq(m.timing, "bet_loadout")
	assert_eq(m.cost_chips, 150)

func test_multiplier_booster_apply_returns_125_factor():
	var result = MultiplierBooster.apply(null, 0, null)
	assert_true(result.applied)
	assert_eq(result.type, "wager_multiplier")
	assert_almost_eq(float(result.multiplier), 1.25, 0.001)
