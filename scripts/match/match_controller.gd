# Owns MatchState and drives the per-event 9-phase state machine.
# Host-authoritative: only the host mutates state and broadcasts via RPC.
# See spec sections 5 and 6.5 for the full design.
extends Node

const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const Bounty = preload("res://scripts/match/bounty.gd")
const CardRegistry = preload("res://scripts/cards/card_registry.gd")

signal phase_changed(new_phase: int)
signal event_starting(event_id: String, event_index: int)
signal resolution_step(step_name: String, payload: Dictionary)
signal match_ended(rankings: Array)
signal player_resources_changed(peer_id: int)
signal request_return_to_lobby
signal wager_acknowledged(peer_id: int, amount: int)
signal loadout_acknowledged(peer_id: int, loadout: Array)
signal bet_loadout_started(active_peer_ids: Array, max_per_player: int)
signal bet_loadout_finished
signal bounty_placed(bounty_dict: Dictionary)
signal bounty_claimed(claimant_peer_id: int, bounty_dict: Dictionary, reward_chips: int)
signal bounty_unclaimed(bounty_dict: Dictionary)
signal card_effect_applied(peer_id: int, card_id: String, effect_result: Dictionary)
signal card_play_rejected(card_id: String, reason: String)
signal shop_opened(offered_card_ids: Array)
signal shop_closed
signal shop_purchase_confirmed(peer_id: int, card_id: String, cost_chips: int)
signal shop_purchase_rejected(peer_id: int, card_id: String, reason: String)

var state: MatchState
var is_host: bool = false
var _multiplayer_node = null  # for RPC routing in production; null in unit tests

# Test seam: override per-step delay to 0 for synchronous tests.
# Plan A: declared for forward-compat; the synchronous pipeline below
# ignores it. Plan B wires this into a Timer-driven pacing path.
var resolution_step_delay_ms_override: int = -1

# Test seam: override no-op phase auto-advance delay. -1 = use MatchConfig
# default. 0 = advance synchronously (no await). >0 = use this delay in ms.
var no_op_phase_delay_ms_override: int = -1

# Factory injected by tests; production code uses _default_event_factory.
# IMPORTANT: do NOT initialize at declaration — instance methods aren't
# bindable at field-init time in GDScript 2.0. Assigned in _init instead.
var _event_factory: Callable
var _current_event_node = null

# Pause/resume gate for the state machine. Wired to NetSession.state_changed(PAUSED)
# in Plan B to freeze progression when a peer disconnects.
var _paused: bool = false

# Watchdog timer for the currently-running MAIN_EVENT. Created in
# _process_main_event when the event node is instantiated; freed in
# _on_event_complete and _on_event_timeout.
var _event_timeout_timer: Timer = null

# Test seam: override watchdog timeout in seconds. -1 = use MatchConfig.
var event_timeout_sec_override: float = -1.0

# Test seam: override BET_LOADOUT phase timeout (mirror of event_timeout pattern).
# Negative = use MatchConfig.BET_LOADOUT_TIMEOUT_SEC. 0.0 = bypass timer entirely.
var bet_loadout_timeout_sec_override: float = -1.0

# Test seam: override SHOP phase timeout (mirror of bet_loadout pattern).
# Negative = use MatchConfig.SHOP_TIMEOUT_SEC. 0.0 = synchronous open, no auto-close.
var shop_timeout_sec_override: float = -1.0

func _default_event_factory(path: String):
	var ps = load(path)
	if ps == null:
		return null
	return ps.instantiate()

func _event_timeout_sec() -> float:
	if event_timeout_sec_override >= 0.0:
		return event_timeout_sec_override
	return float(MatchConfig.EVENT_TIMEOUT_SEC)

func _bet_loadout_timeout_sec() -> float:
	if bet_loadout_timeout_sec_override >= 0.0:
		return bet_loadout_timeout_sec_override
	return float(MatchConfig.BET_LOADOUT_TIMEOUT_SEC)

func _shop_timeout_sec() -> float:
	if shop_timeout_sec_override >= 0.0:
		return shop_timeout_sec_override
	return float(MatchConfig.SHOP_TIMEOUT_SEC)

func _start_event_timeout_watchdog() -> void:
	if not is_inside_tree():
		# Tests that bypass the scene tree skip the watchdog; the test
		# may call _on_event_timeout directly to verify timeout behavior.
		return
	_clear_event_timeout_watchdog()
	_event_timeout_timer = Timer.new()
	_event_timeout_timer.one_shot = true
	_event_timeout_timer.wait_time = _event_timeout_sec()
	add_child(_event_timeout_timer)
	_event_timeout_timer.timeout.connect(_on_event_timeout)
	_event_timeout_timer.start()

func _clear_event_timeout_watchdog() -> void:
	if _event_timeout_timer != null:
		if _event_timeout_timer.is_inside_tree():
			_event_timeout_timer.queue_free()
		_event_timeout_timer = null

