extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")
const EventResult = preload("res://scripts/events/event_result.gd")
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

func _new_controller() -> MatchController:
	var c = MatchController.new(true, null)
	c.start_match(_build_match_start(3))
	return c

func test_bounty_heat_applies_heat_deltas():
	var c = _new_controller()
	var r = EventResult.new()
	r.per_player = {
		1: {"chip_delta": 0, "crown_delta": 0, "heat_delta": 2, "bust": false, "cash_out_at": 0.0},
		2: {"chip_delta": 0, "crown_delta": 0, "heat_delta": -1, "bust": false, "cash_out_at": 0.0},
	}
	c.state.current_result = r
	c.state.phase = MatchPhase.Phase.BOUNTY_HEAT_UPDATE
	c._enter_phase_behavior()
	assert_eq(c.state.players[0].heat, 2)
	assert_eq(c.state.players[1].heat, 0, "heat clamps to 0")

func test_heat_clamps_to_max():
	var c = _new_controller()
	c.state.players[0].heat = 9
	var r = EventResult.new()
	r.per_player = {1: {"chip_delta": 0, "crown_delta": 0, "heat_delta": 5, "bust": false, "cash_out_at": 0.0}}
	c.state.current_result = r
	c.state.phase = MatchPhase.Phase.BOUNTY_HEAT_UPDATE
	c._enter_phase_behavior()
	assert_eq(c.state.players[0].heat, MatchConfig.HEAT_MAX)

func test_match_end_emits_rankings_sorted_by_crowns():
	var c = _new_controller()
	assert_eq(c.state.players.size(), 3, "Controller should have 3 players")
	c.state.players[0].crowns = 2
	c.state.players[1].crowns = 5
	c.state.players[2].crowns = 3
	var rankings = [null]
	c.match_ended.connect(func(r): rankings[0] = r)
	c.state.phase = MatchPhase.Phase.MATCH_END
	c._enter_phase_behavior()
	assert_eq(rankings[0].size(), 3)
	assert_eq(rankings[0][0].peer_id, 2)
	assert_eq(rankings[0][1].peer_id, 3)
	assert_eq(rankings[0][2].peer_id, 1)

func test_match_end_breaks_ties_by_chips_then_heat():
	var c = _new_controller()
	c.state.players[0].crowns = 3; c.state.players[0].chips = 500; c.state.players[0].heat = 2
	c.state.players[1].crowns = 3; c.state.players[1].chips = 700; c.state.players[1].heat = 1
	c.state.players[2].crowns = 3; c.state.players[2].chips = 700; c.state.players[2].heat = 5
	var rankings = [null]
	c.match_ended.connect(func(r): rankings[0] = r)
	c.state.phase = MatchPhase.Phase.MATCH_END
	c._enter_phase_behavior()
	# All tied on crowns. chips DESC: P2 and P3 tied at 700, P1 at 500.
	# heat DESC tiebreak: P3 (5) > P2 (1)
	assert_eq(rankings[0][0].peer_id, 3)
	assert_eq(rankings[0][1].peer_id, 2)
	assert_eq(rankings[0][2].peer_id, 1)
