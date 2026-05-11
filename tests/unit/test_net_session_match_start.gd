extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
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
	session.receive_set_ready(1, true)
	session.receive_set_ready(2, true)

func test_start_match_requires_host():
	var joiner = NetSession.new(FakeTransport.new(), FakeSignalingClient.new())
	joiner.join_session("ABC234")
	var ok = joiner.start_match()
	assert_false(ok)

func test_start_match_requires_min_two_players():
	var solo = NetSession.new(FakeTransport.new(), FakeSignalingClient.new())
	solo.host_session()
	solo._signaling.emit_code_issued("SOLOAA")
	solo.receive_set_ready(1, true)
	assert_false(solo.start_match())

func test_start_match_requires_all_ready():
	session.receive_set_ready(2, false)
	assert_false(session.start_match())

func test_start_match_emits_match_starting_with_correct_payload():
	var emitted_payloads = []
	session.match_starting.connect(func(ms): emitted_payloads.append(ms))
	var ok = session.start_match()
	assert_true(ok)
	assert_eq(emitted_payloads.size(), 1)
	var ms = emitted_payloads[0]
	assert_eq(ms.host_peer_id, 1)
	assert_eq(ms.seats.size(), 2)
	assert_ne(ms.rng_seed, 0, "seed should be non-zero (vanishingly unlikely to be 0)")
	assert_eq(ms.mode, "quick_clash")

func test_start_match_transitions_to_match_state():
	session.start_match()
	assert_eq(session.state, NetSessionState.State.MATCH)

func test_start_match_calls_signaling_send_start_match():
	session.start_match()
	assert_eq(signaling.send_start_match_calls, 1)