func _init(p_is_host: bool = false, multiplayer_node = null) -> void:
	is_host = p_is_host
	_multiplayer_node = multiplayer_node
	state = MatchState.new()
	_event_factory = Callable(self, "_default_event_factory")

func pause() -> void:
	_paused = true

func resume() -> void:
	_paused = false

func start_match(match_start) -> void:
	if not is_host:
		return
	# C1 self-wire: route RPCs via this controller's own self.rpc()
	# since the @rpc receiver methods (_rpc_phase_changed, _rpc_apply_deltas,
	# etc.) live on MatchController. MatchScene passes multiplayer_node=null,
	# so without this self-wire the @rpc dispatch would target MatchScene
	# which has no such methods. Detached test controllers skip this so
	# _send_rpc continues to no-op.
	if _multiplayer_node == null and is_inside_tree():
		_multiplayer_node = self
	# Build MatchPlayer records from MatchStart seats.
	state.players = []
	var player_count = match_start.seats.size()
	var starting_chips = MatchConfig.starting_chips_for_player_count(player_count)
	for seat in match_start.seats:
		var mp = MatchPlayer.new()
		mp.peer_id = seat.peer_id
		mp.seat_index = seat.seat_index
		mp.name = seat.name
		mp.color_index = seat.color_index
		mp.chips = starting_chips
		state.players.append(mp)
	state.rng_seed = match_start.rng_seed
	state.seed_rng()
	state.event_index = 0
	# Deal starter pack of 3 random commons (excluding sabotage)
	_deal_starter_pack()
	_set_phase(MatchPhase.Phase.HOUSE_REVEAL)

func _send_rpc(method_name: String, args: Array = []) -> void:
	# Internal RPC sender. Routes through _multiplayer_node.rpc when non-null;
	# no-ops in unit tests where _multiplayer_node is null.
	if _multiplayer_node == null:
		return
	match args.size():
		0: _multiplayer_node.rpc(method_name)
		1: _multiplayer_node.rpc(method_name, args[0])
		2: _multiplayer_node.rpc(method_name, args[0], args[1])
		3: _multiplayer_node.rpc(method_name, args[0], args[1], args[2])
		_:
			push_error("MatchController._send_rpc: unsupported arity %d" % args.size())

func _send_rpc_to_peer(peer_id: int, method_name: String, args: Array = []) -> void:
	# Targeted RPC. Routes through _multiplayer_node.rpc_id when non-null;
	# no-ops in unit tests where _multiplayer_node is null. FakeMultiplayerNode
	# already records {method, peer_id, args} for rpc_id calls.
	if _multiplayer_node == null:
		return
	match args.size():
		0: _multiplayer_node.rpc_id(peer_id, method_name)
		1: _multiplayer_node.rpc_id(peer_id, method_name, args[0])
		2: _multiplayer_node.rpc_id(peer_id, method_name, args[0], args[1])
		3: _multiplayer_node.rpc_id(peer_id, method_name, args[0], args[1], args[2])
		_:
			push_error("MatchController._send_rpc_to_peer: unsupported arity %d" % args.size())

# Public: called locally by BetLoadoutOverlay's Ready handler.
func submit_loadout_change(loadout: Array) -> void:
	var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
	_send_rpc("_rpc_loadout_set", [my_peer_id, loadout])

func submit_card_play(card_id: String, target_peer_id: int = 0, params = null) -> void:
	var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
	_send_rpc("_rpc_card_play_requested", [my_peer_id, card_id, target_peer_id, params])

func submit_wager(amount: int) -> void:
	var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
	_send_rpc("_rpc_set_wager", [my_peer_id, amount])

@rpc("any_peer", "call_local", "reliable")
func _rpc_set_wager(peer_id: int, amount: int) -> void:
	if not is_host:
		return
	var player = state.find_player(peer_id)
	if player == null:
		return
	var clamped = clamp(amount, 0, player.chips)
	state.pending_wagers[peer_id] = clamped
	_send_rpc("_rpc_wager_acknowledged", [peer_id, clamped])

@rpc("authority", "call_remote", "reliable")
func _rpc_wager_acknowledged(_peer_id: int, _amount: int) -> void:
	# Re-emits a local signal for BetLoadoutOverlay to update readied state.
	wager_acknowledged.emit(_peer_id, _amount)

@rpc("any_peer", "call_local", "reliable")
func _rpc_loadout_set(peer_id: int, loadout: Array) -> void:
	if not is_host:
		return
	if state.phase != MatchPhase.Phase.BET_LOADOUT:
		return  # Silent reject; UI should disable slots outside BET_LOADOUT
	var player = state.find_player(peer_id)
	if player == null:
		return
	var clamped: Array = []
	for card_id in loadout:
		if card_id in player.hand and not (card_id in clamped):
			clamped.append(card_id)
			if clamped.size() >= MatchConfig.MAX_LOADOUT_SIZE:
				break
	player.loadout = clamped
	_send_rpc("_rpc_loadout_acknowledged", [peer_id, clamped])

