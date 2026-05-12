extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func test_no_op_phase_delay_override_default():
	var c = MatchController.new(true, null)
	assert_eq(c.no_op_phase_delay_ms_override, -1, "default: use MatchConfig value")

func test_schedule_advance_synchronous_when_override_zero():
	# With override=0 and not in tree, _schedule_advance calls _advance_phase
	# synchronously. Starting from HOUSE_REVEAL, the cascade also fires (ANTE
	# -> EVENT_SELECTION -> BET_LOADOUT -> MAIN_EVENT where empty
	# current_event_id stops the chain). The key invariant: the phase moved on
	# from HOUSE_REVEAL without requiring a timer.
	var c = MatchController.new(true, null)
	c.no_op_phase_delay_ms_override = 0
	# Seed rng so the EVENT_SELECTION step doesn't crash on null rng.
	c.state.rng = RandomNumberGenerator.new()
	c.state.phase = MatchPhase.Phase.HOUSE_REVEAL
	await c._schedule_advance()
	assert_ne(c.state.phase, MatchPhase.Phase.HOUSE_REVEAL, "should advance synchronously")

func _build_match_start(player_count: int) -> RefCounted:
	var ms = MatchStart.new()
	for i in player_count:
		var s = PlayerSlot.new()
		s.peer_id = i + 1; s.seat_index = i; s.name = "P%d" % (i + 1)
		ms.seats.append(s)
	ms.host_peer_id = 1; ms.rng_seed = 1
	return ms

func _new_controller_synchronous() -> MatchController:
	var c = MatchController.new(true, null)
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(2))
	return c

func test_house_reveal_auto_advances_to_ante():
	var c = _new_controller_synchronous()
	await get_tree().process_frame
	assert_ne(c.state.phase, MatchPhase.Phase.HOUSE_REVEAL)

func test_bet_loadout_auto_advances_to_main_event():
	var c = _new_controller_synchronous()
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	await c._enter_phase_behavior()
	assert_ne(c.state.phase, MatchPhase.Phase.BET_LOADOUT)

func test_shop_auto_advances_to_house_twist():
	var c = _new_controller_synchronous()
	c.state.phase = MatchPhase.Phase.SHOP
	await c._enter_phase_behavior()
	assert_ne(c.state.phase, MatchPhase.Phase.SHOP)

func test_bounty_heat_advances_after_heat_application():
	var c = _new_controller_synchronous()
	var EventResult = preload("res://scripts/events/event_result.gd")
	c.state.current_result = EventResult.new()
	c.state.phase = MatchPhase.Phase.BOUNTY_HEAT_UPDATE
	await c._enter_phase_behavior()
	assert_ne(c.state.phase, MatchPhase.Phase.BOUNTY_HEAT_UPDATE)

func test_house_twist_advances_to_next_event_or_match_end():
	var c = _new_controller_synchronous()
	c.state.phase = MatchPhase.Phase.HOUSE_TWIST
	c.state.event_index = 2
	await c._enter_phase_behavior()
	assert_ne(c.state.phase, MatchPhase.Phase.HOUSE_TWIST)
