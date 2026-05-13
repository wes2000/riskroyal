extends GutTest

const ShopOverlay = preload("res://scripts/ui/shop_overlay.gd")

func test_format_shop_offer_returns_per_card_dicts():
	var offered = ["insurance", "heat_shield", "multiplier_booster"]
	var formatted = ShopOverlay.format_shop_offer(offered)
	assert_eq(formatted.size(), 3)
	assert_eq(formatted[0].card_id, "insurance")
	assert_eq(formatted[0].name, "Insurance")
	assert_eq(formatted[0].cost, 50)

func test_can_afford_true_when_chips_meet_cost():
	assert_true(ShopOverlay.can_afford(50, 50))
	assert_true(ShopOverlay.can_afford(100, 50))

func test_can_afford_false_when_chips_less_than_cost():
	assert_false(ShopOverlay.can_afford(49, 50))

func test_format_summary_uses_chip_count():
	# Static-formatter style: summary text depends on chip count, so a
	# polled refresh against fresh chip value produces fresh text.
	var s1 = ShopOverlay.format_summary_text(3, 100)
	var s2 = ShopOverlay.format_summary_text(3, 250)
	assert_ne(s1, s2, "summary text reflects live chip count")
	assert_true(s1.contains("100"))
	assert_true(s2.contains("250"))
