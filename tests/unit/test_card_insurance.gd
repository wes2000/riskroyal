extends GutTest

const Insurance = preload("res://scripts/cards/effects/insurance.gd")

func test_insurance_meta_is_defense_common_bet_loadout():
	var m = Insurance.CARD_META
	assert_eq(m.name, "Insurance")
	assert_eq(m.rarity, "common")
	assert_eq(m.category, "defense")
	assert_eq(m.timing, "bet_loadout")
	assert_eq(m.target_required, false)
	assert_eq(m.cost_chips, 50)

func test_insurance_apply_returns_insurance_pre():
	var result = Insurance.apply(null, 0, null)
	assert_true(result.applied)
	assert_eq(result.type, "insurance_pre")
