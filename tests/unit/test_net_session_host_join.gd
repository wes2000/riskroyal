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

func test_initial_state():
	assert_eq(session.state, NetSessionState.State.IDLE)
	assert_false(session.is_host)
	assert_eq(session.local_peer_id, 0)
	assert_eq(session.players.size(), 0)
	assert_eq(session.code, "")

func test_host_session_requests_code_and_starts_transport():
	session.host_session()
	assert_eq(signaling.request_code_calls, 1)
	assert_true(transport.is_hosting)
	assert_true(session.is_host)
	assert_eq(session.state, NetSessionState.State.IDLE,
		"stays idle until code issued")

func test_code_issued_moves_to_lobby_and_creates_host_slot():
	session.host_session()
	signaling.emit_code_issued("ABC234")
	assert_eq(session.state, NetSessionState.State.LOBBY)
	assert_eq(session.code, "ABC234")
	assert_eq(session.local_peer_id, 1)
	assert_eq(session.players.size(), 1)
	assert_true(session.players[0].is_host)
	assert_eq(session.players[0].peer_id, 1)
	assert_eq(session.players[0].seat_index, 0)

func test_join_session_connects_to_code():
	session.join_session("ABC234")
	assert_eq(signaling.connect_to_code_calls.size(), 1)
	assert_eq(signaling.connect_to_code_calls[0].code, "ABC234")
	assert_false(session.is_host)

func test_leave_session_closes_transport_and_signaling():
	session.host_session()
	signaling.emit_code_issued("ABC234")
	session.leave_session()
	assert_true(transport.closed)
	assert_true(signaling.closed)
	assert_eq(session.state, NetSessionState.State.IDLE)
	assert_eq(session.players.size(), 0)
	assert_eq(session.code, "")