@rpc("authority", "call_remote", "reliable")
func _rpc_loadout_acknowledged(peer_id: int, loadout: Array) -> void:
	var player = state.find_player(peer_id)
	if player != null:
		player.loadout = loadout.duplicate()
	loadout_acknowledged.emit(peer_id, loadout)

func _phase_change_context() -> Dictionary:
	return {
		"event_index": state.event_index,
		"current_event_id": state.current_event_id,
	}

func _set_phase(new_phase: int) -> void:
	state.phase = new_phase
	phase_changed.emit(new_phase)
	if is_host:
		_send_rpc("_rpc_phase_changed", [new_phase, _phase_change_context()])
	_enter_phase_behavior()

# Called on host when entering a phase to execute MVP behavior.
# Async: no-op phases call _schedule_advance to auto-advance the machine.
# _set_phase calls this without await; the coroutine runs detached and the
# phase change still happens synchronously. Plan A tests that call this
# without await continue to work (GDScript runs unwaited coroutines detached).
func _enter_phase_behavior() -> void:
	if not is_host:
		return
	match state.phase:
		MatchPhase.Phase.HOUSE_REVEAL:
			_auto_place_bounties()
			for p in state.players:
				p.played_this_event = []
			state.event_modifiers = {}
			state.pending_card_effects = []
			await _schedule_advance()
		MatchPhase.Phase.ANTE:
			_process_ante_phase()
			await _schedule_advance()
		MatchPhase.Phase.EVENT_SELECTION:
			_process_event_selection()
			await _schedule_advance()
		MatchPhase.Phase.BET_LOADOUT:
			await _process_bet_loadout()
			await _schedule_advance()
		MatchPhase.Phase.MAIN_EVENT:
			_process_main_event()
			# MAIN_EVENT does NOT _schedule_advance; the event drives the
			# transition via event_complete or watchdog timeout.
		MatchPhase.Phase.RESOLUTION:
			await _process_resolution_phase()
			# RESOLUTION pipeline calls _advance_phase at its end (existing).
		MatchPhase.Phase.BOUNTY_HEAT_UPDATE:
			_process_bounty_heat_update()
			await _schedule_advance()
		MatchPhase.Phase.SHOP:
			await _process_shop()
			await _schedule_advance()
		MatchPhase.Phase.HOUSE_TWIST:
			await _schedule_advance()
		MatchPhase.Phase.MATCH_END:
			_process_match_end()
		_:
			pass

func _process_ante_phase() -> void:
	var ante = MatchConfig.ANTE_BY_EVENT_INDEX[state.event_index]
	var deltas: Array = []
	for p in state.players:
		if p.chips >= ante:
			p.chips -= ante
			p.is_active_this_event = true
			player_resources_changed.emit(p.peer_id)
			deltas.append({"peer_id": p.peer_id, "chip_delta": -ante, "crown_delta": 0, "heat_delta": 0})
		else:
			p.is_active_this_event = false
	if deltas.size() > 0 and is_host:
		_send_rpc("_rpc_apply_deltas", [deltas])

func _process_event_selection() -> void:
	var pool = MatchConfig.EVENT_POOL
	var idx = state.rng.randi() % pool.size()
	state.current_event_id = pool[idx]

func _process_bet_loadout() -> void:
	if not is_host:
		return
	state.pending_wagers = {}
	var active_peer_ids: Array = []
	var max_per_player: int = 0
	for p in state.players:
		if p.is_active_this_event:
			active_peer_ids.append(p.peer_id)
			max_per_player = max(max_per_player, int(p.chips * MatchConfig.ROCKET_CLASH_MAX_WAGER_FACTOR))
	bet_loadout_started.emit(active_peer_ids, max_per_player)
	var timeout_sec = _bet_loadout_timeout_sec()
	if timeout_sec <= 0.0:
		# Test path: bypass timer entirely.
		bet_loadout_finished.emit()
		return
	if not is_inside_tree():
		# Detached controller: no SceneTree to create timer.
		bet_loadout_finished.emit()
		return
	var timer = get_tree().create_timer(timeout_sec)
	while timer.time_left > 0.0:
		if _all_active_ready(active_peer_ids):
			break
		await get_tree().process_frame
	bet_loadout_finished.emit()

func _all_active_ready(active_peer_ids: Array) -> bool:
	for pid in active_peer_ids:
		if not state.pending_wagers.has(pid):
			return false
	return true

