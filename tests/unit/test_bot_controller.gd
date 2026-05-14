# BotController wiring tests. Uses a FakeController Node that emits the
# same signals BotController subscribes to and records every host_submit_*
# call into an Array. Event-node interactions go through a FakeEventNode
# that records cash_out/pull_out/draw/lock calls.
#
# Some tests are slow (700-1500ms) because BotController uses real Timers
# for human-feeling delays. Acceptable for a unit test of timing-driven
# wiring; tighter timing seams can come later if the suite gets too slow.
extends GutTest

const BotController = preload("res://scripts/match/bot_controller.gd")


class FakePlayer extends RefCounted:
	var peer_id: int = 0
	var chips: int = 500
	var hand: Array = []
	var is_active_this_event: bool = true
	var busted_this_event: bool = false


class FakeState extends RefCounted:
	var event_index: int = 0
	var event_modifiers: Dictionary = {}
	var players: Array = []
	func find_player(pid: int):
		for p in players:
			if p.peer_id == pid:
				return p
		return null


class FakeEventNode extends Node:
	var calls: Array = []
	var current_mult: float = 2.5
	var scores: Dictionary = {}  # peer_id -> int (Card Cannon)
	var _scores: Dictionary = {}  # alias readable by BotController via `in` check
	func host_submit_cash_out(pid: int, mult: float) -> void:
		calls.append(["cash_out", pid, mult])
	func host_submit_pull_out(pid: int) -> void:
		calls.append(["pull_out", pid])
	func host_submit_draw(pid: int) -> void:
		calls.append(["draw", pid])
	func host_submit_lock(pid: int) -> void:
		calls.append(["lock", pid])
	func _current_multiplier_host() -> float:
		return current_mult


class FakeController extends Node:
	signal bet_loadout_started(active_peer_ids: Array, max_per_player: int)
	signal shop_opened(offered_card_ids: Array)
	signal event_picker_started(picker_peer_id: int, options: Array)
	signal event_starting(event_id: String, event_index: int)
	signal match_ended(rankings: Array)

	var state = FakeState.new()
	var calls: Array = []
	var current_event_node = null

	func host_submit_wager(pid: int, amount: int) -> void:
		calls.append(["wager", pid, amount])
	func host_submit_loadout(pid: int, loadout: Array) -> void:
		calls.append(["loadout", pid, loadout])
	func host_submit_shop_buy(pid: int, card_id: String) -> void:
		calls.append(["shop_buy", pid, card_id])
	func host_submit_shop_done(pid: int) -> void:
		calls.append(["shop_done", pid])
	func host_submit_event_pick(pid: int, path: String) -> void:
		calls.append(["event_pick", pid, path])
	func get_current_event_node():
		return current_event_node


# ----- Setup helpers -----

const BOT_PEER_ID: int = 1000

func _build_bot(ctrl: Node, seed_int: int = 12345) -> BotController:
	var bc = BotController.new()
	bc.controller = ctrl
	bc.bot_peer_id = BOT_PEER_ID
	bc.match_seed = seed_int
	return bc

func _add_player(ctrl: FakeController, pid: int, chips: int = 500, hand: Array = [], active: bool = true, busted: bool = false) -> FakePlayer:
	var p = FakePlayer.new()
	p.peer_id = pid; p.chips = chips; p.hand = hand
	p.is_active_this_event = active; p.busted_this_event = busted
	ctrl.state.players.append(p)
	return p

func _wait_ms(ms: int) -> void:
	await get_tree().create_timer(ms / 1000.0).timeout

func _count_calls(ctrl: FakeController, label: String) -> int:
	var n = 0
	for c in ctrl.calls:
		if String(c[0]) == label:
			n += 1
	return n


# ----- Tests -----

