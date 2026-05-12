extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MockEvent = preload("res://tests/fakes/mock_event.gd")
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

func _new_with_mock() -> Dictionary:
	var c = MatchController.new(true, null)
	var mock = MockEvent.new()
	c._event_factory = func(_path): return mock
	c.start_match(_build_match_start(2))
	return {"controller": c, "mock": mock}

func test_pause_blocks_advance_phase():
	var d = _new_with_mock()
	var c = d.controller
	c.state.phase = MatchPhase.Phase.HOUSE_REVEAL
	c.pause()
	var pre_phase = c.state.phase
	c._advance_phase()
	assert_eq(c.state.phase, pre_phase, "advance_phase should not change phase when paused")

func test_resume_unblocks_advance_phase():
	var d = _new_with_mock()
	var c = d.controller
	c.state.phase = MatchPhase.Phase.HOUSE_REVEAL
	c.pause()
	c.resume()
	c._advance_phase()
	assert_eq(c.state.phase, MatchPhase.Phase.ANTE)

func test_event_timeout_synthesizes_zero_delta_result():
	var d = _new_with_mock()
	var c = d.controller
	c.state.current_event_id = "res://scripts/events/test_event/test_event.tscn"
	c.state.phase = MatchPhase.Phase.MAIN_EVENT
	c._enter_phase_behavior()
	# Don't drive emit_complete; instead fire the watchdog manually.
	c._on_event_timeout()
	# By Task 13, the RESOLUTION pipeline (Task 11) and BOUNTY_HEAT_UPDATE
	# handler (Task 12) are both wired and chain synchronously through
	# _advance_phase. So phase will land past RESOLUTION; just assert we
	# left MAIN_EVENT and that the synthesized empty result was stored.
	assert_ne(c.state.phase, MatchPhase.Phase.MAIN_EVENT)
	assert_not_null(c.state.current_result)
	# All zero deltas
	assert_eq(c.state.current_result.chip_delta_for(1), 0)
	assert_eq(c.state.current_result.crown_delta_for(1), 0)
