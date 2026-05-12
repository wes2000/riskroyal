extends GutTest

const UnderdogOdds = preload("res://scripts/cards/effects/underdog_odds.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(peer_id: int, chips: int) -> RefCounted:
	var p = MatchPlayer.new()
	p.peer_id = peer_id
	p.chips = chips
	p.is_active_this_event = true
	return p

func _ctx_with_players(chips_by_id: Dictionary) -> RefCounted:
	var ctx = EventContext.new()
	for pid in chips_by_id.keys():
		ctx.players.append(_make_player(pid, chips_by_id[pid]))
	return ctx

func test_underdog_odds_meta():
	var m = UnderdogOdds.CARD_META
	assert_eq(m.name, "Underdog Odds")
	assert_eq(m.category, "social")
	assert_eq(m.timing, "bet_loadout")

func test_underdog_odds_applies_when_caller_is_last_in_chips():
	var ctx = _ctx_with_players({1: 500, 2: 100, 3: 300})
	var result = UnderdogOdds.apply(ctx, 2, null)
	assert_true(result.applied)
	assert_eq(result.type, "underdog_multiplier")
	assert_almost_eq(float(result.multiplier), 1.5, 0.001)

func test_underdog_odds_no_op_when_caller_not_last():
	var ctx = _ctx_with_players({1: 500, 2: 100, 3: 300})
	var result = UnderdogOdds.apply(ctx, 1, null)
	assert_false(result.applied)
