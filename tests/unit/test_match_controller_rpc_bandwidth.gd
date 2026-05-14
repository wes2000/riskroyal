extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start(player_count: int):
	var ms = MatchStart.new()
	for i in player_count:
		var s = PlayerSlot.new()
		s.peer_id = i + 1; s.seat_index = i; s.name = "P%d" % (i + 1)
		ms.seats.append(s)
	ms.host_peer_id = 1; ms.rng_seed = 1
	return ms

func _new_client_controller():
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(false, fake)
	c.no_op_phase_delay_ms_override = 0
	# Client skips start_match (is_host=false), so set host_peer_id manually.
	# In production, clients receive this via the network session bootstrap.
	c.host_peer_id = 1
	c.start_match(_build_match_start(3))
	fake.rpc_calls.clear()
	return c

func _find_call(fake, method_name: String) -> Dictionary:
	for call in fake.rpc_calls:
		if String(call.get("method", "")) == method_name:
			return call
	return {}

func test_submit_wager_targets_host_via_rpc_id():
	var c = _new_client_controller()
	c.submit_wager(50)
	var call = _find_call(c._rpc_sender._multiplayer_node, "_rpc_set_wager")
	assert_true(call.has("peer_id"),
		"_rpc_set_wager must use rpc_id (peer_id key present in fake record)")
	assert_eq(int(call.get("peer_id", -1)), 1,
		"target peer_id must be host_peer_id (1)")

func test_submit_card_play_targets_host_via_rpc_id():
	var c = _new_client_controller()
	c.submit_card_play("heat_shield", 0, null)
	var call = _find_call(c._rpc_sender._multiplayer_node, "_rpc_card_play_requested")
	assert_true(call.has("peer_id"),
		"_rpc_card_play_requested must use rpc_id")
	assert_eq(int(call.get("peer_id", -1)), 1, "targets host")

func test_submit_event_pick_targets_host_via_rpc_id():
	var c = _new_client_controller()
	c.submit_event_pick("res://scenes/events/rocket_clash/rocket_clash_event.tscn")
	var call = _find_call(c._rpc_sender._multiplayer_node, "_rpc_event_picker_choice")
	assert_true(call.has("peer_id"),
		"_rpc_event_picker_choice must use rpc_id")
	assert_eq(int(call.get("peer_id", -1)), 1, "targets host")
