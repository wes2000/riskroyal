extends GutTest

const EventPickerOverlay = preload("res://scripts/ui/event_picker_overlay.gd")

func test_format_event_button_label_per_event_id():
	assert_eq(EventPickerOverlay.format_event_button_label(
		"res://scenes/events/rocket_clash/rocket_clash_event.tscn"), "Rocket Clash")
	assert_eq(EventPickerOverlay.format_event_button_label(
		"res://scenes/events/bomb_pot/bomb_pot_event.tscn"), "Bomb Pot")
	assert_eq(EventPickerOverlay.format_event_button_label(
		"res://scenes/events/card_cannon/card_cannon_event.tscn"), "Card Cannon")
	assert_eq(EventPickerOverlay.format_event_button_label(""), "")

func test_format_waiting_banner_includes_picker_name():
	assert_eq(EventPickerOverlay.format_waiting_banner("P2"),
		"Waiting for P2 to pick the next event...")
	assert_eq(EventPickerOverlay.format_waiting_banner(""),
		"Waiting for the picker to choose...")
