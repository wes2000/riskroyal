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
	c.state.players[0].hand = ["insurance", "heat_shield"]
	c.state.players[0].loadout = ["insurance", "heat_shield"]
	return {"controller": c, "fake": fake}

func test_card_play_during_bet_loadout_applies_modifier():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c._rpc_card_play_requested(1, "insurance", 0, null)
	assert_true(c.state.event_modifiers.get(1, {}).get("insurance_pre", false))
	assert_true("insurance" in c.state.players[0].played_this_event)

func test_card_play_outside_window_rejected():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.phase = MatchPhase.Phase.MAIN_EVENT
	c._rpc_card_play_requested(1, "insurance", 0, null)
	assert_false(c.state.event_modifiers.get(1, {}).get("insurance_pre", false))
	assert_false("insurance" in c.state.players[0].played_this_event)

func test_card_not_in_loadout_rejected():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c._rpc_card_play_requested(1, "multiplier_booster", 0, null)
	assert_false(c.state.event_modifiers.get(1, {}).get("wager_multiplier", false))

func test_card_already_played_silently_dropped():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c._rpc_card_play_requested(1, "insurance", 0, null)
	d.fake.rpc_calls.clear()
	c._rpc_card_play_requested(1, "insurance", 0, null)
	var ack_count = 0
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_card_effect_applied":
			ack_count += 1
	assert_eq(ack_count, 0, "second play silently dropped (no new broadcast)")

func test_card_play_broadcasts_effect_applied():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	d.fake.rpc_calls.clear()
	c._rpc_card_play_requested(1, "insurance", 0, null)
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_card_effect_applied":
			found = true
			assert_eq(call.args[0], 1)
			assert_eq(call.args[1], "insurance")
			break
	assert_true(found)

func test_card_play_multiple_cards_accumulates_modifiers():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c._rpc_card_play_requested(1, "insurance", 0, null)
	c._rpc_card_play_requested(1, "heat_shield", 0, null)
	assert_true(c.state.event_modifiers.get(1, {}).get("insurance_pre", false))
	assert_true(c.state.event_modifiers.get(1, {}).get("heat_shield", false))

func test_insurance_rejected_under_no_insurance_twist():
	# Wrapper rejection path: under no_insurance twist, the host returns
	# _rpc_card_play_rejected to the originating peer and does NOT mutate
	# state (no modifier set, no card consumed).
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c.state.house_twist = {"type": "no_insurance", "params": {}}
	d.fake.rpc_calls.clear()
	c._rpc_card_play_requested(1, "insurance", 0, null)
	# Modifier must NOT be set.
	assert_false(c.state.event_modifiers.get(1, {}).get("insurance_pre", false),
		"insurance_pre modifier must not be set when no_insurance twist is active")
	# Card must NOT be recorded as played.
	assert_false("insurance" in c.state.players[0].played_this_event,
		"insurance must not be added to played_this_event when rejected")
	# A _rpc_card_play_rejected RPC must have been sent with reason "no_insurance_twist".
	var rejected = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_card_play_rejected" and call.args.size() >= 2 and call.args[1] == "no_insurance_twist":
			rejected = true
			break
	assert_true(rejected, "_rpc_card_play_rejected must be sent with reason no_insurance_twist")
