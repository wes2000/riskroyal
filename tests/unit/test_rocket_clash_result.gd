extends GutTest

const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const EventResult = preload("res://scripts/events/event_result.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(peer_id: int, name: String) -> RefCounted:
	var p = MatchPlayer.new()
	p.peer_id = peer_id
	p.name = name
	p.is_active_this_event = true
	return p

func _make_context(player_count: int, wagers: Dictionary) -> RefCounted:
	var ctx = EventContext.new()
	for i in player_count:
		ctx.players.append(_make_player(i + 1, "P%d" % (i + 1)))
	ctx.event_index = 0
	ctx.wagers = wagers
	return ctx

func test_survivor_chip_delta_is_wager_times_cash_out():
	var ctx = _make_context(2, {1: 100, 2: 100})
	var cash_outs = {1: 2.5, 2: 1.5}
	var busted = []
	var result = RocketClashEvent.compute_event_result(ctx, 3.0, cash_outs, busted)
	assert_eq(result.chip_delta_for(1), 250, "P1 cashed at 2.5x with wager 100 -> +250")
	assert_eq(result.chip_delta_for(2), 150, "P2 cashed at 1.5x with wager 100 -> +150")

func test_bust_chip_delta_is_negative_wager():
	var ctx = _make_context(2, {1: 100, 2: 200})
	var cash_outs = {}
	var busted = [1, 2]
	var result = RocketClashEvent.compute_event_result(ctx, 3.0, cash_outs, busted)
	assert_eq(result.chip_delta_for(1), -100, "bust loses wager")
	assert_eq(result.chip_delta_for(2), -200, "bust loses wager")
	assert_true(result.bust_for(1))
	assert_true(result.bust_for(2))

func test_crown_to_highest_cash_out_survivor():
	var ctx = _make_context(3, {1: 100, 2: 100, 3: 100})
	var cash_outs = {1: 1.2, 2: 2.8, 3: 1.5}
	var busted = []
	var result = RocketClashEvent.compute_event_result(ctx, 3.0, cash_outs, busted)
	assert_eq(result.crown_delta_for(2), 1, "P2 has highest cash-out -> 1 Crown")
	assert_eq(result.crown_delta_for(1), 0)
	assert_eq(result.crown_delta_for(3), 0)

func test_no_crown_when_all_bust():
	var ctx = _make_context(2, {1: 100, 2: 100})
	var cash_outs = {}
	var busted = [1, 2]
	var result = RocketClashEvent.compute_event_result(ctx, 1.5, cash_outs, busted)
	assert_eq(result.crown_delta_for(1), 0)
	assert_eq(result.crown_delta_for(2), 0)

func test_painful_reveal_payload_shape():
	var ctx = _make_context(3, {1: 100, 2: 100, 3: 100})
	var cash_outs = {2: 2.20, 3: 1.45}
	var busted = [1]
	var result = RocketClashEvent.compute_event_result(ctx, 3.42, cash_outs, busted)
	var pr = result.painful_reveal
	assert_almost_eq(pr["crash_at"], 3.42, 0.001)
	assert_eq(pr["winner_peer_id"], 2)
	assert_eq(pr["winner_name"], "P2")
	assert_eq(pr["cash_outs_summary"].size(), 3)
	var entries = pr["cash_outs_summary"]
	entries.sort_custom(func(a, b): return a["peer_id"] < b["peer_id"])
	assert_eq(entries[0]["peer_id"], 1)
	assert_eq(entries[0]["busted"], true)
	assert_eq(entries[0]["chip_delta"], -100)
	assert_eq(entries[1]["peer_id"], 2)
	assert_almost_eq(entries[1]["cash_out_at"], 2.20, 0.001)
	assert_eq(entries[1]["chip_delta"], 220)
	assert_eq(entries[1]["busted"], false)
