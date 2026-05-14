extends GutTest

const PainfulReveal = preload("res://scripts/ui/painful_reveal.gd")

func test_bust_animation_timeline():
	var t = PainfulReveal.bust_animation_timeline()
	assert_almost_eq(float(t.get("snap_in_sec", 0.0)), 0.15, 0.001)
	assert_almost_eq(float(t.get("settle_sec", 0.0)), 0.1, 0.001)
	assert_almost_eq(float(t.get("shake_sec", 0.0)), 0.2, 0.001)
	assert_almost_eq(float(t.get("hold_sec", 0.0)), 1.2, 0.001)
	assert_almost_eq(float(t.get("fade_sec", 0.0)), 0.3, 0.001)
	assert_almost_eq(float(t.get("total_sec", 0.0)), 0.15 + 0.1 + 1.2 + 0.3, 0.001)

func test_crown_animation_timeline():
	var t = PainfulReveal.crown_animation_timeline()
	assert_almost_eq(float(t.get("sparkle_sec", 0.0)), 0.2, 0.001)
	assert_almost_eq(float(t.get("pulse_sec", 0.0)), 0.6, 0.001)
	assert_almost_eq(float(t.get("fade_sec", 0.0)), 0.3, 0.001)
	assert_almost_eq(float(t.get("total_sec", 0.0)), 0.2 + 0.6 + 0.3, 0.001)
