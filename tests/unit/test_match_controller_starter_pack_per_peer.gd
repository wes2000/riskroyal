extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start(player_count: int) -> RefCounted:
	var ms = MatchStart.new()
	for i in player_count:
		var s = PlayerSlot.new()
		s.peer_id = i + 1; s.seat_index = i; s.name = "P%d" % (i + 1)
		ms.seats.append(s)
	ms.host_peer_id = 1; ms.rng_seed = 1
	return ms

func test_starter_pack_dealt_fires_one_rpc_per_remote_peer():
	# Alpha feel remediation Phase A §13.4: the host (peer_id=1) skips its
	# own rpc_id call; only remote peers receive the targeted broadcast.
	# For a 3-player match the expected count is 2 (peers 2 + 3), not 3.
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	# peer_id 1 is the host (local peer via _local_peer_id_override default)
	# _local_peer_id() returns multiplayer.get_unique_id() which is 0 in tests
	# without an override, but _local_peer_id_override=0 means "use real
	# multiplayer". Since there is no real multiplayer in unit tests, 0 is
	# returned — so peer_id 1 != 0 and gets an RPC in that path. Set the
	# override to 1 to model the "I am the host" scenario properly.
	c._local_peer_id_override = 1
	c.start_match(_build_match_start(3))
	var starter_pack_calls = []
	for call in fake.rpc_calls:
		if String(call.get("method", "")) == "_rpc_starter_pack_dealt":
			starter_pack_calls.append(call)
	# With host-skip: 2 remote peers (peer_id 2 + 3), not 3.
	assert_eq(starter_pack_calls.size(), 2,
		"expected 2 _rpc_starter_pack_dealt calls (remote peers only), got %d" % starter_pack_calls.size())
	for call in starter_pack_calls:
		assert_true(call.has("peer_id"),
			"each starter_pack call must be rpc_id (targeted), not rpc broadcast")
	# Verify no call targets the host's own peer_id.
	for call in starter_pack_calls:
		assert_ne(int(call.get("peer_id", 0)), 1,
			"host (peer_id=1) must not receive rpc_id to itself")
	var peer_ids_seen = []
	for call in starter_pack_calls:
		var pid = int(call.get("peer_id", 0))
		assert_false(pid in peer_ids_seen, "duplicate starter_pack to peer %d" % pid)
		peer_ids_seen.append(pid)
	assert_eq(peer_ids_seen.size(), 2, "both remote peers received exactly one starter_pack call")
