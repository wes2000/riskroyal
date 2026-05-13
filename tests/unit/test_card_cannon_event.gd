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

const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func _new_host_card_cannon_at_main() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var e = Node.new()
	e.set_script(CardCannonEvent)
	e._is_host = true
	e._multiplayer_node = fake
	e._active_peers = [1, 2]
	e._hands = {1: [], 2: []}
	e._scores = {1: 0, 2: 0}
	e._busted = {1: false, 2: false}
	# Stash a minimal context for compute_next_rank (which uses _rng,
	# falling back to a fresh RNG if _rng is null — tests use override).
	var EventContext = load("res://scripts/events/event_context.gd")
	var ctx = EventContext.new()
	ctx.rng_seed = 1
	e._stashed_context = ctx
	return {"event": e, "fake": fake}

func test_draw_appends_to_hand_and_updates_score():
	var d = _new_host_card_cannon_at_main()
	var e = d.event
	e._force_next_rank_override = 7
	e._rpc_draw_requested(1)
	assert_eq(e._hands[1], [7])
	assert_eq(e._scores[1], 7)
	e.free()

func test_draw_busts_at_22_or_higher():
	var d = _new_host_card_cannon_at_main()
	var e = d.event
	e._hands[1] = [10, 7]
	e._scores[1] = 17
	e._force_next_rank_override = 6  # 17 + 6 = 23 → bust
	e._rpc_draw_requested(1)
	assert_eq(e._scores[1], 23)
	assert_true(e._busted[1])
	e.free()

func test_lock_freezes_score():
	var d = _new_host_card_cannon_at_main()
	var e = d.event
	e._hands[1] = [10, 8]
	e._scores[1] = 18
	e._rpc_lock_requested(1)
	assert_eq(e._locked_scores.get(1, -1), 18)
	e.free()

func test_draw_after_lock_rejected():
	var d = _new_host_card_cannon_at_main()
	var e = d.event
	e._locked_scores[1] = 17
	e._force_next_rank_override = 10
	e._rpc_draw_requested(1)
	# Should not have drawn anything (no hand mutation)
	assert_eq(e._hands.get(1, []), [])
	e.free()

func test_draw_after_bust_rejected():
	var d = _new_host_card_cannon_at_main()
	var e = d.event
	e._busted[1] = true
	e._hands[1] = [10, 10, 5]  # already busted at 25
	e._scores[1] = 25
	e._force_next_rank_override = 5
	e._rpc_draw_requested(1)
	# Hand should not have grown
	assert_eq(e._hands[1], [10, 10, 5])
	e.free()
