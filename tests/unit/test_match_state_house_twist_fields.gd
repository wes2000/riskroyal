extends GutTest

const MatchState = preload("res://scripts/match/match_state.gd")

func test_house_twist_defaults_empty_dict():
	var s = MatchState.new()
	assert_eq(s.house_twist, {})

func test_last_twist_type_defaults_empty_string():
	var s = MatchState.new()
	assert_eq(s.last_twist_type, "")

func test_previous_event_id_defaults_empty_string():
	var s = MatchState.new()
	assert_eq(s.previous_event_id, "")

func test_round_trip_preserves_house_twist_fields():
	var s = MatchState.new()
	s.house_twist = {"type": "double_bounty", "params": {"reward_multiplier": 2.0}}
	s.last_twist_type = "double_bounty"
	s.previous_event_id = "res://scenes/events/rocket_clash/rocket_clash_event.tscn"
	var d = s.to_dict()
	var s2 = MatchState.from_dict(d)
	assert_eq(s2.house_twist.get("type", ""), "double_bounty")
	assert_almost_eq(float(s2.house_twist.get("params", {}).get("reward_multiplier", 0.0)), 2.0, 0.001)
	assert_eq(s2.last_twist_type, "double_bounty")
	assert_eq(s2.previous_event_id, "res://scenes/events/rocket_clash/rocket_clash_event.tscn")
