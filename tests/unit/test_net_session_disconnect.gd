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

func _slot(peer_id: int):
	for s in session.players:
		if s.peer_id == peer_id:
			return s
	return null

func test_peer_left_marks_slot_disconnected():
	transport.emit_peer_left(2)
	var s = _slot(2)
	assert_not_null(s, "slot retained for grace period")
	assert_false(s.connected)

func test_peer_left_pauses_session_and_records_pre_pause_state():
	transport.emit_peer_left(2)
	assert_eq(session.state, NetSessionState.State.PAUSED)
	assert_eq(session.pre_pause_state, NetSessionState.State.LOBBY)

func test_peer_left_in_match_state_pauses_and_records():
	session._set_state(NetSessionState.State.MATCH)
	transport.emit_peer_left(2)
	assert_eq(session.state, NetSessionState.State.PAUSED)
	assert_eq(session.pre_pause_state, NetSessionState.State.MATCH)

func test_host_left_signal_pauses_clients():
	var client = NetSession.new(FakeTransport.new(), FakeSignalingClient.new())
	client.join_session("ABC234")
	# Simulate client's local state being post-handshake by manually setting fields.
	client.state = NetSessionState.State.LOBBY
	client._signaling.emit_host_left()
	assert_eq(client.state, NetSessionState.State.PAUSED)

func test_peer_left_emits_state_changed():
	var emitted = []
	session.state_changed.connect(func(s): emitted.append(s))
	transport.emit_peer_left(2)
	assert_true(emitted.has(NetSessionState.State.PAUSED))
