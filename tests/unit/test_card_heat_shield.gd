extends GutTest

const HeatShield = preload("res://scripts/cards/effects/heat_shield.gd")

func test_heat_shield_meta():
	var m = HeatShield.CARD_META
	assert_eq(m.name, "Heat Shield")
	assert_eq(m.rarity, "common")
	assert_eq(m.category, "defense")
	assert_eq(m.timing, "bet_loadout")
	assert_eq(m.target_required, false)

func test_heat_shield_apply():
	var result = HeatShield.apply(null, 0, null)
	assert_true(result.applied)
	assert_eq(result.type, "heat_shield")
