# BotController: drives one bot in Practice mode. Subscribes to
# MatchController signals (bet_loadout_started, shop_opened,
# event_picker_started, event_starting, match_ended), feeds the active
# game state to BotDecisions (pure static helpers), and dispatches the
# resulting actions through MatchController.host_submit_* + event-node
# host_submit_* entry points. One instance per bot; freed on match_ended.
#
# All randomness routes through `_rng = BotDecisions.rng_for_bot(seed, peer_id)`
# so practice matches are reproducible from match_seed alone.
extends Node

const BotDecisions = preload("res://scripts/match/bot_decisions.gd")
const CardRegistry = preload("res://scripts/cards/card_registry.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")

# Wired by spawning code (MatchScene's practice-mode block).
var controller = null     # MatchController-like
var bot_peer_id: int = 0
var match_seed: int = 0

var _rng: RandomNumberGenerator = null
var _cc_poll_timer: Timer = null     # Card Cannon draw/lock loop
var _cc_threshold: int = 21          # locked at start of each Card Cannon event
var _cc_already_locked: bool = false

# Per-event submission guards (keyed by state.event_index) so a re-emitted
# signal in the same phase doesn't double-submit. Initialized to -1 so the
# first event (index 0) always passes the check.
var _wager_submitted_for_event: int = -1
var _shop_submitted_for_event: int = -1
var _pull_out_submitted_for_event: int = -1
var _cash_out_submitted_for_event: int = -1


func _ready() -> void:
	if controller == null:
		push_warning("BotController: no controller assigned")
		return
	_rng = BotDecisions.rng_for_bot(match_seed, bot_peer_id)
	controller.bet_loadout_started.connect(_on_bet_loadout_started)
	controller.shop_opened.connect(_on_shop_opened)
	controller.event_picker_started.connect(_on_event_picker_started)
	controller.event_starting.connect(_on_event_starting)
	controller.match_ended.connect(_on_match_ended)


# ----- Signal handlers -----

func _on_bet_loadout_started(active_peer_ids: Array, _max_per_player: int) -> void:
	if not (bot_peer_id in active_peer_ids):
		return
	var ev: int = _event_index()
	if _wager_submitted_for_event == ev:
		return
	_wager_submitted_for_event = ev
	var player = _player()
	if player == null:
		return
	# Modest delay so the wager doesn't fire instantly on phase entry.
	var t: Timer = _make_one_shot_timer_ms(_random_delay_ms(100, 500))
	t.timeout.connect(_submit_wager_and_loadout.bind(t))
	add_child(t)
	t.start()


func _submit_wager_and_loadout(t: Timer) -> void:
	var player = _player()
	if player == null or controller == null:
		if t != null and is_instance_valid(t):
			t.queue_free()
		return
	var wager: int = BotDecisions.pick_wager(player.chips, player.chips, _rng)
	controller.host_submit_wager(bot_peer_id, wager)
	var loadout: Array = BotDecisions.pick_loadout(player.hand, MatchConfig.MAX_LOADOUT_SIZE, _rng)
	controller.host_submit_loadout(bot_peer_id, loadout)
	if t != null and is_instance_valid(t):
		t.queue_free()


func _on_shop_opened(offered_card_ids: Array) -> void:
	var ev: int = _event_index()
	if _shop_submitted_for_event == ev:
		return
	_shop_submitted_for_event = ev
	var player = _player()
	if player == null:
		return
	# Build cost dict from CardRegistry (card meta exposes cost_chips).
	var costs: Dictionary = {}
	for cid in offered_card_ids:
		var meta: Dictionary = CardRegistry.get_card(String(cid))
		costs[cid] = int(meta.get("cost_chips", 0))
	var choice: String = BotDecisions.pick_shop_purchase(offered_card_ids, costs, player.chips, _rng)
	var t: Timer = _make_one_shot_timer_ms(_random_delay_ms(100, 300))
	t.timeout.connect(_submit_shop_actions.bind(choice, t))
	add_child(t)
	t.start()


func _submit_shop_actions(choice: String, t: Timer) -> void:
	if controller == null:
		if t != null and is_instance_valid(t):
			t.queue_free()
		return
	if choice != "":
		controller.host_submit_shop_buy(bot_peer_id, choice)
	controller.host_submit_shop_done(bot_peer_id)
	if t != null and is_instance_valid(t):
		t.queue_free()


func _on_event_picker_started(picker_peer_id: int, options: Array) -> void:
	if picker_peer_id != bot_peer_id:
		return
	var t: Timer = _make_one_shot_timer_ms(_random_delay_ms(300, 600))
	t.timeout.connect(_submit_event_pick.bind(options, t))
	add_child(t)
	t.start()


func _submit_event_pick(options: Array, t: Timer) -> void:
	if controller == null:
		if t != null and is_instance_valid(t):
			t.queue_free()
		return
	var path: String = BotDecisions.pick_event_path(options, _rng)
	if path != "":
		controller.host_submit_event_pick(bot_peer_id, path)
	if t != null and is_instance_valid(t):
		t.queue_free()


