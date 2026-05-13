extends GutTest

const CopycatBet = preload("res://scripts/cards/effects/copycat_bet.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _ctx_with_player_chips(chip_map: Dictionary) -> RefCounted:
	var ctx = EventContext.new()
	for pid in chip_map.keys():
		var p = MatchPlayer.new()
		p.peer_id = pid; p.chips = chip_map[pid]; p.is_active_this_event = true
		ctx.players.append(p)
	return ctx

func test_copycat_meta():
	var m = CopycatBet.CARD_META
	assert_eq(m.name, "Copycat Bet")
	assert_eq(m.rarity, "rare")
	assert_eq(m.category, "greed")
	assert_eq(m.timing, "bet_loadout")
	assert_eq(m.target_required, true)
	assert_eq(m.cost_chips, 150)

func test_apply_copies_target_wager():
	var ctx = _ctx_with_player_chips({1: 500, 2: 400})
	ctx.wagers = {2: 150}
	var result = CopycatBet.apply(ctx, 2, {"caller_peer_id": 1})
	assert_true(result.applied)
	assert_eq(result.type, "copycat_bet")
	assert_eq(result.source, 1)
	assert_eq(result.new_wager, 150)

func test_apply_caps_copy_at_caller_chips():
	var ctx = _ctx_with_player_chips({1: 100, 2: 500})
	ctx.wagers = {2: 400}
	var result = CopycatBet.apply(ctx, 2, {"caller_peer_id": 1})
	assert_true(result.applied)
	assert_eq(result.new_wager, 100, "capped at caller's chip count")

func test_apply_no_op_when_self_target():
	var ctx = _ctx_with_player_chips({1: 500})
	ctx.wagers = {1: 100}
	var result = CopycatBet.apply(ctx, 1, {"caller_peer_id": 1})
	assert_false(result.applied)