func _process_shop() -> void:
	if not is_host:
		return
	var pool = CardRegistry.shop_pool().duplicate()
	pool.shuffle()
	state.current_shop_offer = pool.slice(0, min(MatchConfig.SHOP_OFFER_SIZE, pool.size()))
	state.shop_done_peers = []
	_send_rpc("_rpc_shop_opened", [state.current_shop_offer.duplicate()])
	shop_opened.emit(state.current_shop_offer.duplicate())
	var timeout_sec = _shop_timeout_sec()
	if timeout_sec <= 0.0:
		# Test-bypass path: shop is open; do NOT await, do NOT auto-close.
		# Tests inspect state.current_shop_offer/shop_opened immediately. Any
		# test exercising the close path calls _close_shop() directly.
		return
	if not is_inside_tree():
		# Detached controller (no scene): treat like timeout=0 — caller
		# drives the close path explicitly.
		return
	var timer = get_tree().create_timer(timeout_sec)
	while timer.time_left > 0.0:
		if not is_inside_tree():
			return  # node freed (e.g. add_child_autofree cleanup); abort silently
		if _all_active_done_in_shop():
			break
		await get_tree().process_frame
	_close_shop()

func _all_active_done_in_shop() -> bool:
	for p in state.players:
		if p.is_active_this_event and not (p.peer_id in state.shop_done_peers):
			return false
	return true

func _close_shop() -> void:
	state.current_shop_offer = []
	state.shop_done_peers = []
	_send_rpc("_rpc_shop_closed", [])
	shop_closed.emit()

func _card_cost(card_id: String) -> int:
	var card = CardRegistry.get_card(card_id)
	return int(card.get("cost_chips", 0))

@rpc("any_peer", "call_local", "reliable")
func _rpc_shop_buy_requested(peer_id: int, card_id: String) -> void:
	if not is_host:
		return
	if state.phase != MatchPhase.Phase.SHOP:
		return
	if not (card_id in state.current_shop_offer):
		_send_rpc_to_peer(peer_id, "_rpc_shop_buy_rejected", [card_id, "not_in_offer"])
		return
	if peer_id in state.shop_done_peers:
		return  # silent: second buy attempt
	var player = state.find_player(peer_id)
	if player == null:
		return
	var cost = _card_cost(card_id)
	if player.chips < cost:
		_send_rpc_to_peer(peer_id, "_rpc_shop_buy_rejected", [card_id, "insufficient_chips"])
		return
	if player.hand.size() >= MatchConfig.MAX_HAND_SIZE:
		_send_rpc_to_peer(peer_id, "_rpc_shop_buy_rejected", [card_id, "hand_full"])
		return
	player.chips -= cost
	player.hand.append(card_id)
	state.shop_done_peers.append(peer_id)
	player_resources_changed.emit(peer_id)
	_send_rpc("_rpc_shop_purchase_confirmed", [peer_id, card_id, cost])
	_send_rpc("_rpc_apply_deltas", [[{"peer_id": peer_id, "chip_delta": -cost, "crown_delta": 0, "heat_delta": 0}]])
	shop_purchase_confirmed.emit(peer_id, card_id, cost)

@rpc("any_peer", "call_local", "reliable")
func _rpc_shop_done(peer_id: int) -> void:
	if not is_host:
		return
	if state.phase != MatchPhase.Phase.SHOP:
		return
	if not (peer_id in state.shop_done_peers):
		state.shop_done_peers.append(peer_id)

@rpc("authority", "call_remote", "reliable")
func _rpc_shop_opened(offered: Array) -> void:
	state.current_shop_offer = offered.duplicate()
	state.shop_done_peers = []
	shop_opened.emit(offered)

@rpc("authority", "call_remote", "reliable")
func _rpc_shop_closed() -> void:
	state.current_shop_offer = []
	state.shop_done_peers = []
	shop_closed.emit()

@rpc("authority", "call_remote", "reliable")
func _rpc_shop_purchase_confirmed(peer_id: int, card_id: String, cost_chips: int) -> void:
	var player = state.find_player(peer_id)
	if player != null and not (card_id in player.hand):
		player.hand.append(card_id)
	shop_purchase_confirmed.emit(peer_id, card_id, cost_chips)

@rpc("authority", "call_remote", "reliable")
func _rpc_shop_buy_rejected(card_id: String, reason: String) -> void:
	shop_purchase_rejected.emit(0, card_id, reason)

func submit_shop_buy(card_id: String) -> void:
	var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
	_send_rpc("_rpc_shop_buy_requested", [my_peer_id, card_id])

func submit_shop_done() -> void:
	var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
	_send_rpc("_rpc_shop_done", [my_peer_id])

func _process_main_event() -> void:
	if state.current_event_id.is_empty():
		return
	# Defensive: clear any stale event node from a prior, unfinished MAIN_EVENT.
	if _current_event_node != null:
		_current_event_node.queue_free()
		_current_event_node = null
	_current_event_node = _event_factory.call(state.current_event_id)
	if _current_event_node == null:
		# Load failed for a non-empty path; synthesize empty result and advance.
		var empty_result = preload("res://scripts/events/event_result.gd").new()
		state.current_result = empty_result
		_advance_phase()
		return
	_current_event_node.event_complete.connect(_on_event_complete)
	event_starting.emit(_current_event_node.get_event_id(), state.event_index)
	_start_event_timeout_watchdog()
	var context = _build_event_context()
	_current_event_node._run(context)