func test_bot_subscribes_on_ready():
	# Smoke: connecting all 5 signals should not push warnings, and after
	# _ready() all 5 signals should report at least one connection.
	var ctrl = FakeController.new()
	add_child_autofree(ctrl)
	_add_player(ctrl, BOT_PEER_ID)
	var bc = _build_bot(ctrl)
	add_child_autofree(bc)
	assert_gt(ctrl.bet_loadout_started.get_connections().size(), 0,
		"bet_loadout_started should have a BotController listener")
	assert_gt(ctrl.shop_opened.get_connections().size(), 0,
		"shop_opened should have a BotController listener")
	assert_gt(ctrl.event_picker_started.get_connections().size(), 0,
		"event_picker_started should have a BotController listener")
	assert_gt(ctrl.event_starting.get_connections().size(), 0,
		"event_starting should have a BotController listener")
	assert_gt(ctrl.match_ended.get_connections().size(), 0,
		"match_ended should have a BotController listener")


func test_bet_loadout_skipped_when_bot_not_active():
	# Bot is not in the active_peer_ids list -> no submission ever.
	var ctrl = FakeController.new()
	add_child_autofree(ctrl)
	_add_player(ctrl, BOT_PEER_ID, 500, ["a", "b"])
	var bc = _build_bot(ctrl)
	add_child_autofree(bc)
	ctrl.bet_loadout_started.emit([2, 3], 2)  # bot_peer_id (1000) absent
	await _wait_ms(700)  # well past the 100-500ms delay window
	assert_eq(_count_calls(ctrl, "wager"), 0)
	assert_eq(_count_calls(ctrl, "loadout"), 0)


func test_bet_loadout_submits_when_bot_active():
	var ctrl = FakeController.new()
	add_child_autofree(ctrl)
	_add_player(ctrl, BOT_PEER_ID, 500, ["a", "b", "c"])
	var bc = _build_bot(ctrl)
	add_child_autofree(bc)
	ctrl.bet_loadout_started.emit([BOT_PEER_ID], 2)
	await _wait_ms(700)
	assert_eq(_count_calls(ctrl, "wager"), 1, "exactly one wager submitted")
	assert_eq(_count_calls(ctrl, "loadout"), 1, "exactly one loadout submitted")
	# Spot-check shapes.
	for c in ctrl.calls:
		if c[0] == "wager":
			assert_eq(int(c[1]), BOT_PEER_ID)
			assert_gte(int(c[2]), 0); assert_lte(int(c[2]), 500)
		elif c[0] == "loadout":
			assert_eq(int(c[1]), BOT_PEER_ID)
			assert_lte((c[2] as Array).size(), 2)


func test_bet_loadout_no_double_submit_for_same_event():
	# Two emissions of bet_loadout_started in the same event index must
	# produce exactly one wager + one loadout (per-event submission guard).
	var ctrl = FakeController.new()
	add_child_autofree(ctrl)
	_add_player(ctrl, BOT_PEER_ID, 500, ["a", "b"])
	var bc = _build_bot(ctrl)
	add_child_autofree(bc)
	ctrl.bet_loadout_started.emit([BOT_PEER_ID], 2)
	ctrl.bet_loadout_started.emit([BOT_PEER_ID], 2)
	await _wait_ms(700)
	assert_eq(_count_calls(ctrl, "wager"), 1, "guard should suppress 2nd wager")
	assert_eq(_count_calls(ctrl, "loadout"), 1, "guard should suppress 2nd loadout")


func test_shop_opened_always_emits_shop_done():
	# Even with an unaffordable offer, BotController must always send
	# host_submit_shop_done so the host's shop phase can advance.
	var ctrl = FakeController.new()
	add_child_autofree(ctrl)
	_add_player(ctrl, BOT_PEER_ID, 500, [])
	var bc = _build_bot(ctrl)
	add_child_autofree(bc)
	# Real card id with a known cost (insurance = 50). Cost (50) <= chips/2
	# (250) so it's an affordable buy under the half-stack heuristic.
	ctrl.shop_opened.emit(["insurance"])
	await _wait_ms(500)
	assert_eq(_count_calls(ctrl, "shop_done"), 1, "shop_done must always fire")
	# The decision rule lets insurance through (cost 50 <= 250 budget) so
	# we should also see a shop_buy.
	assert_eq(_count_calls(ctrl, "shop_buy"), 1, "shop_buy fires for affordable card")
	for c in ctrl.calls:
		if c[0] == "shop_buy":
			assert_eq(c[2], "insurance")


