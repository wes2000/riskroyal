extends GutTest

const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_seat(peer_id: int, name: String, seat: int) -> Object:
	var s = PlayerSlot.new()
	s.peer_id = peer_id
	s.name = name
	s.seat_index = seat
	return s

func test_defaults():
	var m = MatchStart.new()
	assert_eq(m.seats.size(), 0)
	assert_eq(m.host_peer_id, 0)
	assert_eq(m.rng_seed, 0)
	assert_eq(m.mode, "quick_clash")
	assert_eq(m.rules, {})

func test_to_dict_round_trip():
	var m = MatchStart.new()
	m.seats = [_build_seat(1, "Host", 0), _build_seat(2, "Joiner", 1)]
	m.host_peer_id = 1
	m.rng_seed = 0xDEADBEEF
	m.mode = "quick_clash"
	m.rules = { "no_sabotage": true }

	var d = m.to_dict()
	assert_eq(d.host_peer_id, 1)
	assert_eq(d.rng_seed, 0xDEADBEEF)
	assert_eq(d.seats.size(), 2)
	assert_eq(d.seats[0].name, "Host")

	var m2 = MatchStart.from_dict(d)
	assert_eq(m2.host_peer_id, 1)
	assert_eq(m2.rng_seed, 0xDEADBEEF)
	assert_eq(m2.seats.size(), 2)
	assert_eq(m2.seats[1].name, "Joiner")
	assert_eq(m2.rules, { "no_sabotage": true })
