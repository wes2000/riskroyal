extends GutTest

const ResolutionOverlay = preload("res://scripts/ui/resolution_overlay.gd")

func test_crown_awards_one_renders_plain():
	var payload = {"deltas": [{"peer_id": 2, "delta": 1}]}
	var s = ResolutionOverlay.format_resolution_step("crown_awards", payload)
	assert_string_contains(s, "P2 gets 1 Crown",
		"single Crown renders as the existing plain format")

func test_crown_awards_two_renders_sudden_death_stack():
	var payload = {"deltas": [{"peer_id": 2, "delta": 2}]}
	var s = ResolutionOverlay.format_resolution_step("crown_awards", payload)
	assert_string_contains(s, "P2 gets 👑👑 2 CROWNS",
		"crown_delta == 2 renders the Sudden Death stack visually distinct")
	assert_string_contains(s, "Sudden Death",
		"label includes the source attribution")
