extends GutTest

const BetLoadoutOverlay = preload("res://scripts/ui/bet_loadout_overlay.gd")

func test_format_wager_summary_zero():
	assert_eq(BetLoadoutOverlay.format_wager_summary(800, 0), "Wager: 0 (Chips: 800)")

func test_format_wager_summary_partial():
	assert_eq(BetLoadoutOverlay.format_wager_summary(800, 200), "Wager: 200 (Chips: 800)")

func test_clamp_wager_within_range():
	assert_eq(BetLoadoutOverlay.clamp_wager(200, 800, 1.0), 200)

func test_clamp_wager_negative_to_zero():
	assert_eq(BetLoadoutOverlay.clamp_wager(-50, 800, 1.0), 0)

func test_clamp_wager_above_max_to_max():
	assert_eq(BetLoadoutOverlay.clamp_wager(5000, 800, 1.0), 800)
	assert_eq(BetLoadoutOverlay.clamp_wager(5000, 800, 0.5), 400)
