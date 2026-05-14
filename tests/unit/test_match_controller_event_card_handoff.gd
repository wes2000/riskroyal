extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
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

class StubEvent extends Node:
	var delays: Dictionary = {}
	# Phase C Change 4: signature gains source_peer_id for attribution.
	func set_cash_out_delay(peer_id: int, delay_ms: int, _source_peer_id: int = 0) -> void:
		delays[peer_id] = delay_ms

func test_pending_jammer_delays_injected_into_event():
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(2))
	# Queue a cash-out delay (as Task 8's dispatcher would)
	c.state.pending_card_effects.append({"type": "cash_out_delay", "target": 2, "delay_ms": 750})
	# Also queue a non-cash_out_delay entry — must NOT be consumed
	c.state.pending_card_effects.append({"type": "heat_delta", "target": 1, "delta": 2})
	# Create a stub event with a set_cash_out_delay method
	var stub_event = StubEvent.new()
	c._current_event_node = stub_event
	c._inject_pending_event_effects()
	assert_eq(stub_event.delays.get(2, 0), 750)
	# Verify cash_out_delay was consumed but heat_delta entry kept
	var has_delay = false
	var has_heat_delta = false
	for e in c.state.pending_card_effects:
		if e.get("type", "") == "cash_out_delay":
			has_delay = true
		if e.get("type", "") == "heat_delta":
			has_heat_delta = true
	assert_false(has_delay, "cash_out_delay entry consumed")
	assert_true(has_heat_delta, "heat_delta entry kept for RESOLUTION")
	stub_event.free()
