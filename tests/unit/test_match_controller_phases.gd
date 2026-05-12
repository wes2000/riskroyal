extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start(player_count: int) -> RefCounted:
	var ms = MatchStart.new()
	for i in player_count:
		var s = PlayerSlot.new()
		s.peer_id = i + 1
		s.seat_index = i
		s.name = "P%d" % (i + 1)
		ms.seats.append(s)
	ms.host_peer_id = 1
	ms.rng_seed = 1
	return ms

func _new_controller() -> MatchController:
	var c = MatchController.new(true, null)
	c.start_match(_build_match_start(2))
	return c

func test_house_reveal_advances_to_ante():
	var c = _new_controller()
	c._advance_phase()
	assert_eq(c.state.phase, MatchPhase.Phase.ANTE)

func test_bet_loadout_advances_to_main_event():
	var c = _new_controller()
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c._advance_phase()
	assert_eq(c.state.phase, MatchPhase.Phase.MAIN_EVENT)

func test_shop_advances_to_house_twist():
	var c = _new_controller()
	c.state.phase = MatchPhase.Phase.SHOP
	c._advance_phase()
	assert_eq(c.state.phase, MatchPhase.Phase.HOUSE_TWIST)

func test_house_twist_increments_event_and_returns_to_house_reveal():
	var c = _new_controller()
	c.state.phase = MatchPhase.Phase.HOUSE_TWIST
	c.state.event_index = 2
	c._advance_phase()
	assert_eq(c.state.event_index, 3)
	assert_eq(c.state.phase, MatchPhase.Phase.HOUSE_REVEAL)

func test_house_twist_on_final_event_transitions_to_match_end():
	var c = _new_controller()
	c.state.phase = MatchPhase.Phase.HOUSE_TWIST
	c.state.event_index = 4  # last event in Quick Clash
	c._advance_phase()
	assert_eq(c.state.event_index, 4, "event_index does not increment past last")
	assert_eq(c.state.phase, MatchPhase.Phase.MATCH_END)

func test_advance_phase_emits_phase_changed():
	var c = _new_controller()
	var phases: Array = []
	c.phase_changed.connect(func(p): phases.append(p))
	c._advance_phase()
	assert_true(MatchPhase.Phase.ANTE in phases)
