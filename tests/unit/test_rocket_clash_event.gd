extends GutTest

const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func _build_context(player_count: int, is_host: bool) -> RefCounted:
	var ctx = EventContext.new()
	for i in player_count:
		var p = MatchPlayer.new()
		p.peer_id = i + 1
		p.name = "P%d" % (i + 1)
		p.is_active_this_event = true
		ctx.players.append(p)
		ctx.wagers[p.peer_id] = 100
	ctx.event_index = 0
	ctx.rng_seed = 0xCAFE
	ctx.is_host = is_host
	return ctx

func _new_host_event() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var event = RocketClashEvent.new()
	event._multiplayer_node = fake
	add_child_autofree(event)
	return {"event": event, "fake": fake}

func test_get_event_id():
	var e = RocketClashEvent.new()
	assert_eq(e.get_event_id(), "rocket_clash")

func test_run_on_host_broadcasts_rocket_launched():
	var d = _new_host_event()
	var e = d.event
	e._force_crash_at_override = 2.5
	e._run(_build_context(2, true))
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_rocket_launched":
			found = true
			assert_eq(call.args.size(), 2)
			assert_almost_eq(float(call.args[1]), 2.5, 0.001)
			break
	assert_true(found, "host should broadcast _rpc_rocket_launched")

func test_run_on_client_does_not_broadcast():
	var d = _new_host_event()
	var e = d.event
	e._run(_build_context(2, false))
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_rocket_launched":
			found = true
			break
	assert_false(found, "client must not broadcast _rpc_rocket_launched")

func test_force_crash_at_override_used_when_set():
	var d = _new_host_event()
	var e = d.event
	e._force_crash_at_override = 7.5
	e._run(_build_context(2, true))
	assert_almost_eq(e._crash_at, 7.5, 0.001)

func test_force_crash_at_override_falls_back_to_rng():
	var d = _new_host_event()
	var e = d.event
	e._run(_build_context(2, true))
	assert_true(e._crash_at >= 1.0)
	assert_true(e._crash_at <= 100.0)

func test_cash_out_within_tolerance_accepted():
	var d = _new_host_event()
	var e = d.event
	e._force_crash_at_override = 5.0
	e._run(_build_context(2, true))
	e._force_current_mult_for_testing = 2.0
	e._rpc_cash_out_requested(2, 2.01)  # within 0.05 tolerance
	var confirmed = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_cash_out_confirmed":
			confirmed = true
			assert_eq(call.args[0], 2, "confirmed peer_id")
			assert_almost_eq(float(call.args[1]), 2.0, 0.001, "host's authoritative mult")
			break
	assert_true(confirmed)
	assert_true(e._cash_outs.has(2))

func test_cash_out_out_of_tolerance_rejected():
	var d = _new_host_event()
	var e = d.event
	e._force_crash_at_override = 5.0
	e._run(_build_context(2, true))
	e._force_current_mult_for_testing = 2.0
	e._rpc_cash_out_requested(2, 2.50)  # >0.05 off
	var rejected = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_cash_out_rejected":
			rejected = true
			assert_eq(call.args[0], 2)
			break
	assert_true(rejected)
	assert_false(e._cash_outs.has(2))

func test_double_cash_out_silently_dropped():
	var d = _new_host_event()
	var e = d.event
	e._force_crash_at_override = 5.0
	e._run(_build_context(2, true))
	e._force_current_mult_for_testing = 2.0
	e._rpc_cash_out_requested(2, 2.0)  # first: accepted
	var first_count = d.fake.rpc_calls.size()
	e._rpc_cash_out_requested(2, 2.0)  # second: silently dropped
	assert_eq(d.fake.rpc_calls.size(), first_count, "duplicate cash-out silently dropped")

func test_cash_out_button_press_dispatches_request():
	var d = _new_host_event()
	var e = d.event
	e._force_crash_at_override = 5.0
	e._run(_build_context(2, true))
	# Simulate button press by calling the handler directly (no actual button click in unit test)
	d.fake.rpc_calls.clear()
	e._force_current_mult_for_testing = -1.0  # use real elapsed (will be near 1.0)
	e._on_cash_out_button_pressed()
	# Verify _rpc_cash_out_requested was broadcast with the host's peer_id
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_cash_out_requested":
			found = true
			break
	assert_true(found, "button press should fire _rpc_cash_out_requested")
