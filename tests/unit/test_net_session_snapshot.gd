extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")

func _build_welcome_payload():
	var s = PlayerSlot.new()
	s.peer_id = 1; s.is_host = true; s.seat_index = 0; s.name = "Host"
	return {
		"code": "ABC234",
		"players": [s.to_dict()],
	}

func test_rpc_receive_welcome_populates_client_state():
	var t = FakeTransport.new()
	var sig = FakeSignalingClient.new()
	var sess = NetSession.new(t, sig)
	sess.join_session("ABC234")
	sig.emit_peer_id_assigned(2)  # so local_peer_id is set first
	sess.rpc_receive_welcome(_build_welcome_payload())
	assert_eq(sess.local_peer_id, 2)
	assert_eq(sess.code, "ABC234")
	assert_eq(sess.players.size(), 1)
	assert_true(sess.players[0].is_host)
	assert_eq(sess.state, NetSessionState.State.LOBBY)

func test_rpc_receive_welcome_emits_players_changed():
	var t = FakeTransport.new()
	var sig = FakeSignalingClient.new()
	var sess = NetSession.new(t, sig)
	sess.join_session("ABC234")
	sig.emit_peer_id_assigned(2)
	var fired = [false]
	sess.players_changed.connect(func(): fired[0] = true)
	sess.rpc_receive_welcome(_build_welcome_payload())
	assert_true(fired[0])

func test_rpc_sync_player_list_replaces_players():
	var t = FakeTransport.new()
	var sig = FakeSignalingClient.new()
	var sess = NetSession.new(t, sig)
	sess.join_session("ABC234")
	sig.emit_peer_id_assigned(2)
	sess.rpc_receive_welcome(_build_welcome_payload())
	var s2 = PlayerSlot.new()
	s2.peer_id = 2; s2.seat_index = 1; s2.name = "Maya"
	sess.rpc_sync_player_list([
		sess.players[0].to_dict(),
		s2.to_dict(),
	])
	assert_eq(sess.players.size(), 2)
	assert_eq(sess.players[1].name, "Maya")

func test_host_emits_welcome_via_signal_on_peer_joined():
	var t = FakeTransport.new()
	var sig = FakeSignalingClient.new()
	var sess = NetSession.new(t, sig)
	sess.host_session()
	sig.emit_code_issued("ABC234")
	var welcomes := []
	sess.send_welcome_to.connect(func(target_peer, payload): welcomes.append([target_peer, payload]))
	t.emit_peer_joined(2)
	assert_eq(welcomes.size(), 1)
	assert_eq(welcomes[0][0], 2)
	assert_eq(welcomes[0][1].code, "ABC234")
	assert_eq(welcomes[0][1].players.size(), 2, "host + new joiner")
