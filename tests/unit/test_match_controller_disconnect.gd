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
	# After start_match cascade the machine is at MAIN_EVENT; set a known
	# phase so we can verify that pause/resume gates _advance_phase correctly.
	c.state.phase = MatchPhase.Phase.HOUSE_REVEAL
	c.pause()
	c.resume()
	c._advance_phase()
	# _advance_phase advanced past HOUSE_REVEAL; the cascade (ANTE -> ... ->
	# MAIN_EVENT where mock blocks) runs synchronously, so phase ends at
	# MAIN_EVENT. The key assertion is that we moved on from HOUSE_REVEAL.
	assert_ne(c.state.phase, MatchPhase.Phase.HOUSE_REVEAL)

func test_event_timeout_synthesizes_zero_delta_result():
	var d = _new_with_mock()
	var c = d.controller
	c.state.current_event_id = "res://scripts/events/test_event/test_event.tscn"
	c.state.phase = MatchPhase.Phase.MAIN_EVENT
	c._enter_phase_behavior()
	# Don't drive emit_complete; instead fire the watchdog manually.
	c._on_event_timeout()
	# The cascade runs synchronously through RESOLUTION and all subsequent
	# no-op phases, eventually looping back to MAIN_EVENT (mock blocks there).
	# The important invariants are that _on_event_timeout stored a synthesized
	# all-zero result and that the phase machine transitioned away from
	# MAIN_EVENT at least once (even if it loops back via the scheduler).
	assert_not_null(c.state.current_result)
	# All zero deltas in the synthesized result
	assert_eq(c.state.current_result.chip_delta_for(1), 0)
	assert_eq(c.state.current_result.crown_delta_for(1), 0)
