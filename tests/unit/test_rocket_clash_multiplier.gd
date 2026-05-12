extends GutTest

const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")

func test_multiplier_at_zero_elapsed():
	assert_almost_eq(RocketClashEvent.multiplier_at(0, 0.06), 1.0, 0.001)

func test_multiplier_at_10_seconds():
	# exp(0.06 * 10) = e^0.6 ≈ 1.8221
	assert_almost_eq(RocketClashEvent.multiplier_at(10_000, 0.06), 1.8221, 0.01)

func test_multiplier_monotonic_increasing():
	var prev = 1.0
	for sec in range(1, 60):
		var m = RocketClashEvent.multiplier_at(sec * 1000, 0.06)
		assert_true(m > prev, "monotonic at %ds: %f vs %f" % [sec, m, prev])
		prev = m
