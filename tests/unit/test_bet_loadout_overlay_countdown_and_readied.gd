extends GutTest

const BetLoadoutOverlay = preload("res://scripts/ui/bet_loadout_overlay.gd")

func test_format_countdown_renders_seconds_remaining():
	assert_eq(BetLoadoutOverlay.format_countdown(15), "[15s]")
	assert_eq(BetLoadoutOverlay.format_countdown(1), "[1s]")
	assert_eq(BetLoadoutOverlay.format_countdown(0), "")

func test_format_readied_chip_marks_readied_peers():
	assert_eq(BetLoadoutOverlay.format_readied_chip(2, [2, 3]), "✓ P2",
		"P2 in readied set should show check mark")
	assert_eq(BetLoadoutOverlay.format_readied_chip(2, [3]), "P2",
		"P2 not in readied set should render plain")
	assert_eq(BetLoadoutOverlay.format_readied_chip(2, []), "P2",
		"empty readied set means no one ready yet")
