extends GutTest

const LateCash = preload("res://scripts/cards/effects/late_cash.gd")

func test_late_cash_meta():
	var m = LateCash.CARD_META
	assert_eq(m.name, "Late Cash")
	assert_eq(m.rarity, "common")
	assert_eq(m.category, "greed")
	assert_eq(m.timing, "bet_loadout")

func test_late_cash_apply():
	var result = LateCash.apply(null, 0, null)
	assert_true(result.applied)
	assert_eq(result.type, "late_cash_bonus")
	assert_almost_eq(float(result.threshold), 5.0, 0.001)
	assert_eq(result.bonus_chips, 200)
