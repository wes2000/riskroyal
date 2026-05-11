extends GutTest

const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func test_defaults():
	var s = PlayerSlot.new()
	assert_eq(s.peer_id, 0)
	assert_eq(s.name, "")
	assert_eq(s.color_index, -1)
	assert_false(s.ready)
	assert_false(s.is_host)
	assert_true(s.connected)
	assert_eq(s.seat_index, -1)
	assert_eq(s.reconnect_token, "")

func test_to_dict_round_trip():
	var s = PlayerSlot.new()
	s.peer_id = 2
	s.name = "Maya"
	s.color_index = 3
	s.ready = true
	s.is_host = false
	s.connected = true
	s.seat_index = 1
	s.reconnect_token = "abc123"
	var d = s.to_dict()
	assert_eq(d.peer_id, 2)
	var s2 = PlayerSlot.from_dict(d)
	assert_eq(s2.peer_id, 2)
	assert_eq(s2.name, "Maya")
	assert_eq(s2.color_index, 3)
	assert_true(s2.ready)
	assert_eq(s2.seat_index, 1)
	assert_eq(s2.reconnect_token, "abc123")

func test_from_dict_handles_missing_fields():
	var s = PlayerSlot.from_dict({ "peer_id": 5, "name": "Solo" })
	assert_eq(s.peer_id, 5)
	assert_eq(s.name, "Solo")
	# Unspecified fields fall back to defaults.
	assert_eq(s.color_index, -1)
	assert_false(s.ready)
