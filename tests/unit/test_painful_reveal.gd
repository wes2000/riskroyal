extends GutTest

const PainfulReveal = preload("res://scripts/ui/painful_reveal.gd")

func test_format_bust_reveal():
	var s = PainfulReveal.format_bust_reveal("P2", 100)
	assert_string_contains(s, "P2")
	assert_string_contains(s, "LOST")
	assert_string_contains(s, "100")

func test_format_crown_reveal_single():
	var s = PainfulReveal.format_crown_reveal("P3", 1)
	assert_string_contains(s, "P3")
	assert_string_contains(s, "+1 CROWN")

func test_format_crown_reveal_stacked():
	var s = PainfulReveal.format_crown_reveal("P3", 2)
	assert_string_contains(s, "P3")
	assert_string_contains(s, "+2 CROWN")

func test_format_bust_reveal_has_color_blind_icon_prefix():
	var s = PainfulReveal.format_bust_reveal("P2", 100)
	assert_string_contains(s, "✗", "bust reveal has X-mark icon")
	assert_string_contains(s, "↓", "chip-loss arrow suffix")

func test_format_crown_reveal_has_color_blind_icon_prefix():
	var s = PainfulReveal.format_crown_reveal("P3", 1)
	assert_string_contains(s, "👑", "crown reveal has crown icon")
