extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
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

func _new_host() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(2))
	return {"controller": c, "fake": fake}

func test_event_selection_with_sudden_death_finalizes_condition_and_broadcasts():
	var d = _new_host()
	var c = d.controller
	c.state.house_twist = {
		"type": "sudden_death_jackpot",
		"params": {"condition": ""},
	}
	c.state.previous_event_id = ""
	c.state.rng.seed = 1
	d.fake.rpc_calls.clear()
	c._process_event_selection()
	# Condition must be filled in
	var cond = String(c.state.house_twist.params.get("condition", ""))
	assert_ne(cond, "", "condition was populated by finalize_pending_params")
	assert_true(cond in ["cash_out_over_5x", "pull_out_after_80_pct", "locked_at_perfect"],
		"condition is one of the 3 valid strings")
	# Broadcast went out
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_house_twist_params_updated":
			found = true
			assert_eq(String(call.args[0].get("condition", "")), cond,
				"broadcast carries the resolved condition")
			break
	assert_true(found, "_rpc_house_twist_params_updated broadcast")

func test_event_selection_without_sudden_death_does_not_broadcast_params_updated():
	# Plan A path: non-Sudden-Death twist (or no twist) → no broadcast.
	var d = _new_host()
	var c = d.controller
	c.state.house_twist = {"type": "double_bounty", "params": {"reward_multiplier": 2.0}}
	c.state.previous_event_id = ""
	d.fake.rpc_calls.clear()
	c._process_event_selection()
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_house_twist_params_updated":
			found = true
			break
	assert_false(found, "non-Sudden-Death must not broadcast params_updated")