func _on_event_starting(event_id: String, _event_index_arg: int) -> void:
	# Reset per-event Card Cannon flags every event so we don't carry state.
	_cc_already_locked = false
	_cc_threshold = 21
	if _cc_poll_timer != null and is_instance_valid(_cc_poll_timer):
		_cc_poll_timer.stop()
		_cc_poll_timer.queue_free()
		_cc_poll_timer = null
	var player = _player()
	if player == null or not player.is_active_this_event:
		return
	# event_starting emits get_event_id() which is the bare event id
	# ("rocket_clash", "bomb_pot", "card_cannon"), not a scene path. Match
	# by equality (and accept .tscn suffix defensively).
	if event_id == "rocket_clash" or event_id.ends_with("rocket_clash_event.tscn"):
		_schedule_cash_out()
	elif event_id == "bomb_pot" or event_id.ends_with("bomb_pot_event.tscn"):
		_schedule_pull_out()
	elif event_id == "card_cannon" or event_id.ends_with("card_cannon_event.tscn"):
		_start_card_cannon_loop()


func _schedule_cash_out() -> void:
	var ev: int = _event_index()
	if _cash_out_submitted_for_event == ev:
		return
	var delay_ms: int = BotDecisions.pick_cash_out_delay_ms(_rng)
	var t: Timer = _make_one_shot_timer_ms(delay_ms)
	t.timeout.connect(_do_cash_out.bind(ev, t))
	add_child(t)
	t.start()


func _do_cash_out(ev: int, t: Timer) -> void:
	_cash_out_submitted_for_event = ev
	var cleanup = func():
		if t != null and is_instance_valid(t):
			t.queue_free()
	var ev_node = _current_event_node()
	if ev_node == null or not ev_node.has_method("host_submit_cash_out"):
		cleanup.call(); return
	var player = _player()
	if player == null or player.busted_this_event:
		cleanup.call(); return
	var mult: float = 1.0
	if ev_node.has_method("_current_multiplier_host"):
		mult = float(ev_node._current_multiplier_host())
	ev_node.host_submit_cash_out(bot_peer_id, mult)
	cleanup.call()


func _schedule_pull_out() -> void:
	var ev: int = _event_index()
	if _pull_out_submitted_for_event == ev:
		return
	var delay_ms: int = BotDecisions.pick_pull_out_delay_ms(_rng)
	var t: Timer = _make_one_shot_timer_ms(delay_ms)
	t.timeout.connect(_do_pull_out.bind(ev, t))
	add_child(t)
	t.start()


func _do_pull_out(ev: int, t: Timer) -> void:
	_pull_out_submitted_for_event = ev
	var cleanup = func():
		if t != null and is_instance_valid(t):
			t.queue_free()
	var ev_node = _current_event_node()
	if ev_node == null or not ev_node.has_method("host_submit_pull_out"):
		cleanup.call(); return
	var player = _player()
	if player == null or player.busted_this_event:
		cleanup.call(); return
	ev_node.host_submit_pull_out(bot_peer_id)
	cleanup.call()


func _start_card_cannon_loop() -> void:
	_cc_threshold = BotDecisions.pick_card_cannon_threshold(_rng)
	_cc_already_locked = false
	if _cc_poll_timer != null and is_instance_valid(_cc_poll_timer):
		_cc_poll_timer.stop()
		_cc_poll_timer.queue_free()
	_cc_poll_timer = Timer.new()
	_cc_poll_timer.wait_time = 0.7
	_cc_poll_timer.one_shot = false
	_cc_poll_timer.timeout.connect(_on_cc_tick)
	add_child(_cc_poll_timer)
	_cc_poll_timer.start()


func _on_cc_tick() -> void:
	if _cc_already_locked:
		if _cc_poll_timer != null and is_instance_valid(_cc_poll_timer):
			_cc_poll_timer.stop()
		return
	var ev_node = _current_event_node()
	if ev_node == null or not ev_node.has_method("host_submit_draw"):
		if _cc_poll_timer != null and is_instance_valid(_cc_poll_timer):
			_cc_poll_timer.stop()
		return
	var player = _player()
	if player == null or player.busted_this_event:
		if _cc_poll_timer != null and is_instance_valid(_cc_poll_timer):
			_cc_poll_timer.stop()
		return
	var score: int = _cc_current_score_for(ev_node)
	if score >= _cc_threshold:
		ev_node.host_submit_lock(bot_peer_id)
		_cc_already_locked = true
		if _cc_poll_timer != null and is_instance_valid(_cc_poll_timer):
			_cc_poll_timer.stop()
	else:
		ev_node.host_submit_draw(bot_peer_id)


func _cc_current_score_for(ev_node) -> int:
	# CardCannonEvent stores per-peer running scores in `_scores` (Dictionary
	# peer_id -> int). We read directly off the event node since the state is
	# event-local, not on state.event_modifiers.
	if ev_node == null:
		return 0
	if not ("_scores" in ev_node):
		return 0
	var scores: Dictionary = ev_node._scores
	return int(scores.get(bot_peer_id, 0))


func _on_match_ended(_rankings) -> void:
	queue_free()


# ----- Helpers -----

func _player():
	if controller == null or controller.state == null:
		return null
	return controller.state.find_player(bot_peer_id)


func _event_index() -> int:
	if controller == null or controller.state == null:
		return -1
	return controller.state.event_index


func _current_event_node():
	# Prefer the public getter if MatchController exposes one; fall back to
	# the private field name so the test FakeController can wire it directly.
	if controller == null:
		return null
	if controller.has_method("get_current_event_node"):
		return controller.get_current_event_node()
	if "_current_event_node" in controller:
		return controller._current_event_node
	return null


func _make_one_shot_timer_ms(ms: int) -> Timer:
	var t := Timer.new()
	t.wait_time = max(0.001, ms / 1000.0)
	t.one_shot = true
	return t


func _random_delay_ms(min_ms: int, max_ms: int) -> int:
	return _rng.randi_range(min_ms, max_ms)
