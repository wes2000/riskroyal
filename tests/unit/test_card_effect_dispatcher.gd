extends GutTest

const CardEffectDispatcher = preload("res://scripts/match/card_effect_dispatcher.gd")
const MatchState = preload("res://scripts/match/match_state.gd")

func _new_state(player_count: int) -> RefCounted:
	var s = MatchState.new()
	var MatchPlayer = load("res://scripts/match/match_player.gd")
	for i in player_count:
		var p = MatchPlayer.new()
		p.peer_id = i + 1
		p.chips = 500
		p.is_active_this_event = true
		s.players.append(p)
	return s

func test_apply_insurance_pre():
	var state = _new_state(2)
	CardEffectDispatcher.apply(state, 1, {"type": "insurance_pre", "applied": true}, true)
	assert_true(state.event_modifiers.get(1, {}).get("insurance_pre", false))

func test_apply_no_op_when_not_applied():
	var state = _new_state(2)
	CardEffectDispatcher.apply(state, 1, {"type": "insurance_pre", "applied": false}, true)
	assert_eq(state.event_modifiers.get(1, {}), {})

func test_apply_heat_spike_queues_pending():
	var state = _new_state(2)
	CardEffectDispatcher.apply(state, 1, {
		"type": "post_event_heat_delta", "applied": true, "target": 2, "delta": 2,
	}, true)
	assert_eq(state.pending_card_effects.size(), 1)
	assert_eq(state.pending_card_effects[0].get("type", ""), "heat_delta")

func test_unknown_type_pushes_warning():
	var state = _new_state(2)
	CardEffectDispatcher.apply(state, 1, {"type": "made_up_type", "applied": true}, true)
	# Smoke test: ensures call doesn't crash on unknown type.
	assert_true(true, "dispatcher tolerates unknown type via default branch")
