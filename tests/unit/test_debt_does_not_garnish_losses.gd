extends GutTest

# Alpha feel remediation Phase E §10.3 (Debt-Lite Comeback).
# Garnish only fires when chip_delta > 0. Negative (bust / loss) or zero
# chip_delta must leave both chip_delta and player debt untouched.

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

func test_negative_chip_delta_does_not_garnish():
	var c = _new_controller()
	var p = _new_player(2, 500, 200)
	_seed(c, [p])
	var r = EventResult.new()
	r.per_player[2] = {"chip_delta": -300, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0}
	c._apply_debt_garnish_to_result(r)
	assert_eq(int(r.per_player[2]["chip_delta"]), -300, "chip_delta unchanged on loss")
	assert_eq(int(r.per_player[2].get("debt_delta", 0)), 0, "no debt_delta on loss")

func test_zero_chip_delta_does_not_garnish():
	var c = _new_controller()
	var p = _new_player(2, 500, 200)
	_seed(c, [p])
	var r = EventResult.new()
	r.per_player[2] = {"chip_delta": 0, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 1.0}
	c._apply_debt_garnish_to_result(r)
	assert_eq(int(r.per_player[2]["chip_delta"]), 0, "chip_delta unchanged at 0")
	assert_eq(int(r.per_player[2].get("debt_delta", 0)), 0, "no debt_delta when chip_delta=0")

func test_debt_unchanged_after_loss_through_apply_and_emit():
	# End-to-end: a debt-holding player who loses must not have their debt
	# reduced (only positive winnings repay debt).
	var c = _new_controller()
	var p = _new_player(2, 500, 200)
	_seed(c, [p])
	var r = EventResult.new()
	r.per_player[2] = {"chip_delta": -100, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 0.5}
	c._apply_debt_garnish_to_result(r)
	c._apply_and_emit("chip_changes", r, "chip_delta")
	assert_eq(p.chips, 400, "chips reduced by full loss")
	assert_eq(p.debt, 200, "debt unchanged on loss")
