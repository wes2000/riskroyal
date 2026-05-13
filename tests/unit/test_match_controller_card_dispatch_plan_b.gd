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
	c.state.event_index = 2
	# Tests below set per-test loadouts; fixture provides hands only.
	c.state.players[0].hand = ["heat_spike", "wager_tax", "place_bounty", "copycat_bet", "cash_out_jammer"]
	c.state.players[1].hand = ["place_bounty", "copycat_bet", "emergency_eject"]
	return {"controller": c, "fake": fake}

func test_heat_spike_queues_pending_effect():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.players[0].loadout = ["heat_spike"]
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c._rpc_card_play_requested(1, "heat_spike", 2, null)
	assert_eq(c.state.pending_card_effects.size(), 1)
	var e = c.state.pending_card_effects[0]
	assert_eq(e.get("type", ""), "heat_delta")
	assert_eq(e.get("target", 0), 2)
	assert_eq(e.get("delta", 0), 2)

func test_wager_tax_queues_pending_effect_with_caller():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.players[0].loadout = ["wager_tax"]
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c._rpc_card_play_requested(1, "wager_tax", 2, null)
	assert_eq(c.state.pending_card_effects.size(), 1)
	var e = c.state.pending_card_effects[0]
	assert_eq(e.get("type", ""), "wager_tax")
	assert_eq(e.get("source", 0), 1)
	assert_eq(e.get("target", 0), 2)

func test_place_bounty_appends_to_state_bounties():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.players[1].loadout = ["place_bounty"]
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c.state.players[1].heat = 4
	c.state.bounties = []
	c._rpc_card_play_requested(2, "place_bounty", 1, null)
	assert_eq(c.state.bounties.size(), 1)
	var b = c.state.bounties[0]
	assert_eq(b.origin, "placed")
	assert_eq(b.target, 1)
	assert_eq(b.placed_by, 2)
	assert_eq(b.reward_chips, 150)

func test_copycat_bet_writes_pending_wagers_and_broadcasts():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.players[0].loadout = ["copycat_bet"]
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c.state.pending_wagers[2] = 200
	d.fake.rpc_calls.clear()
	c._rpc_card_play_requested(1, "copycat_bet", 2, null)
	assert_eq(c.state.pending_wagers.get(1, 0), 200, "copycat copies target wager")
	var wager_acks = 0
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_wager_acknowledged":
			wager_acks += 1
	assert_eq(wager_acks, 1, "wager broadcast exactly once for the caller")

func test_cash_out_delay_queues_pending_card_effect():
	# Cash-Out Jammer can only be played during MAIN_EVENT (cash_out timing).
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.players[0].loadout = ["cash_out_jammer"]
	c.state.phase = MatchPhase.Phase.MAIN_EVENT
	c._rpc_card_play_requested(1, "cash_out_jammer", 2, null)
	var found = false
	for e in c.state.pending_card_effects:
		if e.get("type", "") == "cash_out_delay" and e.get("target", 0) == 2:
			found = true
			assert_eq(e.get("delay_ms", 0), 750)
			break
	assert_true(found)

func test_auto_eject_loaded_sets_event_modifier():
	var d = _new_host_with_fake()
	var c = d.controller
	c.state.players[0].loadout = ["emergency_eject"]
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c._rpc_card_play_requested(1, "emergency_eject", 0, null)
	assert_true(c.state.event_modifiers.get(1, {}).get("auto_eject_loaded", false))
	assert_almost_eq(float(c.state.event_modifiers.get(1, {}).get("auto_eject_threshold", 0.0)), 3.0, 0.001)
