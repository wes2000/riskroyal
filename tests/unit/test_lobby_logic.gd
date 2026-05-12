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

func test_on_name_submitted_calls_set_name():
	var session = _make_session()
	var lobby = Lobby.new()
	lobby.session = session
	lobby._on_name_submitted("Maya")
	var slot = session.players[0]
	assert_eq(slot.name, "Maya")

func test_on_color_picked_calls_set_color():
	var session = _make_session()
	var lobby = Lobby.new()
	lobby.session = session
	lobby._on_color_picked(4)
	var slot = session.players[0]
	assert_eq(slot.color_index, 4)

func test_on_ready_toggled_calls_set_ready():
	var session = _make_session()
	var lobby = Lobby.new()
	lobby.session = session
	lobby._on_ready_toggled(true)
	var slot = session.players[0]
	assert_true(slot.ready)

func test_start_button_visible_only_for_host():
	var session = _make_session()
	# session.is_host == true after host_session()
	assert_true(Lobby.should_show_start_button(session))

func test_start_button_hidden_for_joiner():
	var t = FakeTransport.new()
	var s = FakeSignalingClient.new()
	var joiner = NetSession.new(t, s)
	joiner.join_session("ABC234")
	assert_false(Lobby.should_show_start_button(joiner))

func test_start_button_enabled_only_when_all_ready_and_2_plus_players():
	var session = _make_session()
	# Just host, not ready
	assert_false(Lobby.is_start_button_enabled(session))
	# Add a joiner
	session._transport.emit_peer_joined(2)
	session.receive_player_info(2, "Maya", 3)
	assert_false(Lobby.is_start_button_enabled(session))  # nobody ready
	session.receive_set_ready(1, true)
	session.receive_set_ready(2, true)
	assert_true(Lobby.is_start_button_enabled(session))

func test_on_start_pressed_calls_start_match():
	var session = _make_session()
	session._transport.emit_peer_joined(2)
	session.receive_player_info(2, "Maya", 3)
	session.receive_set_ready(1, true)
	session.receive_set_ready(2, true)
	var lobby = Lobby.new()
	lobby.session = session
	var emitted = [null]
	session.match_starting.connect(func(ms): emitted[0] = ms)
	lobby._on_start_pressed()
	assert_not_null(emitted[0])

func test_on_kick_pressed_calls_kick():
	var session = _make_session()
	session._transport.emit_peer_joined(2)
	session.receive_player_info(2, "Maya", 3)
	var lobby = Lobby.new()
	lobby.session = session
	lobby._on_kick_pressed(2)
	assert_null(_find_slot(session, 2))

func _find_slot(session, peer_id: int):
	for s in session.players:
		if s.peer_id == peer_id:
			return s
	return null

func test_pause_overlay_hidden_in_lobby_state():
	var session = _make_session()
	assert_false(Lobby.should_show_pause_overlay(session.state))

func test_pause_overlay_shown_in_paused_state():
	assert_true(Lobby.should_show_pause_overlay(3))  # NetSessionState.State.PAUSED == 3

func test_format_pause_message_lists_disconnected_player():
	var s1 = PlayerSlot.new()
	s1.name = "Host"; s1.connected = true
	var s2 = PlayerSlot.new()
	s2.name = "Maya"; s2.connected = false
	var msg = Lobby.format_pause_message([s1, s2])
	assert_true("Maya" in msg)

func test_format_pause_message_handles_no_disconnected():
	var s1 = PlayerSlot.new()
	s1.name = "Host"; s1.connected = true
	var msg = Lobby.format_pause_message([s1])
	assert_true("paused" in msg.to_lower())
