extends GutTest

const ResolutionOverlay = preload("res://scripts/ui/resolution_overlay.gd")

func test_crown_stack_animation_timeline():
	var t = ResolutionOverlay.crown_stack_animation_timeline()
	assert_almost_eq(float(t.get("first_crown_fade_sec", 0.0)), 0.0, 0.001,
		"first crown is rendered immediately by the existing path")
	assert_almost_eq(float(t.get("delay_sec", 0.0)), 0.3, 0.001)
	assert_almost_eq(float(t.get("second_crown_slide_sec", 0.0)), 0.4, 0.001)
	assert_almost_eq(float(t.get("suffix_fade_sec", 0.0)), 0.3, 0.001)
	assert_almost_eq(float(t.get("total_sec", 0.0)), 0.3 + 0.4 + 0.3, 0.001)
