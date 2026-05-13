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
