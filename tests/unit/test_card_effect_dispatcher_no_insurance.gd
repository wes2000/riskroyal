extends GutTest

const CardEffectDispatcher = preload("res://scripts/match/card_effect_dispatcher.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _new_state() -> RefCounted:
	var s = MatchState.new()
	for i in 2:
		var p = MatchPlayer.new()
		p.peer_id = i + 1; p.seat_index = i
		s.players.append(p)
	return s

func test_apply_no_insurance_short_circuits_insurance_pre():
	var s = _new_state()
	s.house_twist = {"type": "no_insurance", "params": {}}
	CardEffectDispatcher.apply(s, 1, {"type": "insurance_pre", "applied": true}, true)
	# Under no_insurance twist, the dispatcher does NOT set the modifier
	assert_eq(s.event_modifiers.get(1, {}).get("insurance_pre", false), false,
		"no_insurance twist short-circuits insurance_pre")

func test_apply_no_insurance_does_not_affect_other_effects():
	var s = _new_state()
	s.house_twist = {"type": "no_insurance", "params": {}}
	# Heat Shield is unaffected by no_insurance
	CardEffectDispatcher.apply(s, 1, {"type": "heat_shield", "applied": true}, true)
	assert_true(s.event_modifiers.get(1, {}).get("heat_shield", false),
		"heat_shield effect proceeds normally under no_insurance twist")
