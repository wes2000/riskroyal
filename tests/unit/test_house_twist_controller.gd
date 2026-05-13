extends GutTest

const HouseTwistController = preload("res://scripts/match/house_twist_controller.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _new_state_with_players(chips_array: Array) -> RefCounted:
	var s = MatchState.new()
	for i in chips_array.size():
		var p = MatchPlayer.new()
		p.peer_id = i + 1
		p.seat_index = i
		p.chips = chips_array[i]
		s.players.append(p)
	s.rng_seed = 1
	s.seed_rng()
	return s

func test_select_next_twist_picks_from_plan_a_pool_when_no_history():
	var s = _new_state_with_players([500, 700, 600])  # unequal chips → all twists eligible
	var twist = HouseTwistController.select_next_twist(s)
	assert_true(twist.get("type", "") in HouseTwistController.PLAN_A_TWISTS,
		"Plan A: selected twist must be in PLAN_A_TWISTS subset")

func test_select_next_twist_excludes_last_twist_type():
	# Run select 20 times after seeding last_twist_type; should NEVER return that type.
	var s = _new_state_with_players([500, 700, 600])
	s.last_twist_type = "double_bounty"
	for i in 20:
		s.seed_rng()
		s.rng.seed = i + 1
		var twist = HouseTwistController.select_next_twist(s)
		assert_ne(twist.get("type", ""), "double_bounty",
			"no-repeat filter must exclude last_twist_type")

func test_select_next_twist_excludes_lowest_chips_picks_when_equal_chips():
	var s = _new_state_with_players([500, 500, 500])  # all equal
	for i in 20:
		s.seed_rng()
		s.rng.seed = i + 1
		var twist = HouseTwistController.select_next_twist(s)
		assert_ne(twist.get("type", ""), "lowest_chips_picks",
			"filter must exclude lowest_chips_picks when chips equal")

func test_select_next_twist_excludes_leader_cursed_when_equal_chips():
	var s = _new_state_with_players([500, 500, 500])
	for i in 20:
		s.seed_rng()
		s.rng.seed = i + 1
		var twist = HouseTwistController.select_next_twist(s)
		assert_ne(twist.get("type", ""), "leader_cursed",
			"filter must exclude leader_cursed when chips equal")

func test_select_next_twist_deterministic_with_same_seed():
	var s1 = _new_state_with_players([500, 700, 600])
	var s2 = _new_state_with_players([500, 700, 600])
	# Both RNGs seeded identically by _new_state_with_players
	for i in 5:
		var t1 = HouseTwistController.select_next_twist(s1)
		var t2 = HouseTwistController.select_next_twist(s2)
		assert_eq(t1.get("type", ""), t2.get("type", ""),
			"same seed produces same twist sequence")

func test_compute_twist_params_leader_cursed_identifies_chip_leader():
	var s = _new_state_with_players([500, 900, 700])  # P2 is leader
	var params = HouseTwistController.compute_twist_params("leader_cursed", s)
	assert_eq(int(params.get("leader_peer_id", 0)), 2)
	assert_almost_eq(float(params.get("reward_multiplier", 0.0)), 0.75, 0.001)

func test_compute_twist_params_double_bounty_carries_multipliers():
	var s = _new_state_with_players([500, 500])
	var params = HouseTwistController.compute_twist_params("double_bounty", s)
	assert_almost_eq(float(params.get("reward_multiplier", 0.0)), 2.0, 0.001)
	assert_almost_eq(float(params.get("place_bounty_discount", 0.0)), 0.25, 0.001)

func test_apply_pre_event_effects_power_surge_deals_bonus_cards():
	var s = _new_state_with_players([500, 500])
	for p in s.players:
		p.hand = []  # ensure empty starting hand
	var twist = {"type": "power_surge", "params": {}}
	HouseTwistController.apply_pre_event_effects(s, twist)
	# Each active player should now have 1 bonus card in hand
	for p in s.players:
		assert_eq(p.hand.size(), 1, "%s should receive 1 bonus card" % p.name)
	var dealt = twist["params"].get("cards_dealt", {})
	assert_eq(dealt.size(), s.players.size(), "cards_dealt must have one entry per active player")

func test_apply_pre_event_effects_no_op_for_state_only_twists():
	var s = _new_state_with_players([500, 500])
	for p in s.players:
		p.hand = []
	var twist = {"type": "double_bounty", "params": {"reward_multiplier": 2.0}}
	HouseTwistController.apply_pre_event_effects(s, twist)
	# State-only twists shouldn't mutate hands
	for p in s.players:
		assert_eq(p.hand.size(), 0)
