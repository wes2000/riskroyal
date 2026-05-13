extends GutTest

const EmergencyEject = preload("res://scripts/cards/effects/emergency_eject.gd")

func test_eject_meta():
	var m = EmergencyEject.CARD_META
	assert_eq(m.name, "Emergency Eject")
	assert_eq(m.rarity, "rare")
	assert_eq(m.category, "defense")
	assert_eq(m.timing, "bet_loadout")
	assert_eq(m.target_required, false)
	assert_eq(m.cost_chips, 150)

func test_apply_returns_auto_eject_loaded():
	var result = EmergencyEject.apply(null, 0, null)
	assert_true(result.applied)
	assert_eq(result.type, "auto_eject_loaded")
	assert_eq(result.threshold, 3.0)
