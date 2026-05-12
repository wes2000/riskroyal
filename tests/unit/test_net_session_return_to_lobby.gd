extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")

func _host_session():
	var t = FakeTransport.new()
	var s = FakeSignalingClient.new()
	var session = NetSession.new(t, s)
	session.host_session()
	s.emit_code_issued("ABC234")
	return session

func test_return_to_lobby_requires_host():
	var t = FakeTransport.new()
	var s = FakeSignalingClient.new()
	var joiner = NetSession.new(t, s)
	joiner.join_session("ABC234")
	joiner.state = NetSessionState.State.MATCH
	joiner.return_to_lobby()
	assert_eq(joiner.state, NetSessionState.State.MATCH, "joiner should not transition")

func test_return_to_lobby_requires_match_state():
	var session = _host_session()
	# state is LOBBY after host_session + emit_code_issued
	session.return_to_lobby()
	assert_eq(session.state, NetSessionState.State.LOBBY, "no-op when not in MATCH")

func test_return_to_lobby_transitions_match_to_lobby():
	var session = _host_session()
	session.state = NetSessionState.State.MATCH  # simulate post-start_match
	session.return_to_lobby()
	assert_eq(session.state, NetSessionState.State.LOBBY)

func test_return_to_lobby_emits_state_changed():
	var session = _host_session()
	session.state = NetSessionState.State.MATCH
	var states: Array = []
	session.state_changed.connect(func(s): states.append(s))
	session.return_to_lobby()
	assert_true(NetSessionState.State.LOBBY in states)
