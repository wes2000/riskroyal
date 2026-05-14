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

func test_starter_pack_dealt_fires_one_rpc_per_peer():
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(3))
	var starter_pack_calls = []
	for call in fake.rpc_calls:
		if String(call.get("method", "")) == "_rpc_starter_pack_dealt":
			starter_pack_calls.append(call)
	assert_eq(starter_pack_calls.size(), 3,
		"expected 3 _rpc_starter_pack_dealt calls (1 per peer), got %d" % starter_pack_calls.size())
	for call in starter_pack_calls:
		assert_true(call.has("peer_id"),
			"each starter_pack call must be rpc_id (targeted), not rpc broadcast")
	var peer_ids_seen = []
	for call in starter_pack_calls:
		var pid = int(call.get("peer_id", 0))
		assert_false(pid in peer_ids_seen, "duplicate starter_pack to peer %d" % pid)
		peer_ids_seen.append(pid)
	assert_eq(peer_ids_seen.size(), 3, "all 3 peers received exactly one starter_pack call")
