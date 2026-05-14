extends GutTest

# Alpha feel remediation Phase E §10.3 (Debt-Lite Comeback).
# When p.debt > 0 AND chip_delta > 0 at resolution, the controller
# garnishes int(floor(chip_delta * DEBT_GARNISH_RATE)) (capped at remaining
# debt). The garnish reduces chip_delta and reduces p.debt by the same
# magnitude. result.per_player[pid]["debt_delta"] = -garnish for broadcast.

const MatchController = preload("res://scripts/match/match_controller.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")
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

func test_garnish_25_pct_of_positive_winnings():
	# debt=200, chip_delta=+400. 25% = 100. chip_delta becomes 300, debt -> 100.
	var c = _new_controller()
	var p = _new_player(2, 0, 200)
	_seed(c, [p])
	var r = EventResult.new()
	r.per_player[2] = {"chip_delta": 400, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 2.0}
	c._apply_debt_garnish_to_result(r)
	assert_eq(int(r.per_player[2]["chip_delta"]), 300, "chip_delta reduced by garnish (400 - 100)")
	assert_eq(int(r.per_player[2].get("debt_delta", 0)), -100, "debt_delta = -garnish on result")

func test_garnish_floors_fractional_amount():
	# debt=200, chip_delta=+101. 25% = 25.25 -> floor 25. chip_delta -> 76.
	var c = _new_controller()
	var p = _new_player(2, 0, 200)
	_seed(c, [p])
	var r = EventResult.new()
	r.per_player[2] = {"chip_delta": 101, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 1.5}
	c._apply_debt_garnish_to_result(r)
	assert_eq(int(r.per_player[2]["chip_delta"]), 76, "chip_delta reduced by floored garnish (25)")
	assert_eq(int(r.per_player[2].get("debt_delta", 0)), -25, "debt_delta = -25")

func test_garnish_capped_at_remaining_debt():
	# debt=20, chip_delta=+400. 25% = 100, but only 20 owed. Cap at 20.
	# chip_delta -> 380, debt -> 0.
	var c = _new_controller()
	var p = _new_player(2, 0, 20)
	_seed(c, [p])
	var r = EventResult.new()
	r.per_player[2] = {"chip_delta": 400, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 2.0}
	c._apply_debt_garnish_to_result(r)
	assert_eq(int(r.per_player[2]["chip_delta"]), 380, "chip_delta reduced by capped garnish")
	assert_eq(int(r.per_player[2].get("debt_delta", 0)), -20, "debt_delta caps at remaining debt")

func test_garnish_applies_to_player_debt_on_host_via_apply_and_emit():
	# End-to-end: after _apply_and_emit("chip_changes", ...), the host's
	# MatchPlayer.debt should reflect the garnish (decremented).
	var c = _new_controller()
	var p = _new_player(2, 500, 200)
	# Need a 2nd player so the rpc broadcast actually serializes the delta.
	var p2 = _new_player(3, 500, 0)
	_seed(c, [p, p2])
	var r = EventResult.new()
	r.per_player[2] = {"chip_delta": 400, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 2.0}
	c._apply_debt_garnish_to_result(r)
	c._apply_and_emit("chip_changes", r, "chip_delta")
	assert_eq(p.chips, 500 + 300, "host applies post-garnish chip_delta")
	assert_eq(p.debt, 100, "host applies debt_delta (200 - 100)")
	# Broadcast delta should carry debt_delta = -100.
	var broadcast_call = null
	for call in c._multiplayer_node.rpc_calls:
		if String(call.get("method", "")) == "_rpc_apply_deltas":
			broadcast_call = call
			break
	assert_true(broadcast_call != null, "broadcast _rpc_apply_deltas fired")
	var deltas: Array = broadcast_call["args"][0]
	var found = false
	for d in deltas:
		if int(d.get("peer_id", 0)) == 2:
			assert_eq(int(d.get("debt_delta", 0)), -100, "broadcast carries debt_delta = -100")
			assert_eq(int(d.get("chip_delta", 0)), 300, "broadcast chip_delta is post-garnish")
			found = true
	assert_true(found, "garnished player's delta included in broadcast")

func test_zero_debt_player_unaffected_by_garnish():
	var c = _new_controller()
	var p = _new_player(2, 0, 0)
	_seed(c, [p])
	var r = EventResult.new()
	r.per_player[2] = {"chip_delta": 400, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 2.0}
	c._apply_debt_garnish_to_result(r)
	assert_eq(int(r.per_player[2]["chip_delta"]), 400, "chip_delta unchanged with no debt")
	assert_eq(int(r.per_player[2].get("debt_delta", 0)), 0, "no debt_delta when no debt")
