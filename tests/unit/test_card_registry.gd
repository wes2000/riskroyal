extends GutTest

const CardRegistry = preload("res://scripts/cards/card_registry.gd")

func test_heat_multiplier_quiet():
	assert_almost_eq(CardRegistry.heat_multiplier(0), 1.0, 0.001)
	assert_almost_eq(CardRegistry.heat_multiplier(2), 1.0, 0.001)

func test_heat_multiplier_noticed():
	assert_almost_eq(CardRegistry.heat_multiplier(3), 1.25, 0.001)
	assert_almost_eq(CardRegistry.heat_multiplier(5), 1.25, 0.001)

func test_heat_multiplier_hot_seat():
	assert_almost_eq(CardRegistry.heat_multiplier(6), 1.5, 0.001)
	assert_almost_eq(CardRegistry.heat_multiplier(8), 1.5, 0.001)

func test_heat_multiplier_public_enemy():
	assert_almost_eq(CardRegistry.heat_multiplier(9), 2.0, 0.001)
	assert_almost_eq(CardRegistry.heat_multiplier(10), 2.0, 0.001)

func test_get_card_unknown_returns_empty():
	assert_eq(CardRegistry.get_card("nonexistent"), {})
