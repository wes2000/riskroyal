extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const EventResult = preload("res://scripts/events/event_result.gd")
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

func _new_host_with_fake() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(2))
	return {"controller": c, "fake": fake}

func test_wager_tax_redirects_20_pct_of_target_chip_gain():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.pending_card_effects = [{"type": "wager_tax", "source": 1, "target": 2}]
	var r = EventResult.new()
	r.per_player[1] = {"chip_delta": 0, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 1.5}
	r.per_player[2] = {"chip_delta": 200, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 2.0}
	c._apply_card_effects_to_result(r)
	assert_eq(r.per_player[1].chip_delta, 40, "caller gets 20% of 200")
	assert_eq(r.per_player[2].chip_delta, 160, "target keeps 80% of 200")
	assert_eq(c.state.pending_card_effects, [], "cleared after apply")

func test_wager_tax_no_op_when_target_busts():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.pending_card_effects = [{"type": "wager_tax", "source": 1, "target": 2}]
	var r = EventResult.new()
	r.per_player[1] = {"chip_delta": 0, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 1.5}
	r.per_player[2] = {"chip_delta": -100, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0}
	c._apply_card_effects_to_result(r)
	assert_eq(r.per_player[1].chip_delta, 0, "no tax when target busts")
	assert_eq(r.per_player[2].chip_delta, -100)

func test_heat_spike_adds_to_target_heat_delta():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.pending_card_effects = [{"type": "heat_delta", "target": 2, "delta": 2}]
	var r = EventResult.new()
	r.per_player[2] = {"chip_delta": 100, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 1.5}
	c._apply_card_effects_to_result(r)
	assert_eq(r.per_player[2].heat_delta, 2, "+2 heat from spike")

func test_multiple_effects_apply_in_order():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.pending_card_effects = [
		{"type": "wager_tax", "source": 1, "target": 2},
		{"type": "heat_delta", "target": 2, "delta": 2},
	]
	var r = EventResult.new()
	r.per_player[1] = {"chip_delta": 0, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 1.0}
	r.per_player[2] = {"chip_delta": 100, "crown_delta": 0, "heat_delta": 1, "bust": false, "cash_out_at": 2.0}
	c._apply_card_effects_to_result(r)
	assert_eq(r.per_player[1].chip_delta, 20, "tax = 20% of 100")
	assert_eq(r.per_player[2].chip_delta, 80)
	assert_eq(r.per_player[2].heat_delta, 3, "1 base + 2 from spike")