func _build_event_context():
	var ctx = EventContext.new()
	for p in state.players:
		if p.is_active_this_event:
			ctx.players.append(p)
	ctx.event_index = state.event_index
	ctx.rng_seed = state.rng_seed ^ (state.event_index * 0x9E3779B9)
	ctx.is_host = is_host
	if not state.pending_wagers.is_empty():
		for p in ctx.players:
			ctx.wagers[p.peer_id] = state.pending_wagers.get(p.peer_id, 0)
	else:
		var ante = MatchConfig.ANTE_BY_EVENT_INDEX[state.event_index]
		for p in ctx.players:
			ctx.wagers[p.peer_id] = ante
	# Thread event_modifiers into the context so card effects + event runtime can read them.
	ctx.event_modifiers = state.event_modifiers.duplicate(true)
	return ctx

func _on_event_complete(result) -> void:
	state.current_result = result
	_clear_event_timeout_watchdog()
	if _current_event_node != null:
		_current_event_node.queue_free()
		_current_event_node = null
	_advance_phase()

func _on_event_timeout() -> void:
	_clear_event_timeout_watchdog()
	if _current_event_node == null:
		return
	var empty = preload("res://scripts/events/event_result.gd").new()
	# Build all-zero deltas for active players
	for p in state.players:
		if p.is_active_this_event:
			empty.per_player[p.peer_id] = {"chip_delta": 0, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0}
	state.current_result = empty
	_current_event_node.queue_free()
	_current_event_node = null
	_advance_phase()

# Internal: advance the phase machine. Each phase decides what to do next.
# Real phase behavior (ANTE deduction, EVENT_SELECTION pick, MAIN_EVENT run,
# RESOLUTION pipeline) is filled in by Tasks 9-12.
func _advance_phase() -> void:
	if _paused:
		return
	var next_phase: int
	match state.phase:
		MatchPhase.Phase.HOUSE_REVEAL:
			next_phase = MatchPhase.Phase.ANTE
		MatchPhase.Phase.ANTE:
			next_phase = MatchPhase.Phase.EVENT_SELECTION
		MatchPhase.Phase.EVENT_SELECTION:
			next_phase = MatchPhase.Phase.BET_LOADOUT
		MatchPhase.Phase.BET_LOADOUT:
			next_phase = MatchPhase.Phase.MAIN_EVENT
		MatchPhase.Phase.MAIN_EVENT:
			next_phase = MatchPhase.Phase.RESOLUTION
		MatchPhase.Phase.RESOLUTION:
			next_phase = MatchPhase.Phase.BOUNTY_HEAT_UPDATE
		MatchPhase.Phase.BOUNTY_HEAT_UPDATE:
			next_phase = MatchPhase.Phase.SHOP
		MatchPhase.Phase.SHOP:
			next_phase = MatchPhase.Phase.HOUSE_TWIST
		MatchPhase.Phase.HOUSE_TWIST:
			if state.event_index < MatchConfig.QUICK_CLASH_EVENT_COUNT - 1:
				state.event_index += 1
				next_phase = MatchPhase.Phase.HOUSE_REVEAL
			else:
				next_phase = MatchPhase.Phase.MATCH_END
		_:
			return  # MATCH_END or unknown: do nothing
	_set_phase(next_phase)

func _schedule_advance() -> void:
	# Detached-controller test pattern (Plan A): when not in the scene tree
	# there's no SceneTree to create timers from, so advance synchronously.
	# This preserves the behavior of every Plan A unit test that constructs
	# MatchController.new(true, null) without add_child_autofree.
	if not is_inside_tree():
		_advance_phase()
		return
	var delay_ms: int = no_op_phase_delay_ms_override
	if delay_ms < 0:
		delay_ms = MatchConfig.NO_OP_PHASE_DELAY_MS
	if delay_ms > 0:
		await get_tree().create_timer(delay_ms / 1000.0).timeout
	_advance_phase()

func _resolution_step_delay_ms() -> int:
	if resolution_step_delay_ms_override >= 0:
		return resolution_step_delay_ms_override
	return MatchConfig.RESOLUTION_STEP_DELAY_MS

func _await_resolution_step_delay() -> void:
	if not is_inside_tree():
		return  # detached test path — no SceneTree available
	var ms = _resolution_step_delay_ms()
	if ms <= 0:
		return
	await get_tree().create_timer(ms / 1000.0).timeout

