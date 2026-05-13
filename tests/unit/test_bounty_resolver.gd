extends GutTest

const BountyResolver = preload("res://scripts/match/bounty_resolver.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const EventResult = preload("res://scripts/events/event_result.gd")

func _new_state_with_players(chip_heat_pairs: Array) -> RefCounted:
	var s = MatchState.new()
	for pair in chip_heat_pairs:
		var p = MatchPlayer.new()
		p.peer_id = pair[0]; p.chips = pair[1]; p.heat = pair[2]
		s.players.append(p)
	s.event_index = 1
	return s

func test_compute_leader_targets_chip_leader():
	var s = _new_state_with_players([[1, 500, 2], [2, 900, 1], [3, 700, 3]])
	var leader = BountyResolver.find_chip_leader_peer_id(s)
	assert_eq(leader, 2)

func test_compute_heat_leader_targets_heat_leader():
	var s = _new_state_with_players([[1, 500, 4], [2, 500, 2], [3, 500, 7]])
	var leader = BountyResolver.find_heat_leader_peer_id(s)
	assert_eq(leader, 3)

func test_auto_place_skipped_at_event_zero():
	var s = _new_state_with_players([[1, 500, 0], [2, 500, 0]])
	s.event_index = 0
	var placed = BountyResolver.auto_place(s)
	assert_eq(placed.size(), 0)
	assert_eq(s.bounties.size(), 0)

func test_auto_place_creates_2_bounties():
	var s = _new_state_with_players([[1, 500, 4], [2, 900, 2]])
	var placed = BountyResolver.auto_place(s)
	assert_eq(placed.size(), 2)
	assert_eq(s.bounties.size(), 2)
	assert_eq(placed[0].origin, "leader")
	assert_eq(placed[0].target, 2)  # chip leader
	assert_eq(placed[1].origin, "heat")
	assert_eq(placed[1].target, 1)  # heat leader

func test_resolve_awards_single_claimant():
	var s = _new_state_with_players([[1, 500, 0], [2, 500, 0]])
	var Bounty = load("res://scripts/match/bounty.gd")
	var b = Bounty.new()
	b.origin = "leader"; b.target = 1; b.condition = "bust"; b.reward_chips = 150
	s.bounties = [b]
	var r = EventResult.new()
	r.per_player[1] = {"chip_delta": -100, "bust": true, "crown_delta": 0, "heat_delta": 0, "cash_out_at": 0.0}
	r.per_player[2] = {"chip_delta": 100, "bust": false, "crown_delta": 0, "heat_delta": 0, "cash_out_at": 2.0}
	var awards = BountyResolver.resolve(s, r)
	assert_eq(awards.size(), 1)
	assert_eq(awards[0].claimant_peer_id, 2)
	assert_eq(awards[0].reward_chips, 150)
	assert_eq(s.players[1].chips, 650, "claimant chips updated in state")
	assert_eq(s.bounties, [], "cleared")
