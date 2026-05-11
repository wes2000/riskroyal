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

func _find_slot(peer_id: int):
	for s in session.players:
		if s.peer_id == peer_id:
			return s
	return null

func test_peer_join_creates_provisional_slot():
	transport.emit_peer_joined(2)
	assert_eq(session.players.size(), 2)
	var s = _find_slot(2)
	assert_not_null(s)
	assert_eq(s.name, "")
	assert_eq(s.color_index, -1)
	assert_eq(s.seat_index, 1)
	assert_true(s.connected)
	assert_false(s.is_host)
	assert_ne(s.reconnect_token, "", "host issues a reconnect token")

func test_receive_player_info_updates_slot():
	transport.emit_peer_joined(2)
	session.receive_player_info(2, "Maya", 3)
	var s = _find_slot(2)
	assert_eq(s.name, "Maya")
	assert_eq(s.color_index, 3)

func test_receive_player_info_rejects_duplicate_color():
	transport.emit_peer_joined(2)
	transport.emit_peer_joined(3)
	var ok1 = session.receive_player_info(2, "Maya", 3)
	var ok2 = session.receive_player_info(3, "Sam", 3)
	assert_true(ok1)
	assert_false(ok2)
	assert_eq(_find_slot(3).color_index, -1, "rejected slot keeps default")

func test_receive_player_info_rejects_unknown_peer():
	var ok = session.receive_player_info(99, "Ghost", 1)
	assert_false(ok)

func test_receive_player_info_truncates_long_name():
	transport.emit_peer_joined(2)
	var long_name = "x".repeat(50)
	session.receive_player_info(2, long_name, 1)
	var s = _find_slot(2)
	assert_eq(s.name.length(), 16)

func test_receive_player_info_replaces_empty_name():
	transport.emit_peer_joined(2)
	session.receive_player_info(2, "", 1)
	var s = _find_slot(2)
	assert_eq(s.name, "Player 2")

func test_peer_join_emits_players_changed():
	var emitted = []
	session.players_changed.connect(func(): emitted.append(true))
	transport.emit_peer_joined(2)
	assert_eq(emitted.size(), 1)
