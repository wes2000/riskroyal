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

const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func _new_host_event_with_fake() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var e = Node.new()
	e.set_script(BombPotEvent)
	e._is_host = true
	e._multiplayer_node = fake
	e._start_time_ms = Time.get_ticks_msec()
	e._active_peers = [1, 2]
	e._shares_accumulator = {1: 120.0, 2: 80.0}
	return {"event": e, "fake": fake}

func test_pull_out_locks_share_and_records_timestamp():
	var d = _new_host_event_with_fake()
	var e = d.event
	e._rpc_pull_out_requested(1)
	assert_eq(e._locked_shares.get(1, 0), 120, "P1 locked accumulator at int 120")
	assert_true(1 in e._pulled_out_peers)
	assert_true(e._pull_out_timestamps.has(1), "host recorded timestamp")
	e.free()

func test_pull_out_broadcasts_confirmed():
	var d = _new_host_event_with_fake()
	var e = d.event
	e._rpc_pull_out_requested(1)
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_pull_out_confirmed":
			found = true
			assert_eq(call.args[0], 1, "peer_id")
			assert_eq(call.args[1], 120, "locked_share")
			break
	assert_true(found, "_rpc_pull_out_confirmed broadcast")
	e.free()

func test_pull_out_double_tap_silently_dropped():
	var d = _new_host_event_with_fake()
	var e = d.event
	e._rpc_pull_out_requested(1)
	d.fake.rpc_calls.clear()
	e._rpc_pull_out_requested(1)
	var ack_count = 0
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_pull_out_confirmed":
			ack_count += 1
	assert_eq(ack_count, 0, "second pull-out silently dropped")
	e.free()

func test_pull_out_after_finished_rejected():
	var d = _new_host_event_with_fake()
	var e = d.event
	e._finished = true
	e._rpc_pull_out_requested(1)
	assert_false(e._locked_shares.has(1))
	e.free()

func test_compute_per_tick_share_distributes_across_active_grabbers():
	# 50 chips/sec, 0.5 sec delta, 2 grabbers → each gets 12.5
	var share = BombPotEvent.compute_per_tick_share(0.5, 50.0, 2)
	assert_almost_eq(share, 12.5, 0.001)

func test_compute_per_tick_share_zero_when_no_active_grabbers():
	var share = BombPotEvent.compute_per_tick_share(0.5, 50.0, 0)
	assert_almost_eq(share, 0.0, 0.001)

func test_compute_per_tick_share_solo_grabber_gets_full_rate():
	var share = BombPotEvent.compute_per_tick_share(1.0, 50.0, 1)
	assert_almost_eq(share, 50.0, 0.001)

const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(peer_id: int, name: String, seat_index: int = -1) -> RefCounted:
	var p = MatchPlayer.new()
	p.peer_id = peer_id
	p.name = name
	p.is_active_this_event = true
	p.seat_index = seat_index if seat_index >= 0 else peer_id
	return p

func _make_context(player_count: int, wagers: Dictionary, modifiers: Dictionary) -> RefCounted:
	var ctx = EventContext.new()
	for i in player_count:
		ctx.players.append(_make_player(i + 1, "P%d" % (i + 1), i))
	ctx.wagers = wagers
	ctx.event_modifiers = modifiers
	return ctx

func test_compute_event_result_survivor_locks_share():
	var ctx = _make_context(2, {1: 100, 2: 100}, {})
	var locked = {1: 200}  # P1 pulled out with 200 chips locked
	var pulled = [1]
	var timestamps = {1: 8000}
	var result = BombPotEvent.compute_event_result(ctx, 15.0, locked, pulled, timestamps)
	assert_eq(result.per_player[1].chip_delta, 200, "survivor gets locked share")
	assert_false(result.per_player[1].bust)

