extends GutTest

const MatchScene = preload("res://scripts/ui/match_scene.gd")

func test_compute_loadout_from_drop_replaces_slot_0():
	var current_loadout: Array = ["heat_shield", "wager_tax"]
	var out = MatchScene.compute_loadout_from_drop(current_loadout, 0, "insurance")
	assert_eq(out, ["insurance", "wager_tax"])

func test_compute_loadout_from_drop_fills_empty_slot():
	var current_loadout: Array = ["heat_shield"]
	var out = MatchScene.compute_loadout_from_drop(current_loadout, 1, "wager_tax")
	assert_eq(out, ["heat_shield", "wager_tax"])
