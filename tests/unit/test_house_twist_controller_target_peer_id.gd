extends GutTest

# Alpha remediation Phase F §12.3: target_peer_id must be populated on
# the twist params dict (in addition to the existing per-twist alias
# fields leader_peer_id / picker_peer_id) so the announcer + overlay
# can resolve <Name> uniformly via state.find_player(target_peer_id).

const HouseTwistController = preload("res://scripts/match/house_twist_controller.gd")
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

func test_leader_cursed_params_carry_target_peer_id_equal_to_leader():
	var s = _new_state_with_chips([500, 900, 700])  # P2 is leader
	var params = HouseTwistController.compute_twist_params("leader_cursed", s)
	assert_eq(int(params.get("target_peer_id", 0)), 2,
		"target_peer_id mirrors leader_peer_id for leader_cursed")
	assert_eq(int(params.get("leader_peer_id", 0)), 2,
		"existing leader_peer_id field preserved (back-compat)")

func test_lowest_chips_picks_params_carry_target_peer_id_equal_to_picker():
	var s = _new_state_with_chips([700, 300, 500])  # P2 lowest
	var params = HouseTwistController.compute_twist_params("lowest_chips_picks", s)
	assert_eq(int(params.get("target_peer_id", 0)), 2,
		"target_peer_id mirrors picker_peer_id for lowest_chips_picks")
	assert_eq(int(params.get("picker_peer_id", 0)), 2,
		"existing picker_peer_id field preserved (back-compat)")

func test_other_twists_omit_target_peer_id():
	# double_bounty / no_insurance / power_surge / sudden_death_jackpot are
	# not name-required twists. target_peer_id should be absent or 0.
	var s = _new_state_with_chips([500, 700, 600])
	for twist_type in ["double_bounty", "no_insurance", "power_surge", "sudden_death_jackpot"]:
		var params = HouseTwistController.compute_twist_params(twist_type, s)
		assert_eq(int(params.get("target_peer_id", 0)), 0,
			"%s should not carry target_peer_id" % twist_type)
