extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")
const MockEvent = preload("res://tests/fakes/mock_event.gd")

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
	# Inject blocking mock so cascade from start_match stops at MAIN_EVENT.
	var mock = MockEvent.new()
	c._event_factory = func(_path): return mock
	c.start_match(_build_match_start(2))
	return c

func test_house_reveal_advances_to_ante():
	var c = _new_controller()
	# Plan B: _advance_phase(HOUSE_REVEAL) transitions to ANTE; ANTE then
	# cascades through the scheduler to MAIN_EVENT (mock blocks). Verify
	# the transition happened by tracking emitted phases.
	c.state.phase = MatchPhase.Phase.HOUSE_REVEAL
	var phases: Array = []
	c.phase_changed.connect(func(p): phases.append(p))
	c._advance_phase()
	assert_true(MatchPhase.Phase.ANTE in phases,
		"_advance_phase should emit ANTE when called from HOUSE_REVEAL")

func test_bet_loadout_advances_to_main_event():
	var c = _new_controller()
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c._advance_phase()
	assert_eq(c.state.phase, MatchPhase.Phase.MAIN_EVENT)

func test_shop_advances_to_house_twist():
	var c = _new_controller()
	# Plan B: SHOP -> HOUSE_TWIST cascades further (HOUSE_REVEAL -> ... ->
	# MAIN_EVENT). Verify the HOUSE_TWIST transition happened.
	c.state.phase = MatchPhase.Phase.SHOP
	var phases: Array = []
	c.phase_changed.connect(func(p): phases.append(p))
	c._advance_phase()
	assert_true(MatchPhase.Phase.HOUSE_TWIST in phases,
		"_advance_phase should transition through HOUSE_TWIST when called from SHOP")

func test_house_twist_increments_event_and_returns_to_house_reveal():
	var c = _new_controller()
	c.state.phase = MatchPhase.Phase.HOUSE_TWIST
	c.state.event_index = 2
	# Plan B: HOUSE_TWIST -> HOUSE_REVEAL cascades further to MAIN_EVENT.
	# Verify event_index was incremented (proving HOUSE_TWIST ran) and that
	# HOUSE_REVEAL was visited.
	var phases: Array = []
	c.phase_changed.connect(func(p): phases.append(p))
	c._advance_phase()
	assert_eq(c.state.event_index, 3, "event_index incremented")
	assert_true(MatchPhase.Phase.HOUSE_REVEAL in phases,
		"HOUSE_REVEAL should be visited after HOUSE_TWIST increments event")

func test_house_twist_on_final_event_transitions_to_match_end():
	var c = _new_controller()
	c.state.phase = MatchPhase.Phase.HOUSE_TWIST
	c.state.event_index = 4  # last event in Quick Clash
	c._advance_phase()
	assert_eq(c.state.event_index, 4, "event_index does not increment past last")
	assert_eq(c.state.phase, MatchPhase.Phase.MATCH_END)

func test_advance_phase_emits_phase_changed():
	var c = _new_controller()
	# After start_match cascade, phase is MAIN_EVENT. Reset to HOUSE_REVEAL
	# so _advance_phase emits ANTE as expected.
	c.state.phase = MatchPhase.Phase.HOUSE_REVEAL
	var phases: Array = []
	c.phase_changed.connect(func(p): phases.append(p))
	c._advance_phase()
	assert_true(MatchPhase.Phase.ANTE in phases)
