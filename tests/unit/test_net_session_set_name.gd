extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
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

func _slot(peer_id: int):
	for s in session.players:
		if s.peer_id == peer_id:
			return s
	return null

func test_set_name_routes_through_host_validator():
	session.set_name("Maya")
	assert_eq(_slot(1).name, "Maya")

func test_set_name_truncates_long_names():
	session.set_name("x".repeat(50))
	assert_eq(_slot(1).name.length(), 16)

func test_set_name_empty_falls_back_to_player_n():
	session.set_name("")
	assert_eq(_slot(1).name, "Player 1")
