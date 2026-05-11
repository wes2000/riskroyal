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

func _slot(peer_id: int):
	for s in session.players:
		if s.peer_id == peer_id:
			return s
	return null

func test_grace_timeout_removes_disconnected_slot_and_resumes():
	transport.emit_peer_left(2)
	assert_eq(session.state, NetSessionState.State.PAUSED)

	# Synchronously fire the grace timer
	session._on_grace_timeout()

	assert_null(_slot(2), "slot removed after timeout")
	assert_eq(session.state, NetSessionState.State.LOBBY)
	assert_eq(session.players.size(), 1)

func test_grace_timeout_with_no_disconnected_slots_is_noop():
	# If somehow the timer fires when nothing is disconnected, do nothing.
	var initial = session.players.size()
	session._on_grace_timeout()
	assert_eq(session.players.size(), initial)
	assert_eq(session.state, NetSessionState.State.LOBBY)

func test_grace_timeout_on_client_after_host_left_ends_session():
	var client = NetSession.new(FakeTransport.new(), FakeSignalingClient.new())
	client.join_session("ABC234")
	client.state = NetSessionState.State.LOBBY
	client._signaling.emit_host_left()
	assert_eq(client.state, NetSessionState.State.PAUSED)

	var ended_reasons = []
	client.session_ended.connect(func(r): ended_reasons.append(r))
	client._on_grace_timeout()

	assert_eq(client.state, NetSessionState.State.IDLE)
	assert_eq(ended_reasons, ["host_lost"])
