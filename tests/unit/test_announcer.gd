extends GutTest

const Announcer = preload("res://scripts/ui/announcer.gd")

func test_format_twist_text():
	var s = Announcer.format_twist_text({"type": "double_bounty"})
	assert_string_contains(s, "HOUSE TWIST")
	assert_string_contains(s, "Double Bounty")

func test_format_twist_text_empty_returns_empty():
	var s = Announcer.format_twist_text({"type": ""})
	assert_eq(s, "")

func test_format_bust_text():
	var s = Announcer.format_bust_text("P2", 100)
	assert_string_contains(s, "P2")
	assert_string_contains(s, "EJECTED")
	assert_string_contains(s, "100")

func test_format_crown_text():
	var s = Announcer.format_crown_text("P3", 1)
	assert_string_contains(s, "P3")
	assert_string_contains(s, "CROWN")

func test_format_match_outcome_text():
	var s = Announcer.format_match_outcome_text(1, "P1")
	assert_string_contains(s, "P1")
	assert_string_contains(s, "WINS")

func test_format_bust_text_has_color_blind_icon_prefix():
	var s = Announcer.format_bust_text("P2", 100)
	assert_string_contains(s, "✗", "bust message has X-mark icon for color-blind cue")

func test_format_crown_text_has_color_blind_icon_prefix():
	var s = Announcer.format_crown_text("P3", 1)
	assert_string_contains(s, "👑", "crown message has crown icon for color-blind cue")
