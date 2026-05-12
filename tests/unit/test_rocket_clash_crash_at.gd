extends GutTest

const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")

func _seeded_rng(seed_value: int) -> RandomNumberGenerator:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

func test_crash_at_deterministic_with_seed():
	var rng1 = _seeded_rng(0xCAFE)
	var rng2 = _seeded_rng(0xCAFE)
	assert_almost_eq(RocketClashEvent.compute_crash_at(rng1), RocketClashEvent.compute_crash_at(rng2), 0.001, "same seed -> same crash")

func test_crash_at_minimum_1_00():
	var rng = _seeded_rng(1)
	for i in 500:
		var c = RocketClashEvent.compute_crash_at(rng)
		assert_true(c >= 1.0, "crash_at must be >= 1.0 (got %f)" % c)

func test_crash_at_capped_at_100():
	var rng = _seeded_rng(1)
	for i in 500:
		var c = RocketClashEvent.compute_crash_at(rng)
		assert_true(c <= 100.0, "crash_at must be <= 100.0 (got %f)" % c)

func test_crash_at_distribution_has_instabust():
	# Verify ~5% of samples hit exactly 1.0 (the instabust gate).
	var rng = _seeded_rng(0xBEEF)
	var instabust_count = 0
	var total = 2000
	for i in total:
		var c = RocketClashEvent.compute_crash_at(rng)
		if abs(c - 1.0) < 0.001:
			instabust_count += 1
	var instabust_rate = float(instabust_count) / float(total)
	# Tolerance band: 5% ± 2% for n=2000
	assert_true(instabust_rate > 0.03 and instabust_rate < 0.07, "instabust rate %f outside [0.03, 0.07]" % instabust_rate)
