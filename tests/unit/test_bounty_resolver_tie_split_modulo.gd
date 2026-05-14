extends GutTest

const BountyResolver = preload("res://scripts/match/bounty_resolver.gd")
const Bounty = preload("res://scripts/match/bounty.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const EventResult = preload("res://scripts/events/event_result.gd")

func _new_state_with_3_players() -> RefCounted:
	var s = MatchState.new()
	for i in 3:
		var p = MatchPlayer.new()
		p.peer_id = i + 1
		p.seat_index = i
		p.name = "P%d" % (i + 1)
		p.chips = 1000
		s.players.append(p)
	return s

func test_3_way_tie_split_assigns_remainder_to_lowest_seat_index():
	# Three claimants tie; reward = 100. 100 / 3 = 33 each + 1 remainder.
	# The +1 must go to the claimant with the lowest seat_index (P1, seat 0).
	var s = _new_state_with_3_players()
	# Bust the target so all 3 claimants' bust-bounty conditions fire.
	var target = MatchPlayer.new()
	target.peer_id = 99
	target.seat_index = 99
	target.name = "Target"
	s.players.append(target)
	var b = Bounty.new()
	b.origin = "leader"
	b.target = 99
	b.condition = "bust"
	b.reward_chips = 100  # forces 100 / 3 = 33 + 1 remainder
	b.placed_at_event = 1
	s.bounties = [b]

	var result = EventResult.new()
	result.event_id = "rocket_clash"
	result.per_player = {
		1: {"chip_delta": 0, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 5.0},
		2: {"chip_delta": 0, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 5.0},
		3: {"chip_delta": 0, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 5.0},
		99: {"chip_delta": -100, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0},
	}

	var awards = BountyResolver.resolve(s, result)

	# 3 awards expected, one per claimant
	assert_eq(awards.size(), 3, "exactly 3 awards (one per claimant)")
	var by_pid = {}
	for a in awards:
		by_pid[int(a.claimant_peer_id)] = int(a.reward_chips)
	assert_eq(by_pid.get(1, 0), 34, "P1 (lowest seat_index) gets 33 + 1 remainder = 34")
	assert_eq(by_pid.get(2, 0), 33, "P2 gets base share 33")
	assert_eq(by_pid.get(3, 0), 33, "P3 gets base share 33")
	assert_eq(by_pid.get(1, 0) + by_pid.get(2, 0) + by_pid.get(3, 0), 100,
		"sum of awards equals full reward (no chips lost to modulo)")
