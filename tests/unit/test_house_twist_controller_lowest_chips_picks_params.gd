extends GutTest

const HouseTwistController = preload("res://scripts/match/house_twist_controller.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _new_state_with_chips(chips_array: Array, seat_indices: Array = []) -> RefCounted:
	var s = MatchState.new()
	for i in chips_array.size():
		var p = MatchPlayer.new()
		p.peer_id = i + 1
		p.seat_index = seat_indices[i] if i < seat_indices.size() else i
		p.chips = chips_array[i]
		s.players.append(p)
	s.rng_seed = 1
	s.seed_rng()
	return s

func test_compute_lowest_chips_picks_params_identifies_lowest_chips_player():
	var s = _new_state_with_chips([700, 300, 500])  # P2 is lowest
	var params = HouseTwistController.compute_twist_params("lowest_chips_picks", s)
	assert_eq(int(params.get("picker_peer_id", 0)), 2,
		"picker_peer_id must be the lowest-chips player")
	assert_eq(int(params.get("timeout_sec", 0)), 10,
		"timeout_sec defaults to 10 per spec § 7.5")

func test_compute_lowest_chips_picks_params_tie_breaks_by_seat_index():
	# P1 and P3 both have 300 chips; P1 has seat_index 0, P3 has seat_index 2.
	# Tie-break is LOWEST seat_index, so P1 wins.
	var s = _new_state_with_chips([300, 700, 300], [0, 1, 2])
	var params = HouseTwistController.compute_twist_params("lowest_chips_picks", s)
	assert_eq(int(params.get("picker_peer_id", 0)), 1,
		"tie-break must pick lowest seat_index (P1 over P3)")

func test_compute_lowest_chips_picks_options_is_shuffled_event_pool():
	var s = _new_state_with_chips([700, 300, 500])
	var params = HouseTwistController.compute_twist_params("lowest_chips_picks", s)
	var options: Array = params.get("options", [])
	assert_eq(options.size(), MatchConfig.EVENT_POOL.size(),
		"options size matches EVENT_POOL size")
	for entry in options:
		assert_true(MatchConfig.EVENT_POOL.has(entry),
			"each option is an EVENT_POOL member: %s" % entry)