func _process_resolution_phase() -> void:
	var result = state.current_result
	if result == null:
		_advance_phase()
		return
	_emit_resolution_step("busts", _build_busts_payload(result))
	await _await_resolution_step_delay()
	_emit_resolution_step("cash_outs", _build_cash_outs_payload(result))
	await _await_resolution_step_delay()
	_apply_and_emit("chip_changes", result, "chip_delta")
	await _await_resolution_step_delay()
	_apply_and_emit("crown_awards", result, "crown_delta")
	await _await_resolution_step_delay()
	_emit_resolution_step("painful_reveal", result.painful_reveal)
	_advance_phase()

func _emit_resolution_step(step_name: String, payload: Dictionary) -> void:
	resolution_step.emit(step_name, payload)
	if is_host:
		_send_rpc("_rpc_resolution_step", [step_name, payload])

func _build_busts_payload(result) -> Dictionary:
	var bust_ids: Array = []
	for pid in result.per_player.keys():
		if result.bust_for(pid):
			bust_ids.append(pid)
	return {"bust_peer_ids": bust_ids}

func _build_cash_outs_payload(result) -> Dictionary:
	var co: Dictionary = {}
	for pid in result.per_player.keys():
		var entry = result.per_player[pid]
		co[pid] = entry.get("cash_out_at", 0.0)
	return {"cash_outs": co}

func _apply_and_emit(step_name: String, result, delta_key: String) -> void:
	var deltas: Array = []
	var broadcast_deltas: Array = []
	for pid in result.per_player.keys():
		var d = int(result.per_player[pid].get(delta_key, 0))
		if d == 0:
			continue
		var p = state.find_player(pid)
		if p == null:
			continue
		match delta_key:
			"chip_delta":
				p.chips += d
				broadcast_deltas.append({"peer_id": pid, "chip_delta": d, "crown_delta": 0, "heat_delta": 0})
			"crown_delta":
				p.crowns += d
				broadcast_deltas.append({"peer_id": pid, "chip_delta": 0, "crown_delta": d, "heat_delta": 0})
		deltas.append({"peer_id": pid, "delta": d})
		player_resources_changed.emit(pid)
	_emit_resolution_step(step_name, {"deltas": deltas})
	if broadcast_deltas.size() > 0 and is_host:
		_send_rpc("_rpc_apply_deltas", [broadcast_deltas])

func _process_bounty_heat_update() -> void:
	var result = state.current_result
	if result == null:
		return
	var broadcast_deltas: Array = []
	for pid in result.per_player.keys():
		var d = result.heat_delta_for(pid)
		if d == 0:
			continue
		var p = state.find_player(pid)
		if p == null:
			continue
		p.heat = clamp(p.heat + d, 0, MatchConfig.HEAT_MAX)
		player_resources_changed.emit(pid)
		broadcast_deltas.append({"peer_id": pid, "chip_delta": 0, "crown_delta": 0, "heat_delta": d})
	if broadcast_deltas.size() > 0 and is_host:
		_send_rpc("_rpc_apply_deltas", [broadcast_deltas])
	_resolve_bounties(result)

func _auto_place_bounties() -> void:
	if not is_host:
		return
	if state.event_index == 0:
		return  # No auto-placement on the very first event (no rankings yet)
	state.bounties = []
	var leader_id = _find_chip_leader_peer_id()
	var heat_id = _find_heat_leader_peer_id()
	var leader_target = state.find_player(leader_id)
	var heat_target = state.find_player(heat_id)
	var leader_bounty = Bounty.new()
	leader_bounty.origin = "leader"
	leader_bounty.target = leader_id
	leader_bounty.condition = "bust"
	leader_bounty.reward_chips = MatchConfig.BOUNTY_BASE_REWARD
	leader_bounty.placed_at_event = state.event_index
	leader_bounty.placed_at_target_heat = leader_target.heat if leader_target != null else 0
	var heat_bounty = Bounty.new()
	heat_bounty.origin = "heat"
	heat_bounty.target = heat_id
	heat_bounty.condition = "bust"
	heat_bounty.reward_chips = MatchConfig.BOUNTY_BASE_REWARD
	heat_bounty.placed_at_event = state.event_index
	heat_bounty.placed_at_target_heat = heat_target.heat if heat_target != null else 0
	state.bounties = [leader_bounty, heat_bounty]
	var serialized = [leader_bounty.to_dict(), heat_bounty.to_dict()]
	_send_rpc("_rpc_bounties_placed", [serialized])
	bounty_placed.emit(leader_bounty.to_dict())
	bounty_placed.emit(heat_bounty.to_dict())

func _find_chip_leader_peer_id() -> int:
	var leader = state.players[0] if state.players.size() > 0 else null
	for p in state.players:
		if p.chips > leader.chips:
			leader = p
	return leader.peer_id if leader != null else 0

func _find_heat_leader_peer_id() -> int:
	var leader = state.players[0] if state.players.size() > 0 else null
	for p in state.players:
		if p.heat > leader.heat:
			leader = p
	return leader.peer_id if leader != null else 0

