extends GutTest

const Announcer = preload("res://scripts/ui/announcer.gd")

func test_animation_timeline_returns_expected_durations():
	var t = Announcer.animation_timeline()
	assert_almost_eq(float(t.get("slide_in_sec", 0.0)), 0.3, 0.001)
	assert_almost_eq(float(t.get("hold_sec", 0.0)), 2.5, 0.001)
	assert_almost_eq(float(t.get("slide_out_sec", 0.0)), 0.3, 0.001)
	assert_almost_eq(float(t.get("total_sec", 0.0)), 3.1, 0.001,
		"slide_in + hold + slide_out sums to ~3.1s total")
