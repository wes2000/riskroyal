extends GutTest

const EventResult = preload("res://scripts/events/event_result.gd")

func test_defaults():
	var r = EventResult.new()
	assert_eq(r.event_id, "")
	assert_eq(r.per_player, {})
	assert_eq(r.painful_reveal, {})

func test_delta_for_returns_zero_for_missing_peer():
	var r = EventResult.new()
	assert_eq(r.chip_delta_for(99), 0)
	assert_eq(r.crown_delta_for(99), 0)
	assert_eq(r.heat_delta_for(99), 0)
	assert_false(r.bust_for(99))

func test_delta_for_returns_dict_values():
	var r = EventResult.new()
	r.per_player = {
		2: {"chip_delta": 100, "crown_delta": 1, "heat_delta": 2, "bust": false, "cash_out_at": 3.5},
	}
	assert_eq(r.chip_delta_for(2), 100)
	assert_eq(r.crown_delta_for(2), 1)
	assert_eq(r.heat_delta_for(2), 2)
	assert_false(r.bust_for(2))

func test_round_trip():
	var r = EventResult.new()
	r.event_id = "test_event"
	r.per_player = {
		1: {"chip_delta": 0, "crown_delta": 1, "heat_delta": 1, "bust": false, "cash_out_at": 0.0},
		2: {"chip_delta": -50, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0},
	}
	r.painful_reveal = {"winner": 1, "crash_at": 1.85}
	var d = r.to_dict()
	var r2 = EventResult.from_dict(d)
	assert_eq(r2.event_id, "test_event")
	assert_eq(r2.crown_delta_for(1), 1)
	assert_true(r2.bust_for(2))
	assert_eq(r2.painful_reveal.winner, 1)
