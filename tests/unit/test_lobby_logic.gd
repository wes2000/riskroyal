extends GutTest

const Lobby = preload("res://scripts/ui/lobby.gd")
const NetSession = preload("res://scripts/net/net_session.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")

func _make_session():
	var t = FakeTransport.new()
	var s = FakeSignalingClient.new()
	var session = NetSession.new(t, s)
	session.host_session()
	s.emit_code_issued("ABC234")
	return session

func test_format_slot_for_empty_returns_placeholder():
	assert_eq(Lobby.format_slot_label(null), "(empty)")

func test_format_slot_for_filled_includes_name_and_color():
	var s = PlayerSlot.new()
	s.name = "Maya"
	s.color_index = 3
	s.ready = false
	assert_true("Maya" in Lobby.format_slot_label(s))
	assert_true("color 3" in Lobby.format_slot_label(s))

func test_format_slot_marks_ready():
	var s = PlayerSlot.new()
	s.name = "Maya"
	s.color_index = 3
	s.ready = true
	assert_true("READY" in Lobby.format_slot_label(s))

func test_format_slot_marks_host():
	var s = PlayerSlot.new()
	s.name = "Host"
	s.is_host = true
	assert_true("(host)" in Lobby.format_slot_label(s))

func test_format_slot_marks_disconnected():
	var s = PlayerSlot.new()
	s.name = "Maya"
	s.connected = false
	assert_true("disconnected" in Lobby.format_slot_label(s).to_lower())
