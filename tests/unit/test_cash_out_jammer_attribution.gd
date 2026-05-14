extends GutTest

const CashOutJammer = preload("res://scripts/cards/effects/cash_out_jammer.gd")
const CardEffectDispatcher = preload("res://scripts/match/card_effect_dispatcher.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

# Cash-Out Jammer's apply() must include source=caller_peer_id so the
# bounty resolver can later route bust_after_sabotage / saboteur rewards.
func test_cash_out_jammer_records_caller_as_source():
	var effect = CashOutJammer.apply(null, 5, {"caller_peer_id": 2})
	assert_true(effect.applied)
	assert_eq(String(effect.get("type", "")), "cash_out_delay")
	assert_eq(int(effect.get("source", 0)), 2, "caller_peer_id recorded as source")
	assert_eq(int(effect.get("target", 0)), 5)
	assert_eq(int(effect.get("delay_ms", 0)), 750)

# Dispatcher must preserve source when queuing the pending_card_effects entry.
func test_dispatcher_preserves_source_in_pending_effect():
	var s = MatchState.new()
	for i in 3:
		var p = MatchPlayer.new()
		p.peer_id = i + 1; p.is_active_this_event = true
		s.players.append(p)
	CardEffectDispatcher.apply(s, 2, {
		"type": "cash_out_delay",
		"applied": true,
		"source": 2,
		"target": 5,
		"delay_ms": 750,
	}, true)
	assert_eq(s.pending_card_effects.size(), 1)
	var queued = s.pending_card_effects[0]
	assert_eq(int(queued.get("source", 0)), 2, "source forwarded through dispatcher")
	assert_eq(int(queued.get("target", 0)), 5)
	assert_eq(int(queued.get("delay_ms", 0)), 750)