func test_shop_opened_skips_buy_when_too_expensive():
	# Costly card vs small stack: skip the buy, still send shop_done.
	var ctrl = FakeController.new()
	add_child_autofree(ctrl)
	# 60 chips, but most cards cost >= 50 -> budget is 30, so nothing affordable.
	_add_player(ctrl, BOT_PEER_ID, 60, [])
	var bc = _build_bot(ctrl)
	add_child_autofree(bc)
	ctrl.shop_opened.emit(["insurance"])  # costs 50, budget 30
	await _wait_ms(500)
	assert_eq(_count_calls(ctrl, "shop_buy"), 0, "no buy when too expensive")
	assert_eq(_count_calls(ctrl, "shop_done"), 1, "shop_done still fires")


func test_event_picker_acts_only_when_bot_is_picker():
	var ctrl = FakeController.new()
	add_child_autofree(ctrl)
	_add_player(ctrl, BOT_PEER_ID)
	var bc = _build_bot(ctrl)
	add_child_autofree(bc)
	ctrl.event_picker_started.emit(42, ["a", "b", "c"])  # picker != bot
	await _wait_ms(800)
	assert_eq(_count_calls(ctrl, "event_pick"), 0)


func test_event_picker_submits_when_bot_is_picker():
	var ctrl = FakeController.new()
	add_child_autofree(ctrl)
	_add_player(ctrl, BOT_PEER_ID)
	var bc = _build_bot(ctrl)
	add_child_autofree(bc)
	ctrl.event_picker_started.emit(BOT_PEER_ID, ["alpha", "beta"])
	await _wait_ms(800)
	assert_eq(_count_calls(ctrl, "event_pick"), 1, "exactly one pick submitted")
	for c in ctrl.calls:
		if c[0] == "event_pick":
			assert_true(String(c[2]) in ["alpha", "beta"], "pick within options")


func test_match_ended_queue_frees_bot():
	var ctrl = FakeController.new()
	add_child_autofree(ctrl)
	_add_player(ctrl, BOT_PEER_ID)
	var bc = BotController.new()
	bc.controller = ctrl
	bc.bot_peer_id = BOT_PEER_ID
	bc.match_seed = 1
	add_child(bc)  # NOT autofree — we want to observe the queue_free
	ctrl.match_ended.emit([])
	# queue_free flips is_queued_for_deletion at end of frame.
	await get_tree().process_frame
	assert_true(bc.is_queued_for_deletion(),
		"BotController should queue_free on match_ended")


func test_event_starting_skips_when_bot_busted():
	# A busted bot must not schedule any event-node submissions.
	var ctrl = FakeController.new()
	add_child_autofree(ctrl)
	_add_player(ctrl, BOT_PEER_ID, 100, [], true, true)  # busted
	var bc = _build_bot(ctrl)
	add_child_autofree(bc)
	var ev_node = FakeEventNode.new()
	add_child_autofree(ev_node)
	ctrl.current_event_node = ev_node
	ctrl.event_starting.emit("rocket_clash", 0)
	# Wait short — bot must not even arm the cash_out timer because the
	# active-this-event check happens immediately on event_starting.
	await _wait_ms(200)
	assert_eq(ev_node.calls.size(), 0, "busted bot should not submit anything")


