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

func _new_host_with_fake() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(2))
	c.state.players[0].hand = ["insurance", "heat_shield", "multiplier_booster"]
	return {"controller": c, "fake": fake}

func test_loadout_set_with_valid_hand_subset():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c._rpc_loadout_set(1, ["insurance", "heat_shield"])
	assert_eq(c.state.players[0].loadout, ["insurance", "heat_shield"])

func test_loadout_set_drops_cards_not_in_hand():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c._rpc_loadout_set(1, ["insurance", "nonexistent_card"])
	assert_eq(c.state.players[0].loadout, ["insurance"], "invalid card dropped")

func test_loadout_set_truncates_at_max():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.players[0].hand = ["insurance", "heat_shield", "multiplier_booster", "late_cash"]
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c._rpc_loadout_set(1, ["insurance", "heat_shield", "multiplier_booster", "late_cash"])
	assert_eq(c.state.players[0].loadout.size(), 2, "truncated to MAX_LOADOUT_SIZE = 2")

func test_loadout_set_rejected_outside_bet_loadout():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.phase = MatchPhase.Phase.MAIN_EVENT
	c._rpc_loadout_set(1, ["insurance"])
	assert_eq(c.state.players[0].loadout, [], "no change when phase != BET_LOADOUT")

func test_loadout_set_broadcasts_acknowledged():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	d.fake.rpc_calls.clear()
	c._rpc_loadout_set(1, ["insurance"])
	var ack_found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_loadout_acknowledged":
			ack_found = true
			assert_eq(call.args[0], 1)
			assert_eq(call.args[1], ["insurance"])
			break
	assert_true(ack_found)
