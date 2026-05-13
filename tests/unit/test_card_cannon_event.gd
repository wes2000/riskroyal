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

const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player_cc(peer_id: int, name: String, seat_index: int = -1) -> RefCounted:
	var p = MatchPlayer.new()
	p.peer_id = peer_id
	p.name = name
	p.is_active_this_event = true
	p.seat_index = seat_index if seat_index >= 0 else peer_id
	return p

func _make_context_cc(player_count: int, wagers: Dictionary, modifiers: Dictionary) -> RefCounted:
	var ctx = EventContext.new()
	for i in player_count:
		ctx.players.append(_make_player_cc(i + 1, "P%d" % (i + 1), i))
	ctx.wagers = wagers
	ctx.event_modifiers = modifiers
	return ctx

func test_compute_event_result_score_band_payouts():
	# Five band assertions in one test.
	var ctx = _make_context_cc(5, {1: 100, 2: 100, 3: 100, 4: 100, 5: 100}, {})
	var hands = {1: [10], 2: [10, 3], 3: [10, 7], 4: [10, 9], 5: [10, 11]}
	var locked = {1: 10, 2: 13, 3: 17, 4: 19, 5: 21}
	var busted = {}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	assert_eq(result.per_player[1].chip_delta, 50, "band low: 100 * 0.5")
	assert_eq(result.per_player[2].chip_delta, 100, "band medium: 100 * 1.0")
	assert_eq(result.per_player[3].chip_delta, 150, "band strong: 100 * 1.5")
	assert_eq(result.per_player[4].chip_delta, 200, "band heavy: 100 * 2.0")
	assert_eq(result.per_player[5].chip_delta, 300, "band perfect: 100 * 3.0")

func test_compute_event_result_busted_player_loses_wager():
	var ctx = _make_context_cc(2, {1: 100, 2: 100}, {})
	var hands = {1: [10, 10, 5], 2: [10, 5]}
	var locked = {2: 15}
	var busted = {1: true}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	assert_eq(result.per_player[1].chip_delta, -100)
	assert_true(result.per_player[1].bust)
	assert_eq(result.per_player[2].chip_delta, 100, "band medium")

func test_compute_event_result_crown_to_highest_locked_score():
	var ctx = _make_context_cc(3, {1: 100, 2: 100, 3: 100}, {})
	var hands = {1: [10, 7], 2: [10, 9], 3: [10, 5]}
	var locked = {1: 17, 2: 19, 3: 15}
	var busted = {}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	assert_eq(result.per_player[2].crown_delta, 1, "P2 highest")
	assert_eq(result.per_player[1].crown_delta, 0)
	assert_eq(result.per_player[3].crown_delta, 0)

func test_compute_event_result_crown_tie_breaks_by_seat_index():
	var ctx = _make_context_cc(2, {1: 100, 2: 100}, {})
	# seat_index for P1 = 0, P2 = 1 (per _make_player_cc default)
	var hands = {1: [10, 8], 2: [10, 8]}
	var locked = {1: 18, 2: 18}
	var busted = {}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	assert_eq(result.per_player[1].crown_delta, 1, "lower seat_index wins tie")
	assert_eq(result.per_player[2].crown_delta, 0)

func test_compute_event_result_insurance_halves_bust_penalty():
	var ctx = _make_context_cc(2, {1: 200, 2: 200}, {1: {"insurance_pre": true}})
	var hands = {1: [10, 10, 5], 2: [10, 10, 5]}
	var locked = {}
	var busted = {1: true, 2: true}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	assert_eq(result.per_player[1].chip_delta, -100, "P1 Insurance halves")
	assert_eq(result.per_player[2].chip_delta, -200, "P2 no Insurance")

func test_compute_event_result_underdog_odds_boosts_survivor():
	var ctx = _make_context_cc(2, {1: 100, 2: 100}, {1: {"underdog_multiplier": 1.5}})
	var hands = {1: [10, 9], 2: [10, 8]}
	var locked = {1: 19, 2: 18}
	var busted = {}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	# P1: 100 * 2.0 (heavy band) * 1.5 = 300
	assert_eq(result.per_player[1].chip_delta, 300)
	# P2: 100 * 1.5 (strong band) = 150
	assert_eq(result.per_player[2].chip_delta, 150)
