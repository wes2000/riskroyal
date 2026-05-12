extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const EventResult = preload("res://scripts/events/event_result.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start(player_count: int) -> RefCounted:
	var ms = MatchStart.new()
	for i in player_count:
		var s = PlayerSlot.new()
		s.peer_id = i + 1; s.seat_index = i; s.name = "P%d" % (i + 1)
		ms.seats.append(s)
	ms.host_peer_id = 1; ms.rng_seed = 1
	return ms

func _new_host_with_fake() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(2))
	return {"controller": c, "fake": fake}

func test_auto_place_bounties_skipped_at_event_zero():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.event_index = 0
	c._auto_place_bounties()
	assert_eq(c.state.bounties.size(), 0, "event 0: no auto-placement")

func test_auto_place_bounties_places_leader_and_heat():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.players[0].chips = 1000
	c.state.players[1].chips = 500
	c.state.players[1].heat = 6
	c.state.event_index = 2
	c._auto_place_bounties()
	assert_eq(c.state.bounties.size(), 2)
	var origins = [c.state.bounties[0].origin, c.state.bounties[1].origin]
	assert_true("leader" in origins)
	assert_true("heat" in origins)

func test_auto_placed_leader_targets_chip_leader():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.players[0].chips = 500
	c.state.players[1].chips = 900
	c.state.event_index = 1
	c._auto_place_bounties()
	var leader_bounty = null
	for b in c.state.bounties:
		if b.origin == "leader":
			leader_bounty = b
			break
	assert_not_null(leader_bounty)
	assert_eq(leader_bounty.target, 2, "P2 has more chips -> leader bounty targets P2")

func test_auto_placed_heat_captures_target_heat():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.players[1].heat = 7
	c.state.event_index = 1
	c._auto_place_bounties()
	var heat_bounty = null
	for b in c.state.bounties:
		if b.origin == "heat":
			heat_bounty = b
			break
	assert_not_null(heat_bounty)
	assert_eq(heat_bounty.placed_at_target_heat, 7)

func test_resolve_bounties_awards_single_claimant():
	var d = _new_host_with_fake()
	var c = d.controller
	var Bounty = load("res://scripts/match/bounty.gd")
	var b = Bounty.new()
	b.origin = "leader"; b.target = 1; b.condition = "bust"
	b.reward_chips = 150; b.placed_at_target_heat = 0
	c.state.bounties = [b]
	var result = EventResult.new()
	result.per_player[1] = {"chip_delta": -100, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0}
	result.per_player[2] = {"chip_delta": 100, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 2.0}
	var p2_chips_before = c.state.players[1].chips
	c._resolve_bounties(result)
	assert_eq(c.state.players[1].chips, p2_chips_before + 150, "P2 collected 150 bounty")
	assert_eq(c.state.bounties, [], "bounties cleared after resolution")

func test_resolve_bounties_splits_on_tie():
	var d = _new_host_with_fake()
	var c = d.controller
	var p3 = MatchPlayer.new()
	p3.peer_id = 3; p3.name = "P3"; p3.chips = 100
	c.state.players.append(p3)
	var Bounty = load("res://scripts/match/bounty.gd")
	var b = Bounty.new()
	b.origin = "leader"; b.target = 1; b.condition = "bust"
	b.reward_chips = 150; b.placed_at_target_heat = 0
	c.state.bounties = [b]
	var result = EventResult.new()
	result.per_player[1] = {"chip_delta": -100, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0}
	result.per_player[2] = {"chip_delta": 100, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 2.0}
	result.per_player[3] = {"chip_delta": 100, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 1.5}
	var p2_chips_before = c.state.players[1].chips
	var p3_chips_before = c.state.players[2].chips
	c._resolve_bounties(result)
	assert_eq(c.state.players[1].chips, p2_chips_before + 75, "split: P2 gets 75")
	assert_eq(c.state.players[2].chips, p3_chips_before + 75, "split: P3 gets 75")
