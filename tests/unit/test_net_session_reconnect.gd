extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")

var transport
var signaling
var session

func before_each():
	transport = FakeTransport.new()
	signaling = FakeSignalingClient.new()
	session = NetSession.new(transport, signaling)
	session.host_session()
	signaling.emit_code_issued("ABC234")
	transport.emit_peer_joined(2)
	session.receive_player_info(2, "Maya", 3)

func _slot_by_peer(peer_id: int):
	for s in session.players:
		if s.peer_id == peer_id:
			return s
	return null

func test_reconnect_with_matching_token_restores_slot():
	var original_token = _slot_by_peer(2).reconnect_token
	var original_name = _slot_by_peer(2).name
	transport.emit_peer_left(2)
	assert_false(_slot_by_peer(2).connected)
	assert_eq(session.state, NetSessionState.State.PAUSED)

	# Reconnect with the token, new peer_id 4 from signaling
	signaling.emit_peer_arriving(4, original_token)

	# Slot is now under peer_id 4, retaining name/color
	assert_null(_slot_by_peer(2), "old peer_id should be gone")
	var restored = _slot_by_peer(4)
	assert_not_null(restored)
	assert_eq(restored.name, original_name)
	assert_eq(restored.color_index, 3)
	assert_true(restored.connected)
	assert_eq(session.state, NetSessionState.State.LOBBY,
		"back to pre_pause_state")

func test_reconnect_with_wrong_token_treated_as_new_join():
	transport.emit_peer_left(2)
	signaling.emit_peer_arriving(4, "wrong-token")
	# Not a reconnect - host should call transport.add_peer to begin SDP for a new join
	assert_eq(transport.add_peer_calls, [4])
	# Original slot is still in disconnected state
	assert_false(_slot_by_peer(2).connected)

func test_reconnect_when_no_disconnected_slots_is_normal_join():
	signaling.emit_peer_arriving(5, "abc")
	assert_eq(transport.add_peer_calls, [5])

func test_reconnect_with_matching_token_re_establishes_webrtc():
	var original_token = _slot_by_peer(2).reconnect_token
	transport.emit_peer_left(2)
	# Reconnect with the token, new peer_id 4 from signaling.
	signaling.emit_peer_arriving(4, original_token)
	# Even on a successful reconnect, host must call transport.add_peer
	# so WebRTC re-establishes the data channel for the new peer_id.
	assert_true(transport.add_peer_calls.has(4),
		"add_peer must be invoked for the reconnected joiner id")
