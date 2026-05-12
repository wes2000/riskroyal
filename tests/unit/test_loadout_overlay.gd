extends GutTest

const LoadoutOverlay = preload("res://scripts/ui/loadout_overlay.gd")

func test_format_card_label_known():
	var s = LoadoutOverlay.format_card_label("insurance")
	assert_eq(s, "Insurance")

func test_format_card_label_unknown():
	var s = LoadoutOverlay.format_card_label("nonexistent")
	assert_eq(s, "?")

func test_is_card_playable_in_bet_loadout_window():
	# Insurance is bet_loadout timing; phase BET_LOADOUT (3 per MatchPhase enum)
	var played: Array = []
	assert_true(LoadoutOverlay.is_card_playable("insurance", 3, played))

func test_is_card_playable_outside_window():
	var played: Array = []
	# MAIN_EVENT phase (4 per enum)
	assert_false(LoadoutOverlay.is_card_playable("insurance", 4, played))

func test_is_card_playable_already_played():
	var played: Array = ["insurance"]
	assert_false(LoadoutOverlay.is_card_playable("insurance", 3, played))
