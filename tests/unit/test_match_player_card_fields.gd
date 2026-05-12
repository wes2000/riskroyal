extends GutTest

const MatchPlayer = preload("res://scripts/match/match_player.gd")

func test_hand_defaults_empty():
	var p = MatchPlayer.new()
	assert_eq(p.hand, [])

func test_loadout_defaults_empty():
	var p = MatchPlayer.new()
	assert_eq(p.loadout, [])

func test_played_this_event_defaults_empty():
	var p = MatchPlayer.new()
	assert_eq(p.played_this_event, [])

func test_card_fields_round_trip():
	var p = MatchPlayer.new()
	p.peer_id = 1
	p.hand = ["insurance", "heat_shield", "multiplier_booster"]
	p.loadout = ["insurance", "heat_shield"]
	p.played_this_event = ["insurance"]
	var d = p.to_dict()
	var p2 = MatchPlayer.from_dict(d)
	assert_eq(p2.hand, ["insurance", "heat_shield", "multiplier_booster"])
	assert_eq(p2.loadout, ["insurance", "heat_shield"])
	assert_eq(p2.played_this_event, ["insurance"])

func test_to_dict_hand_is_independent():
	var p = MatchPlayer.new()
	p.hand = ["insurance"]
	var d = p.to_dict()
	p.hand.append("heat_shield")
	assert_eq(d["hand"], ["insurance"])

func test_from_dict_hand_is_independent():
	var d = {"hand": ["insurance"], "loadout": [], "played_this_event": []}
	var p = MatchPlayer.from_dict(d)
	d["hand"].append("heat_shield")
	assert_eq(p.hand, ["insurance"])