func _resolve_bounties(result) -> void:
	if not is_host:
		return
	for bounty in state.bounties:
		var claimants: Array = []
		for p in state.players:
			if Bounty.satisfies(bounty, result, p.peer_id):
				claimants.append(p.peer_id)
		if claimants.is_empty():
			_send_rpc("_rpc_bounty_unclaimed", [bounty.to_dict()])
			bounty_unclaimed.emit(bounty.to_dict())
			continue
		var reward = Bounty.compute_reward(bounty)
		if claimants.size() == 1:
			var claimant = state.find_player(claimants[0])
			claimant.chips += reward
			player_resources_changed.emit(claimants[0])
			_send_rpc("_rpc_bounty_claimed", [claimants[0], bounty.to_dict(), reward])
			bounty_claimed.emit(claimants[0], bounty.to_dict(), reward)
		else:
			var split = int(reward / claimants.size())
			for c_id in claimants:
				var c = state.find_player(c_id)
				c.chips += split
				player_resources_changed.emit(c_id)
				_send_rpc("_rpc_bounty_claimed", [c_id, bounty.to_dict(), split])
				bounty_claimed.emit(c_id, bounty.to_dict(), split)
	state.bounties = []

func _deal_starter_pack() -> void:
	if not is_host:
		return
	var pool = CardRegistry.starter_pool()
	if pool.is_empty():
		return
	var serialized_hands: Dictionary = {}
	for p in state.players:
		var hand: Array = []
		for i in MatchConfig.STARTER_PACK_SIZE:
			var idx = state.rng.randi() % pool.size()
			hand.append(pool[idx])
		p.hand = hand
		serialized_hands[p.peer_id] = hand.duplicate()
	_send_rpc("_rpc_starter_pack_dealt", [serialized_hands])

@rpc("authority", "call_remote", "reliable")
func _rpc_starter_pack_dealt(hands: Dictionary) -> void:
	for pid_key in hands.keys():
		var pid = int(pid_key)
		var p = state.find_player(pid)
		if p != null:
			p.hand = hands[pid_key].duplicate()

func _process_match_end() -> void:
	var rankings = state.players.duplicate()
	rankings.sort_custom(func(a, b):
		if a.crowns != b.crowns: return a.crowns > b.crowns
		if a.chips != b.chips: return a.chips > b.chips
		return a.heat > b.heat
	)
	match_ended.emit(rankings)
	if is_host:
		var serialized: Array = []
		for p in rankings:
			serialized.append(p.to_dict())
		_send_rpc("_rpc_match_ended", [serialized])

# Host-only: signals all peers to leave the match scene. Called by
# MatchEndOverlay's Back-to-Lobby button. NetSession.return_to_lobby
# (from Plan A Task 6) is called separately by MatchScene.
func return_to_lobby() -> void:
	if not is_host:
		return
	_send_rpc("_rpc_return_to_lobby", [])

@rpc("any_peer", "call_local", "reliable")
func _rpc_card_play_requested(peer_id: int, card_id: String, target_peer_id: int, params) -> void:
	if not is_host:
		return
	var player = state.find_player(peer_id)
	if player == null:
		return
	if not (card_id in player.loadout):
		return  # silent reject; UI should not have shown this card
	if card_id in player.played_this_event:
		return  # idempotent silent drop (double-click guard)
	var card = CardRegistry.get_card(card_id)
	if card.is_empty():
		return
	var current_window = _current_timing_window()
	if card.get("timing", "") != current_window:
		return  # silent reject; timing mismatch
	if card.get("target_required", false) and target_peer_id == 0:
		_send_rpc_to_peer(peer_id, "_rpc_card_play_rejected", [card_id, "target_required"])
		return
	var ctx = _build_event_context()
	# For self-targeting cards, pass peer_id as target_peer_id; for target-required
	# cards, pass the actual target_peer_id the caller specified.
	var effect_target = peer_id if not card.get("target_required", false) else target_peer_id
	var effect_result = CardRegistry.apply_card(card_id, ctx, effect_target, params)
	if not effect_result.get("applied", false):
		_send_rpc_to_peer(peer_id, "_rpc_card_play_rejected", [card_id, "effect_declined"])
		return
	_apply_effect_result(effect_result, peer_id)
	player.played_this_event.append(card_id)
	_send_rpc("_rpc_card_effect_applied", [peer_id, card_id, effect_result])
	card_effect_applied.emit(peer_id, card_id, effect_result)

@rpc("authority", "call_remote", "reliable")
func _rpc_card_effect_applied(peer_id: int, card_id: String, effect_result: Dictionary) -> void:
	# Clients mirror via the same dispatcher
	_apply_effect_result(effect_result, peer_id)
	var player = state.find_player(peer_id)
	if player != null and not (card_id in player.played_this_event):
		player.played_this_event.append(card_id)
	card_effect_applied.emit(peer_id, card_id, effect_result)

