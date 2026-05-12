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
