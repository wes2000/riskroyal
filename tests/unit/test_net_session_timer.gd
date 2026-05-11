extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")
const FakeTimer = preload("res://tests/fakes/fake_timer.gd")

var transport
var signaling
var timer
var session

func before_each():
	transport = FakeTransport.new()
	signaling = FakeSignalingClient.new()
	timer = FakeTimer.new()
	session = NetSession.new(transport, signaling, timer)
	session.host_session()
	signaling.emit_code_issued("ABC234")
	transport.emit_peer_joined(2)
	session.receive_player_info(2, "Maya", 3)

func test_peer_left_starts_grace_timer():
	transport.emit_peer_left(2)
	assert_eq(timer.start_calls, 1)
	assert_true(timer.running)

func test_reconnect_within_grace_stops_timer():
	var tok = session.players[1].reconnect_token
	transport.emit_peer_left(2)
	assert_true(timer.running)
	signaling.emit_peer_arriving(4, tok)
	assert_false(timer.running)
	assert_eq(timer.stop_calls, 1)

func test_timer_timeout_invokes_grace_resolution():
	transport.emit_peer_left(2)
	assert_eq(session.players.size(), 2)
	timer.emit_timeout()
	assert_eq(session.players.size(), 1, "disconnected slot removed")
	assert_eq(session.state, NetSessionState.State.LOBBY)

func test_constructor_without_timer_still_works():
	# Legacy tests construct NetSession.new(transport, signaling).
	var t = FakeTransport.new()
	var s = FakeSignalingClient.new()
	var sess = NetSession.new(t, s)
	sess.host_session()
	s.emit_code_issued("AAAAAA")
	t.emit_peer_joined(2)
	t.emit_peer_left(2)
	sess._on_grace_timeout()
	assert_true(true)
