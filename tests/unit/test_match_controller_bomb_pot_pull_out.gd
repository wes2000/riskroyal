extends GutTest

const BombPotEvent = preload("res://scripts/events/bomb_pot/bomb_pot_event.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func _new_bomb_pot_event_at_main_event() -> Dictionary:
	# Construct a Bomb Pot event in the running state (post-_run).
	# Bypasses MatchController setup; tests focus on event-level RPC validation.
	var fake = FakeMultiplayerNode.new()
	var e = Node.new()
	e.set_script(BombPotEvent)
	e._is_host = true
	e._multiplayer_node = fake
	e._start_time_ms = Time.get_ticks_msec()
	e._active_peers = [1, 2]
	e._shares_accumulator = {1: 50.0, 2: 80.0}
	return {"event": e, "fake": fake}

func test_pull_out_during_main_event_locks_share():
	var d = _new_bomb_pot_event_at_main_event()
	var e = d.event
	e._rpc_pull_out_requested(1)
	assert_eq(e._locked_shares.get(1, 0), 50)
	assert_true(1 in e._pulled_out_peers)
	e.free()

func test_pull_out_outside_main_event_rejected():
	# Simulate "main event hasn't started" via _start_time_ms == 0
	var fake = FakeMultiplayerNode.new()
	var e = Node.new()
	e.set_script(BombPotEvent)
	e._is_host = true
	e._multiplayer_node = fake
	e._start_time_ms = 0  # not yet started
	e._active_peers = [1, 2]
	e._rpc_pull_out_requested(1)
	assert_eq(e._locked_shares.get(1, 0), 0)
	assert_false(1 in e._pulled_out_peers)
	e.free()

func test_double_pull_out_silently_dropped():
	var d = _new_bomb_pot_event_at_main_event()
	var e = d.event
	e._rpc_pull_out_requested(1)
	d.fake.rpc_calls.clear()
	e._rpc_pull_out_requested(1)
	var ack_count = 0
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_pull_out_confirmed":
			ack_count += 1
	assert_eq(ack_count, 0)
	e.free()