@rpc("authority", "call_remote", "reliable")
func _rpc_card_play_rejected(card_id: String, reason: String) -> void:
	card_play_rejected.emit(card_id, reason)

func _current_timing_window() -> String:
	match state.phase:
		MatchPhase.Phase.BET_LOADOUT:
			return "bet_loadout"
		MatchPhase.Phase.MAIN_EVENT:
			return "cash_out"
		_:
			return ""

func _apply_effect_result(effect: Dictionary, peer_id: int) -> void:
	if not effect.get("applied", false):
		return
	var t = effect.get("type", "")
	match t:
		"insurance_pre":
			_ensure_modifiers(peer_id)
			state.event_modifiers[peer_id]["insurance_pre"] = true
		"heat_shield":
			_ensure_modifiers(peer_id)
			state.event_modifiers[peer_id]["heat_shield"] = true
		"wager_multiplier":
			_ensure_modifiers(peer_id)
			state.event_modifiers[peer_id]["wager_multiplier"] = float(effect.get("multiplier", 1.0))
		"late_cash_bonus":
			_ensure_modifiers(peer_id)
			state.event_modifiers[peer_id]["late_cash_bonus"] = true
			state.event_modifiers[peer_id]["late_cash_threshold"] = float(effect.get("threshold", 5.0))
			state.event_modifiers[peer_id]["late_cash_bonus_chips"] = int(effect.get("bonus_chips", 200))
		"underdog_multiplier":
			_ensure_modifiers(peer_id)
			state.event_modifiers[peer_id]["underdog_multiplier"] = float(effect.get("multiplier", 1.5))
		"double_or_nothing":
			var new_wager = int(effect.get("new_wager", 0))
			state.pending_wagers[peer_id] = new_wager
			# Only host re-broadcasts the wager change. Clients mirror via
			# _rpc_card_effect_applied -> this dispatcher; they must not re-broadcast.
			if is_host:
				_send_rpc("_rpc_wager_acknowledged", [peer_id, new_wager])
		_:
			push_warning("Unhandled effect type: %s" % t)

func _ensure_modifiers(peer_id: int) -> void:
	if not state.event_modifiers.has(peer_id):
		state.event_modifiers[peer_id] = {}

@rpc("authority", "call_remote", "reliable")
func _rpc_phase_changed(phase: int, ctx: Dictionary) -> void:
	state.phase = phase
	state.event_index = int(ctx.get("event_index", state.event_index))
	state.current_event_id = String(ctx.get("current_event_id", state.current_event_id))
	phase_changed.emit(phase)

@rpc("authority", "call_remote", "reliable")
func _rpc_apply_deltas(deltas: Array) -> void:
	for d in deltas:
		var pid = int(d.get("peer_id", 0))
		var p = state.find_player(pid)
		if p == null:
			continue
		var chip_d = int(d.get("chip_delta", 0))
		var crown_d = int(d.get("crown_delta", 0))
		var heat_d = int(d.get("heat_delta", 0))
		if chip_d != 0:
			p.chips += chip_d
		if crown_d != 0:
			p.crowns += crown_d
		if heat_d != 0:
			p.heat = clamp(p.heat + heat_d, 0, MatchConfig.HEAT_MAX)
		player_resources_changed.emit(pid)

@rpc("authority", "call_remote", "reliable")
func _rpc_resolution_step(step_name: String, payload: Dictionary) -> void:
	resolution_step.emit(step_name, payload)

@rpc("authority", "call_remote", "reliable")
func _rpc_match_ended(serialized_rankings: Array) -> void:
	var rankings: Array = []
	for d in serialized_rankings:
		rankings.append(MatchPlayer.from_dict(d))
	match_ended.emit(rankings)

@rpc("authority", "call_remote", "reliable")
func _rpc_return_to_lobby() -> void:
	request_return_to_lobby.emit()

@rpc("authority", "call_remote", "reliable")
func _rpc_bounties_placed(serialized_bounties: Array) -> void:
	state.bounties = []
	for d in serialized_bounties:
		state.bounties.append(Bounty.from_dict(d))
		bounty_placed.emit(d)

@rpc("authority", "call_remote", "reliable")
func _rpc_bounty_claimed(claimant_peer_id: int, bounty_dict: Dictionary, reward_chips: int) -> void:
	var p = state.find_player(claimant_peer_id)
	if p != null:
		p.chips += reward_chips
		player_resources_changed.emit(claimant_peer_id)
	bounty_claimed.emit(claimant_peer_id, bounty_dict, reward_chips)

@rpc("authority", "call_remote", "reliable")
func _rpc_bounty_unclaimed(bounty_dict: Dictionary) -> void:
	bounty_unclaimed.emit(bounty_dict)
