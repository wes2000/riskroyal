extends GutTest

const HouseTwistController = preload("res://scripts/match/house_twist_controller.gd")
const MatchState = preload("res://scripts/match/match_state.gd")

func test_finalize_pending_params_maps_rocket_clash_to_cash_out_over_5x():
	var s = MatchState.new()
	s.house_twist = {"type": "sudden_death_jackpot", "params": {"condition": ""}}
	s.current_event_id = "res://scenes/events/rocket_clash/rocket_clash_event.tscn"
	HouseTwistController.finalize_pending_params(s)
	assert_eq(String(s.house_twist.params.get("condition", "")), "cash_out_over_5x")

func test_finalize_pending_params_maps_bomb_pot_to_pull_out_after_80_pct():
	var s = MatchState.new()
	s.house_twist = {"type": "sudden_death_jackpot", "params": {"condition": ""}}
	s.current_event_id = "res://scenes/events/bomb_pot/bomb_pot_event.tscn"
	HouseTwistController.finalize_pending_params(s)
	assert_eq(String(s.house_twist.params.get("condition", "")), "pull_out_after_80_pct")

func test_finalize_pending_params_maps_card_cannon_to_locked_at_perfect():
	var s = MatchState.new()
	s.house_twist = {"type": "sudden_death_jackpot", "params": {"condition": ""}}
	s.current_event_id = "res://scenes/events/card_cannon/card_cannon_event.tscn"
	HouseTwistController.finalize_pending_params(s)
	assert_eq(String(s.house_twist.params.get("condition", "")), "locked_at_perfect")

func test_finalize_pending_params_no_op_for_non_sudden_death():
	var s = MatchState.new()
	s.house_twist = {"type": "double_bounty", "params": {"reward_multiplier": 2.0}}
	s.current_event_id = "res://scenes/events/rocket_clash/rocket_clash_event.tscn"
	HouseTwistController.finalize_pending_params(s)
	# No mutation: reward_multiplier still 2.0, no condition key added
	assert_almost_eq(float(s.house_twist.params.get("reward_multiplier", 0.0)), 2.0, 0.001)
	assert_false(s.house_twist.params.has("condition"),
		"non-Sudden-Death twists are untouched")

func test_finalize_pending_params_no_op_when_no_twist_active():
	var s = MatchState.new()
	s.house_twist = {}
	s.current_event_id = "res://scenes/events/rocket_clash/rocket_clash_event.tscn"
	HouseTwistController.finalize_pending_params(s)
	assert_eq(s.house_twist, {}, "empty twist stays empty")
