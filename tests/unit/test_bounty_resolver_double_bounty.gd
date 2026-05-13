extends GutTest

const BountyResolver = preload("res://scripts/match/bounty_resolver.gd")
const Bounty = preload("res://scripts/match/bounty.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const EventResult = preload("res://scripts/events/event_result.gd")

func _new_state_with_2_players() -> RefCounted:
	var s = MatchState.new()
	for i in 2:
		var p = MatchPlayer.new()
		p.peer_id = i + 1; p.seat_index = i; p.chips = 500
		s.players.append(p)
	return s

func test_resolve_double_bounty_multiplier_applied():
	var s = _new_state_with_2_players()
	var b = Bounty.new()
	b.origin = "leader"; b.target = 1; b.condition = "bust"; b.reward_chips = 150
	s.bounties = [b]
	s.house_twist = {"type": "double_bounty", "params": {"reward_multiplier": 2.0}}
	var r = EventResult.new()
	r.per_player[1] = {"chip_delta": -100, "bust": true, "crown_delta": 0, "heat_delta": 0, "cash_out_at": 0.0}
	r.per_player[2] = {"chip_delta": 100, "bust": false, "crown_delta": 0, "heat_delta": 0, "cash_out_at": 2.0}
	var awards = BountyResolver.resolve(s, r)
	assert_eq(awards.size(), 1)
	assert_eq(awards[0].claimant_peer_id, 2)
	assert_eq(awards[0].reward_chips, 300, "150 × 2.0 = 300")

func test_resolve_no_double_bounty_unchanged():
	var s = _new_state_with_2_players()
	var b = Bounty.new()
	b.origin = "leader"; b.target = 1; b.condition = "bust"; b.reward_chips = 150
	s.bounties = [b]
	# No house_twist active
	var r = EventResult.new()
	r.per_player[1] = {"chip_delta": -100, "bust": true, "crown_delta": 0, "heat_delta": 0, "cash_out_at": 0.0}
	r.per_player[2] = {"chip_delta": 100, "bust": false, "crown_delta": 0, "heat_delta": 0, "cash_out_at": 2.0}
	var awards = BountyResolver.resolve(s, r)
	assert_eq(awards[0].reward_chips, 150, "no twist: base reward unchanged")
	assert_eq(s.players[1].chips, 650, "claimant chips updated in state (500 base + 150 reward)")

func test_resolve_empty_house_twist_does_not_crash():
	# Regression guard: state.house_twist = {} is reachable (cleanup path
	# in match_controller). The defensive .get("params", {}) chain prevents
	# a crash; this test locks in that behavior.
	var s = _new_state_with_2_players()
	var b = Bounty.new()
	b.origin = "leader"; b.target = 1; b.condition = "bust"; b.reward_chips = 150
	s.bounties = [b]
	s.house_twist = {}  # cleared/no-twist state
	var r = EventResult.new()
	r.per_player[1] = {"chip_delta": -100, "bust": true, "crown_delta": 0, "heat_delta": 0, "cash_out_at": 0.0}
	r.per_player[2] = {"chip_delta": 100, "bust": false, "crown_delta": 0, "heat_delta": 0, "cash_out_at": 2.0}
	var awards = BountyResolver.resolve(s, r)
	assert_eq(awards[0].reward_chips, 150, "empty house_twist: base reward unchanged, no crash")