func test_compute_event_result_busted_grabber_loses_wager():
	var ctx = _make_context(2, {1: 100, 2: 150}, {})
	var locked = {}
	var pulled = []  # nobody pulled out
	var timestamps = {}
	var result = BombPotEvent.compute_event_result(ctx, 10.0, locked, pulled, timestamps)
	assert_eq(result.per_player[1].chip_delta, -100, "P1 lost wager")
	assert_eq(result.per_player[2].chip_delta, -150, "P2 lost wager")
	assert_true(result.per_player[1].bust)
	assert_true(result.per_player[2].bust)

func test_compute_event_result_crown_to_last_puller():
	var ctx = _make_context(3, {1: 100, 2: 100, 3: 100}, {})
	var locked = {1: 150, 2: 200, 3: 100}
	var pulled = [1, 2, 3]
	# P2 pulled out last
	var timestamps = {1: 5000, 2: 12000, 3: 8000}
	var result = BombPotEvent.compute_event_result(ctx, 15.0, locked, pulled, timestamps)
	assert_eq(result.per_player[2].crown_delta, 1, "P2 last-puller wins Crown")
	assert_eq(result.per_player[1].crown_delta, 0)
	assert_eq(result.per_player[3].crown_delta, 0)
	# Phase C Change 3: HeatRules-scaled Heat. P2 pulled at 12000ms on a 15s bomb
	# (ratio = 0.80) -> bomb_pot_heat returns 3 (>= 0.80 tier).
	assert_eq(result.per_player[2].heat_delta, 3, "0.80 ratio late-pull = +3 Heat")

func test_compute_event_result_crown_tie_breaks_by_seat_index():
	var ctx = _make_context(2, {1: 100, 2: 100}, {})
	var locked = {1: 150, 2: 150}
	var pulled = [1, 2]
	# Same timestamps (defensive)
	var timestamps = {1: 8000, 2: 8000}
	var result = BombPotEvent.compute_event_result(ctx, 15.0, locked, pulled, timestamps)
	# P1 has seat_index=0 (lower); should win the tie
	assert_eq(result.per_player[1].crown_delta, 1, "lower seat_index wins tie")
	assert_eq(result.per_player[2].crown_delta, 0)

func test_compute_event_result_insurance_halves_bust_penalty():
	var ctx = _make_context(2, {1: 200, 2: 200}, {1: {"insurance_pre": true}})
	var locked = {}
	var pulled = []
	var timestamps = {}
	var result = BombPotEvent.compute_event_result(ctx, 8.0, locked, pulled, timestamps)
	assert_eq(result.per_player[1].chip_delta, -100, "Insurance halves P1 bust")
	assert_eq(result.per_player[2].chip_delta, -200, "P2 no insurance, full loss")

func test_compute_event_result_wager_multiplier_boosts_survivor():
	var ctx = _make_context(2, {1: 100, 2: 100}, {1: {"wager_multiplier": 1.25}})
	var locked = {1: 200, 2: 200}
	var pulled = [1, 2]
	var timestamps = {1: 9000, 2: 8000}
	var result = BombPotEvent.compute_event_result(ctx, 15.0, locked, pulled, timestamps)
	assert_eq(result.per_player[1].chip_delta, 250, "200 * 1.25")
	assert_eq(result.per_player[2].chip_delta, 200)

func test_compute_event_result_heat_shield_halves_winner_heat():
	var ctx = _make_context(2, {1: 100, 2: 100}, {1: {"heat_shield": true}})
	var locked = {1: 200, 2: 100}
	var pulled = [1, 2]
	var timestamps = {1: 9000, 2: 7000}  # P1 last puller
	var result = BombPotEvent.compute_event_result(ctx, 15.0, locked, pulled, timestamps)
	assert_eq(result.per_player[1].crown_delta, 1, "P1 wins Crown")
	# Phase C Change 3: P1 pulled at 9000ms on 15s bomb (ratio=0.60, won_crown
	# tier) -> base 2 Heat; Heat Shield floors to 1.
	assert_eq(result.per_player[1].heat_delta, 1, "Heat Shield halves 2 -> 1")
