extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func _build_match_start(player_count: int) -> RefCounted:
	var ms = MatchStart.new()
	for i in player_count:
		var s = PlayerSlot.new()
		s.peer_id = i + 1; s.seat_index = i; s.name = "P%d" % (i + 1)
		ms.seats.append(s)
	ms.host_peer_id = 1; ms.rng_seed = 1
	return ms

func _new_host_with_fake() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(2))
	return {"controller": c, "fake": fake}

func test_pending_wagers_default_empty():
	var s = MatchState.new()
	assert_eq(s.pending_wagers, {})

func test_pending_wagers_round_trip():
	var s = MatchState.new()
	s.pending_wagers = {1: 200, 2: 0}
	var d = s.to_dict()
	var s2 = MatchState.from_dict(d)
	assert_eq(s2.pending_wagers.get(1, -1), 200)
	assert_eq(s2.pending_wagers.get(2, -1), 0)

func test_rpc_set_wager_clamps_to_chips():
	var d = _new_host_with_fake()
	var c = d.controller
	var p1_chips = c.state.players[0].chips
	c._rpc_set_wager(1, p1_chips + 5000)  # over
	assert_eq(c.state.pending_wagers[1], p1_chips, "wager clamped to chip count")

func test_rpc_set_wager_broadcasts_acknowledged():
	var d = _new_host_with_fake()
	d.fake.rpc_calls.clear()
	d.controller._rpc_set_wager(1, 50)
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_wager_acknowledged":
			found = true
			assert_eq(call.args[0], 1)
			assert_eq(call.args[1], 50)
			break
	assert_true(found)

func test_build_event_context_reads_pending_wagers():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.pending_wagers = {1: 300, 2: 0}
	var ctx = c._build_event_context()
	assert_eq(ctx.wagers.get(1, -1), 300)
	assert_eq(ctx.wagers.get(2, -1), 0)
