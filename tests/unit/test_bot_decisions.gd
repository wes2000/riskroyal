extends GutTest

const BotDecisions = preload("res://scripts/match/bot_decisions.gd")

func _seeded(seed_int: int = 12345) -> RandomNumberGenerator:
	var r = RandomNumberGenerator.new()
	r.seed = seed_int
	return r

func test_pick_wager_within_range():
	var w = BotDecisions.pick_wager(500, 1000, _seeded())
	assert_gte(w, 0); assert_lte(w, 500)

func test_pick_wager_deterministic_for_seed():
	var a = BotDecisions.pick_wager(500, 1000, _seeded(42))
	var b = BotDecisions.pick_wager(500, 1000, _seeded(42))
	assert_eq(a, b)

func test_pick_wager_zero_max_returns_zero():
	assert_eq(BotDecisions.pick_wager(0, 1000, _seeded()), 0)

func test_pick_cash_out_delay_in_range():
	var d = BotDecisions.pick_cash_out_delay_ms(_seeded())
	assert_gte(d, 2500); assert_lte(d, 8000)

func test_pick_pull_out_delay_in_range():
	var d = BotDecisions.pick_pull_out_delay_ms(_seeded())
	assert_gte(d, 4500); assert_lte(d, 13500)

func test_pick_card_cannon_threshold_in_range():
	var t = BotDecisions.pick_card_cannon_threshold(_seeded())
	assert_gte(t, 14); assert_lte(t, 19)

func test_pick_loadout_respects_max_size():
	var hand = ["a", "b", "c", "d", "e"]
	var lo = BotDecisions.pick_loadout(hand, 2, _seeded())
	assert_lte(lo.size(), 2)
	for c in lo:
		assert_true(c in hand)

func test_pick_loadout_no_duplicates():
	var hand = ["a", "b", "c"]
	var lo = BotDecisions.pick_loadout(hand, 3, _seeded())
	assert_eq(lo.size(), len(_unique(lo)))

func test_pick_loadout_empty_hand_returns_empty():
	assert_eq(BotDecisions.pick_loadout([], 2, _seeded()), [])

func test_pick_shop_purchase_skip_when_no_offer():
	assert_eq(BotDecisions.pick_shop_purchase([], {}, 500, _seeded()), "")

func test_pick_shop_purchase_skip_when_too_expensive():
	# Card costs 400, bot has 500 → 80% of stack, > 50% threshold → skip.
	var got = BotDecisions.pick_shop_purchase(["pricey"], {"pricey": 400}, 500, _seeded())
	assert_eq(got, "")

func test_pick_shop_purchase_buys_affordable():
	# Card costs 50, bot has 500 → 10% of stack, well under threshold.
	var got = BotDecisions.pick_shop_purchase(["cheap"], {"cheap": 50}, 500, _seeded())
	assert_eq(got, "cheap")

func test_pick_event_path_returns_member():
	var got = BotDecisions.pick_event_path(["a", "b", "c"], _seeded())
	assert_true(got in ["a", "b", "c"])

func test_rng_for_bot_differs_across_peer_ids():
	var ra = BotDecisions.rng_for_bot(99, 1000)
	var rb = BotDecisions.rng_for_bot(99, 1001)
	assert_ne(ra.randi(), rb.randi())

func test_rng_for_bot_reproducible_for_same_inputs():
	var ra = BotDecisions.rng_for_bot(99, 1000)
	var rb = BotDecisions.rng_for_bot(99, 1000)
	assert_eq(ra.randi(), rb.randi())

func _unique(arr: Array) -> Array:
	var seen: Dictionary = {}
	for x in arr:
		seen[x] = true
	return seen.keys()
