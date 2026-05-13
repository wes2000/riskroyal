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

func test_all_12_cards_registered():
	# Plan A registered 6; Plan B adds 6.
	var expected = [
		"insurance", "heat_shield", "multiplier_booster",
		"double_or_nothing", "late_cash", "underdog_odds",
		"heat_spike", "wager_tax", "place_bounty",
		"copycat_bet", "cash_out_jammer", "emergency_eject",
	]
	for id in expected:
		var card = CardRegistry.get_card(id)
		assert_false(card.is_empty(), "card %s should be registered" % id)

func test_shop_pool_includes_all_12():
	var pool = CardRegistry.shop_pool()
	assert_eq(pool.size(), 12)

func test_starter_pool_excludes_sabotage_after_plan_b():
	# Heat Spike + Wager Tax are sabotage commons; must be excluded.
	var pool = CardRegistry.starter_pool()
	assert_false("heat_spike" in pool, "Heat Spike (sabotage) excluded from starter pack")
	assert_false("wager_tax" in pool, "Wager Tax (sabotage) excluded from starter pack")
