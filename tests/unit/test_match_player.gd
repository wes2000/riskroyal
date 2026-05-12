extends GutTest

const MatchPlayer = preload("res://scripts/match/match_player.gd")

func test_defaults():
	var p = MatchPlayer.new()
	assert_eq(p.peer_id, 0)
	assert_eq(p.seat_index, -1)
	assert_eq(p.name, "")
	assert_eq(p.color_index, -1)
	assert_eq(p.chips, 0)
	assert_eq(p.crowns, 0)
	assert_eq(p.heat, 0)
	assert_true(p.is_active_this_event)

func test_round_trip():
	var p = MatchPlayer.new()
	p.peer_id = 2
	p.seat_index = 1
	p.name = "Maya"
	p.color_index = 3
	p.chips = 600
	p.crowns = 2
	p.heat = 5
	p.is_active_this_event = false
	var d = p.to_dict()
	var p2 = MatchPlayer.from_dict(d)
	assert_eq(p2.peer_id, 2)
	assert_eq(p2.chips, 600)
	assert_eq(p2.crowns, 2)
	assert_eq(p2.heat, 5)
	assert_false(p2.is_active_this_event)

func test_from_dict_tolerates_missing_fields():
	var p = MatchPlayer.from_dict({"peer_id": 5})
	assert_eq(p.peer_id, 5)
	assert_eq(p.chips, 0)
	assert_true(p.is_active_this_event)
