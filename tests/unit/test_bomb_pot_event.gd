extends GutTest

const BombPotEvent = preload("res://scripts/events/bomb_pot/bomb_pot_event.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")

func _new_rng(seed_value: int) -> RandomNumberGenerator:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

func test_compute_bomb_at_within_window():
	# 1000 samples; every result must be in [MIN, MAX].
	var rng = _new_rng(1)
	for i in 1000:
		var t = BombPotEvent.compute_bomb_at(rng)
		assert_true(t >= MatchConfig.BOMB_POT_MIN_DETONATION_SEC, "got %f" % t)
		assert_true(t <= MatchConfig.BOMB_POT_MAX_DETONATION_SEC, "got %f" % t)

func test_compute_bomb_at_deterministic_with_same_seed():
	var rng1 = _new_rng(42)
	var rng2 = _new_rng(42)
	for i in 10:
		assert_almost_eq(BombPotEvent.compute_bomb_at(rng1), BombPotEvent.compute_bomb_at(rng2), 0.001)

func test_compute_bomb_at_instabust_probability():
	# ~5% should equal MIN_DETONATION (5.0). Allow 3-7% range.
	var rng = _new_rng(99)
	var instabust_count = 0
	var samples = 10000
	for i in samples:
		var t = BombPotEvent.compute_bomb_at(rng)
		if abs(t - MatchConfig.BOMB_POT_MIN_DETONATION_SEC) < 0.001:
			instabust_count += 1
	var ratio = float(instabust_count) / float(samples)
	assert_true(ratio >= 0.03 and ratio <= 0.07, "instabust ratio out of range: %f" % ratio)
