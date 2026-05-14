extends GutTest

# Regression guard for "RPC '_rpc_starter_pack_dealt' on yourself is not
# allowed by selected mode" runtime warning (Alpha feel remediation Phase A §13.4).
#
# Plan A Task 11 narrowed the starter pack from a broadcast to one rpc_id per
# peer. That change inadvertently dispatched rpc_id(host_peer_id, ...) to the
# host itself. The host's hand is already set directly (p.hand = hand), so the
# self-rpc is redundant and produces an engine error. The fix skips rpc_id when
# p.peer_id == _local_peer_id().

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

func test_starter_pack_does_not_rpc_to_host_self():
	# The host (peer_id=1) already has its hand applied locally inside the
	# deal loop. Verify no rpc_id call targets the host's own peer_id.
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	# Set override so _local_peer_id() returns 1 (host peer).
	c._local_peer_id_override = 1
	c.start_match(_build_match_start(3))
	var host_targeted: Array = []
	for call in fake.rpc_calls:
		if String(call.get("method", "")) == "_rpc_starter_pack_dealt":
			if int(call.get("peer_id", 0)) == 1:
				host_targeted.append(call)
	assert_eq(host_targeted.size(), 0,
		"host should not rpc_id _rpc_starter_pack_dealt to itself (peer_id=1)")

func test_starter_pack_remote_peers_still_receive_rpc():
	# The two remote peers (peer_id 2 + 3) must still receive their targeted
	# starter pack broadcast after the host-skip fix.
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c._local_peer_id_override = 1
	c.start_match(_build_match_start(3))
	var remote_targeted: Array = []
	for call in fake.rpc_calls:
		if String(call.get("method", "")) == "_rpc_starter_pack_dealt":
			if int(call.get("peer_id", 0)) in [2, 3]:
				remote_targeted.append(call)
	assert_eq(remote_targeted.size(), 2,
		"remote peers 2 + 3 still receive the starter pack rpc")

func test_host_hand_is_still_set_locally():
	# Confirm the host's MatchPlayer.hand is populated even though no rpc_id
	# is sent to the host. The direct p.hand = hand assignment covers this.
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c._local_peer_id_override = 1
	c.start_match(_build_match_start(2))
	var host_player = c.state.find_player(1)
	assert_not_null(host_player, "host MatchPlayer record must exist")
	assert_true(host_player.hand.size() > 0,
		"host hand is populated locally without needing the rpc")
