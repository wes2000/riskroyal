extends GutTest

# Alpha remediation Phase G S2 (Pillar #7: Comebacks require risk, not
# charity). _build_debt_garnish_payload produces the resolution-step
# payload shape consumed by the resolution overlay. Only players who
# took a garnish on this event appear in the entries list.

const MatchController = preload("res://scripts/match/match_controller.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const EventResult = preload("res://scripts/events/event_result.gd")

func _new_controller() -> MatchController:
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.resolution_step_delay_ms_override = 0
	c._local_peer_id_override = 1
	return c

func _new_player(pid: int, chips: int, debt: int) -> MatchPlayer:
	var p = MatchPlayer.new()
	p.peer_id = pid
	p.seat_index = pid - 1
	p.chips = chips
	p.debt = debt
	p.is_active_this_event = true
	return p

func _seed(c: MatchController, players: Array) -> void:
	c.state = MatchState.new()
	c.state.players = players

func test_garnish_payload_single_player():
	# debt=200, chip_delta=+200. 25% = 50. Payload entry shape:
	# {peer_id: 1, garnish: 50}.
	var c = _new_controller()
	var p = _new_player(1, 0, 200)
	_seed(c, [p])
	var r = EventResult.new()
	r.per_player[1] = {"chip_delta": 200, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 2.0}
	c._apply_debt_garnish_to_result(r)
	var payload = c._build_debt_garnish_payload(r)
	var entries: Array = payload.get("garnishes", [])
	assert_eq(entries.size(), 1, "exactly one garnish entry for one debt-holder")
	assert_eq(int(entries[0].get("peer_id", 0)), 1)
	assert_eq(int(entries[0].get("garnish", 0)), 50, "garnish = 25% of 200")

func test_garnish_payload_only_garnished_players_appear():
	# Two players: P1 has debt and positive winnings (garnished), P2 has
	# no debt and just won (no garnish). Only P1 should appear.
	var c = _new_controller()
	var p1 = _new_player(1, 0, 200)
	var p2 = _new_player(2, 0, 0)
	_seed(c, [p1, p2])
	var r = EventResult.new()
	r.per_player[1] = {"chip_delta": 400, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 2.0}
	r.per_player[2] = {"chip_delta": 300, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 1.8}
	c._apply_debt_garnish_to_result(r)
	var payload = c._build_debt_garnish_payload(r)
	var entries: Array = payload.get("garnishes", [])
	assert_eq(entries.size(), 1, "only the debt-holder appears in garnishes")
	assert_eq(int(entries[0].get("peer_id", 0)), 1)
	assert_eq(int(entries[0].get("garnish", 0)), 100, "25% of 400")

func test_garnish_payload_no_debt_yields_empty():
	# No one has debt → no garnish → empty entries list.
	var c = _new_controller()
	var p = _new_player(1, 0, 0)
	_seed(c, [p])
	var r = EventResult.new()
	r.per_player[1] = {"chip_delta": 400, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 2.0}
	c._apply_debt_garnish_to_result(r)
	var payload = c._build_debt_garnish_payload(r)
	var entries: Array = payload.get("garnishes", [])
	assert_eq(entries.size(), 0, "no garnishes when no debt")

func test_debt_garnish_step_emitted_in_resolution_pipeline():
	# Integration: when a player has debt + positive winnings, the
	# RESOLUTION pipeline emits a `debt_garnish` step between
	# `chip_changes` and `painful_reveal`.
	var c = _new_controller()
	var MatchPhase = preload("res://scripts/match/match_phase.gd")
	var p = _new_player(1, 100, 200)
	var p2 = _new_player(2, 100, 0)
	_seed(c, [p, p2])
	var r = EventResult.new()
	r.per_player[1] = {"chip_delta": 200, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 2.0}
	r.per_player[2] = {"chip_delta": 100, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 1.5}
	c.state.current_result = r
	c.state.phase = MatchPhase.Phase.RESOLUTION
	var steps: Array = []
	c.resolution_step.connect(func(name, _payload): steps.append(name))
	c._process_resolution_phase()
	assert_true(steps.has("debt_garnish"), "debt_garnish step emitted when garnish occurred")
	var debt_idx = steps.find("debt_garnish")
	var chip_idx = steps.find("chip_changes")
	var painful_idx = steps.find("painful_reveal")
	assert_true(chip_idx < debt_idx, "debt_garnish fires after chip_changes")
	assert_true(debt_idx < painful_idx, "debt_garnish fires before painful_reveal")

func test_debt_garnish_step_suppressed_when_no_garnish():
	# Regression guard for existing test snapshots that pin the step
	# sequence (test_match_controller_resolution / _pacing). When no one
	# is in debt, the debt_garnish step must NOT appear.
	var c = _new_controller()
	var MatchPhase = preload("res://scripts/match/match_phase.gd")
	var p = _new_player(1, 100, 0)
	_seed(c, [p])
	var r = EventResult.new()
	r.per_player[1] = {"chip_delta": 200, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 2.0}
	c.state.current_result = r
	c.state.phase = MatchPhase.Phase.RESOLUTION
	var steps: Array = []
	c.resolution_step.connect(func(name, _payload): steps.append(name))
	c._process_resolution_phase()
	assert_false(steps.has("debt_garnish"), "debt_garnish suppressed when nobody is garnished")
