extends GutTest

const LoadoutOverlay = preload("res://scripts/ui/loadout_overlay.gd")

func test_can_drop_data_accepts_known_card_id():
	assert_true(LoadoutOverlay.can_drop_card("heat_shield", ["heat_shield", "wager_tax"]),
		"card_id present in hand is droppable")

func test_can_drop_data_rejects_unknown_payload():
	assert_false(LoadoutOverlay.can_drop_card("not_a_card", ["heat_shield", "wager_tax"]),
		"card_id not in hand is rejected")
	assert_false(LoadoutOverlay.can_drop_card("", ["heat_shield"]),
		"empty string payload is rejected")

func test_apply_drop_returns_new_loadout_with_card_in_slot():
	var loadout: Array = ["heat_shield", ""]
	var new_loadout = LoadoutOverlay.apply_drop(loadout, 1, "wager_tax")
	assert_eq(new_loadout, ["heat_shield", "wager_tax"],
		"drop in slot 1 places the card; slot 0 untouched")

func test_apply_drop_replaces_existing_slot_card():
	var loadout: Array = ["heat_shield", "wager_tax"]
	var new_loadout = LoadoutOverlay.apply_drop(loadout, 0, "insurance")
	assert_eq(new_loadout, ["insurance", "wager_tax"],
		"drop in a non-empty slot replaces the existing card")
