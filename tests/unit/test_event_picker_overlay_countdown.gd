extends GutTest

const EventPickerOverlay = preload("res://scripts/ui/event_picker_overlay.gd")

func test_format_countdown_renders_remaining():
	assert_eq(EventPickerOverlay.format_countdown(10), "[10s]")
	assert_eq(EventPickerOverlay.format_countdown(1), "[1s]")
	assert_eq(EventPickerOverlay.format_countdown(0), "")