func test_event_starting_skips_when_bot_inactive():
	# Inactive (not in event) bot should not act.
	var ctrl = FakeController.new()
	add_child_autofree(ctrl)
	_add_player(ctrl, BOT_PEER_ID, 100, [], false, false)  # is_active_this_event=false
	var bc = _build_bot(ctrl)
	add_child_autofree(bc)
	var ev_node = FakeEventNode.new()
	add_child_autofree(ev_node)
	ctrl.current_event_node = ev_node
	ctrl.event_starting.emit("bomb_pot", 0)
	await _wait_ms(200)
	assert_eq(ev_node.calls.size(), 0, "inactive bot should not submit anything")


func test_event_starting_unknown_event_id_no_op():
	# Unknown event ids must not crash and must not submit anything.
	var ctrl = FakeController.new()
	add_child_autofree(ctrl)
	_add_player(ctrl, BOT_PEER_ID)
	var bc = _build_bot(ctrl)
	add_child_autofree(bc)
	var ev_node = FakeEventNode.new()
	add_child_autofree(ev_node)
	ctrl.current_event_node = ev_node
	ctrl.event_starting.emit("some_unknown_event", 0)
	await _wait_ms(200)
	assert_eq(ev_node.calls.size(), 0)
	assert_eq(ctrl.calls.size(), 0)


func test_card_cannon_threshold_chosen_within_range():
	# White-box: starting Card Cannon should set _cc_threshold via BotDecisions.
	var ctrl = FakeController.new()
	add_child_autofree(ctrl)
	_add_player(ctrl, BOT_PEER_ID)
	var bc = _build_bot(ctrl)
	add_child_autofree(bc)
	var ev_node = FakeEventNode.new()
	add_child_autofree(ev_node)
	ctrl.current_event_node = ev_node
	ctrl.event_starting.emit("card_cannon", 0)
	# Threshold is sampled synchronously inside _start_card_cannon_loop.
	assert_gte(bc._cc_threshold, 14)
	assert_lte(bc._cc_threshold, 19)
	# Cleanup: stop the running poll timer so the test doesn't leak ticks.
	if bc._cc_poll_timer != null:
		bc._cc_poll_timer.stop()


func test_card_cannon_locks_when_score_meets_threshold():
	# Seed the bot's score above the highest possible threshold (19) so the
	# very first tick must produce a lock, not a draw.
	var ctrl = FakeController.new()
	add_child_autofree(ctrl)
	_add_player(ctrl, BOT_PEER_ID)
	var bc = _build_bot(ctrl)
	add_child_autofree(bc)
	var ev_node = FakeEventNode.new()
	ev_node._scores = {BOT_PEER_ID: 20}  # already at 20 -> >= any threshold
	add_child_autofree(ev_node)
	ctrl.current_event_node = ev_node
	ctrl.event_starting.emit("card_cannon", 0)
	# Force first tick early: wait for the 0.7s poll.
	await _wait_ms(900)
	var lock_calls = 0
	for c in ev_node.calls:
		if c[0] == "lock":
			lock_calls += 1
	assert_eq(lock_calls, 1, "expected exactly one lock once score >= threshold")
	# Should NOT issue a draw before the lock since score is already at 20.
	for c in ev_node.calls:
		assert_ne(String(c[0]), "draw", "should not draw when already at threshold")


func test_card_cannon_draws_when_below_threshold():
	# Score of 0 < any threshold (>= 14): first tick should be a draw.
	var ctrl = FakeController.new()
	add_child_autofree(ctrl)
	_add_player(ctrl, BOT_PEER_ID)
	var bc = _build_bot(ctrl)
	add_child_autofree(bc)
	var ev_node = FakeEventNode.new()
	ev_node._scores = {BOT_PEER_ID: 0}
	add_child_autofree(ev_node)
	ctrl.current_event_node = ev_node
	ctrl.event_starting.emit("card_cannon", 0)
	await _wait_ms(900)
	var draw_calls = 0
	for c in ev_node.calls:
		if c[0] == "draw":
			draw_calls += 1
	assert_gte(draw_calls, 1, "expected at least one draw when score is below threshold")
	if bc._cc_poll_timer != null:
		bc._cc_poll_timer.stop()
