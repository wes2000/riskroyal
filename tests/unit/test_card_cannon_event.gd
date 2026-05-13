extends GutTest

const CardCannonEvent = preload("res://scripts/events/card_cannon/card_cannon_event.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")

func _new_rng(seed_value: int) -> RandomNumberGenerator:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

func test_compute_next_rank_distribution_within_range():
	var rng = _new_rng(1)
	for i in 1000:
		var rank = CardCannonEvent.compute_next_rank(rng)
		assert_true(rank >= 2 and rank <= 11, "rank out of range: %d" % rank)

func test_compute_next_rank_deterministic_with_same_seed():
	var rng1 = _new_rng(42)
	var rng2 = _new_rng(42)
	for i in 10:
		assert_eq(CardCannonEvent.compute_next_rank(rng1), CardCannonEvent.compute_next_rank(rng2))

func test_compute_score_basic_sum():
	assert_eq(CardCannonEvent.compute_score([5, 7]), 12)
	assert_eq(CardCannonEvent.compute_score([10, 10]), 20)

func test_compute_score_ace_counts_high_when_safe():
	# Ace (11) + 9 = 20 (safe under 21)
	assert_eq(CardCannonEvent.compute_score([11, 9]), 20)

func test_compute_score_ace_demotes_to_low_to_avoid_bust():
	# Ace (11) + 10 + 5 = 26 → bust → Ace becomes 1 → 16
	assert_eq(CardCannonEvent.compute_score([11, 10, 5]), 16)

func test_compute_score_multiple_aces():
	# Ace + Ace + 9 = 21 (one Ace high, one low)
	assert_eq(CardCannonEvent.compute_score([11, 11, 9]), 21)
	# Ace + Ace + Ace + 10 = 13 (one high, two low: 11+1+1+10=23 → 1+1+1+10=13)
	assert_eq(CardCannonEvent.compute_score([11, 11, 11, 10]), 13)
