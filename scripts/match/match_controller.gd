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
const CardEffectDispatcher = preload("res://scripts/match/card_effect_dispatcher.gd")
const BountyResolver = preload("res://scripts/match/bounty_resolver.gd")
const ShopController = preload("res://scripts/match/shop_controller.gd")
const MatchRpcSender = preload("res://scripts/match/match_rpc_sender.gd")
const HouseTwistController = preload("res://scripts/match/house_twist_controller.gd")

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
signal house_twist_announced(twist_dict: Dictionary)
signal event_picker_started(picker_peer_id: int, options: Array)
signal event_picker_resolved(chosen_path: String, reason: String)

var state: MatchState
var is_host: bool = false
var _multiplayer_node = null  # for RPC routing in production; null in unit tests
var _rpc_sender: MatchRpcSender = null

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

# Test seam: override EVENT_PICKER phase timeout. -1 = use MatchConfig.
# 0.0 = bypass timer entirely (synchronous host fallback).
var event_picker_timeout_sec_override: float = -1.0

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

func _event_picker_timeout_sec() -> float:
	if event_picker_timeout_sec_override >= 0.0:
		return event_picker_timeout_sec_override
	return float(MatchConfig.EVENT_PICKER_TIMEOUT_SEC)

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
	_rpc_sender = MatchRpcSender.new(multiplayer_node)
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
		_rpc_sender = MatchRpcSender.new(self)
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
	# Sub-project #6 Plan B Task 1: defensive reset of twist + event-pool
	# tracking. Production never reuses a controller instance, but this
	# closes the Plan A carry-forward documented in
	# project_riskroyal_followups.md.
	state.house_twist = {}
	state.last_twist_type = ""
	state.previous_event_id = ""
	# Deal starter pack of 3 random commons (excluding sabotage)
	_deal_starter_pack()
	_set_phase(MatchPhase.Phase.HOUSE_REVEAL)

func _send_rpc(method_name: String, args: Array = []) -> void:
	_rpc_sender.send(method_name, args)

func _send_rpc_to_peer(peer_id: int, method_name: String, args: Array = []) -> void:
	_rpc_sender.send_to_peer(peer_id, method_name, args)

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

# Public: called locally by EventPickerOverlay button presses on the
# picker peer.
func submit_event_pick(chosen_path: String) -> void:
	var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
	_send_rpc("_rpc_event_picker_choice", [my_peer_id, chosen_path])

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
			await _process_event_selection()
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
			_process_house_twist()
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
	# Plan B Task 4: defer to async picker flow when the twist is active.
	if state.house_twist.get("type", "") == "lowest_chips_picks":
		await _process_event_selection_with_picker()
		return
	# Plan A path: uniform random with no-repeat filter.
	_select_event_with_no_repeat()
	HouseTwistController.finalize_pending_params(state)
	_broadcast_sudden_death_finalized()

# Plan B Task 6: broadcast updated twist params after finalize_pending_params.
# Skipped unless the active twist is Sudden Death (avoids a round-trip for
# every event-selection in non-Sudden-Death rounds).
func _broadcast_sudden_death_finalized() -> void:
	if state.house_twist.get("type", "") != "sudden_death_jackpot":
		return
	if not is_host:
		return
	_send_rpc("_rpc_house_twist_params_updated", [state.house_twist.params])

# Plan B Task 6: client mirror for late-bind condition resolution.
# Replaces state.house_twist.params with the broadcast copy.
@rpc("authority", "call_remote", "reliable")
func _rpc_house_twist_params_updated(params: Dictionary) -> void:
	if state.house_twist.is_empty():
		return  # defensive: shouldn't happen, but tolerate
	state.house_twist["params"] = params.duplicate(true)

func _select_event_with_no_repeat() -> void:
	var pool = MatchConfig.EVENT_POOL.duplicate()
	if not state.previous_event_id.is_empty():
		pool.erase(state.previous_event_id)
		if pool.is_empty():
			pool = MatchConfig.EVENT_POOL.duplicate()
	var idx = state.rng.randi() % pool.size()
	state.current_event_id = pool[idx]
	state.previous_event_id = state.current_event_id

# Plan B Task 4: Lowest Chips Picks async picker flow.
# Host broadcasts picker UI start, awaits choice OR 10-second timeout,
# falls back to uniform-random pick from options on timeout. The host
# ALWAYS sets state.current_event_id before returning so the phase
# machine advances cleanly.
func _process_event_selection_with_picker() -> void:
	if not is_host:
		return
	var picker_peer_id = int(state.house_twist.params.get("picker_peer_id", 0))
	var options: Array = state.house_twist.params.get("options", [])
	if options.is_empty():
		# Defensive: no options to pick from. Fall back to Plan A path.
		_select_event_with_no_repeat()
		HouseTwistController.finalize_pending_params(state)
		_broadcast_sudden_death_finalized()
		return
	_send_rpc("_rpc_event_picker_started", [picker_peer_id, options])
	# Clear any stale prior pick
	state.current_event_id = ""
	var timeout_sec = _event_picker_timeout_sec()
	if timeout_sec <= 0.0:
		# Synchronous test path: skip the await entirely, fall through to
		# fallback. Tests can also pre-submit a choice via _rpc_event_picker_choice
		# before calling _process_event_selection if they want the happy path.
		pass
	elif not is_inside_tree():
		# Detached controller (some tests): no SceneTree for timer.
		pass
	else:
		var timer = get_tree().create_timer(timeout_sec)
		while timer.time_left > 0.0:
			if not state.current_event_id.is_empty():
				break  # picker submitted; _rpc_event_picker_choice set the id
			await get_tree().process_frame
	# Host fallback if no pick landed
	var reason = "submitted"
	if state.current_event_id.is_empty():
		var idx = state.rng.randi() % options.size()
		state.current_event_id = options[idx]
		reason = "timeout"
	state.previous_event_id = state.current_event_id
	HouseTwistController.finalize_pending_params(state)
	_broadcast_sudden_death_finalized()
	_send_rpc("_rpc_event_picker_resolved", [state.current_event_id, reason])

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

func _process_house_twist() -> void:
	if not is_host:
		return
	var twist = HouseTwistController.select_next_twist(state)
	state.house_twist = twist
	state.last_twist_type = twist.type
	HouseTwistController.apply_pre_event_effects(state, twist)
	# Broadcast AFTER apply_pre_event_effects: it mutates twist.params.cards_dealt
	# in-place; clients need the complete dict including dealt card IDs.
	_send_rpc("_rpc_house_twist_announced", [twist])
	house_twist_announced.emit(twist)

func _process_shop() -> void:
	if not is_host:
		return
	var offered = ShopController.open(state)
	_send_rpc("_rpc_shop_opened", [offered])
	shop_opened.emit(offered)
	var timeout_sec = _shop_timeout_sec()
	if timeout_sec <= 0.0:
		return
	if not is_inside_tree():
		return
	var timer = get_tree().create_timer(timeout_sec)
	while timer.time_left > 0.0:
		if not is_inside_tree():
			return  # node freed (e.g. add_child_autofree cleanup); abort silently
		if ShopController.all_active_done(state):
			break
		await get_tree().process_frame
	_close_shop()

func _close_shop() -> void:
	ShopController.close(state)
	_send_rpc("_rpc_shop_closed", [])
	shop_closed.emit()

@rpc("any_peer", "call_local", "reliable")
func _rpc_shop_buy_requested(peer_id: int, card_id: String) -> void:
	if not is_host:
		return
	if state.phase != MatchPhase.Phase.SHOP:
		return
	var v = ShopController.validate_buy(state, peer_id, card_id)
	match v.get("status", ""):
		"not_in_offer":
			_send_rpc_to_peer(peer_id, "_rpc_shop_buy_rejected", [card_id, "not_in_offer"])
			return
		"already_done":
			return  # silent
		"no_such_player":
			return  # silent
		"insufficient_chips":
			_send_rpc_to_peer(peer_id, "_rpc_shop_buy_rejected", [card_id, "insufficient_chips"])
			return
		"hand_full":
			_send_rpc_to_peer(peer_id, "_rpc_shop_buy_rejected", [card_id, "hand_full"])
			return
	var cost = int(v.get("cost", 0))
	ShopController.apply_buy(state, peer_id, card_id, cost)
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

# Plan B Task 5: picker UI start broadcast. Receives on all peers;
# picker peer's overlay shows buttons, non-pickers see a passive
# waiting banner. Re-emits a local signal for EventPickerOverlay.
@rpc("authority", "call_remote", "reliable")
func _rpc_event_picker_started(picker_peer_id: int, options: Array) -> void:
	event_picker_started.emit(picker_peer_id, options)

# Plan B Task 5: picker submits a choice. Host validates: must be the
# correct picker peer AND chosen_path must be in options. Silent reject
# on bad submit (the UI should not have shown buttons for invalid
# options); duplicate submits ignored because state.current_event_id
# is locked after the first valid pick.
@rpc("any_peer", "call_local", "reliable")
func _rpc_event_picker_choice(peer_id: int, chosen_path: String) -> void:
	if not is_host:
		return
	if state.house_twist.get("type", "") != "lowest_chips_picks":
		return  # twist already resolved or never active
	if not state.current_event_id.is_empty():
		return  # already locked (duplicate submit or timeout fired first)
	var picker_peer_id = int(state.house_twist.params.get("picker_peer_id", 0))
	if peer_id != picker_peer_id:
		return  # non-picker submission rejected
	var options: Array = state.house_twist.params.get("options", [])
	if not options.has(chosen_path):
		return  # invalid option rejected
	state.current_event_id = chosen_path

# Plan B Task 5: resolution broadcast. All peers receive the final
# picked event_id + reason (either "submitted" or "timeout") so the
# EventPickerOverlay can dismiss with the right message.
@rpc("authority", "call_remote", "reliable")
func _rpc_event_picker_resolved(chosen_path: String, reason: String) -> void:
	state.current_event_id = chosen_path
	state.previous_event_id = chosen_path
	event_picker_resolved.emit(chosen_path, reason)

@rpc("authority", "call_remote", "reliable")
func _rpc_house_twist_announced(twist_dict: Dictionary) -> void:
	state.house_twist = twist_dict.duplicate(true)
	state.last_twist_type = twist_dict.get("type", "")
	# Power Surge: mirror the host's bonus-card deal into each client's
	# local MatchPlayer.hand. Without this, clients show stale hands.
	var cards_dealt: Dictionary = twist_dict.get("params", {}).get("cards_dealt", {})
	for peer_id in cards_dealt:
		var card_id: String = String(cards_dealt[peer_id])
		for p in state.players:
			if p.peer_id == int(peer_id):
				p.hand.append(card_id)
				break
	house_twist_announced.emit(twist_dict)

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
	_inject_pending_event_effects()

# Called from MAIN_EVENT entry after _current_event_node is instantiated.
# Drains state.pending_card_effects of cash_out_delay entries and forwards
# them to the event via set_cash_out_delay. Other pending entries (heat_delta,
# wager_tax) stay queued for RESOLUTION's _apply_card_effects_to_result.
func _inject_pending_event_effects() -> void:
	if _current_event_node == null:
		return
	if not _current_event_node.has_method("set_cash_out_delay"):
		return
	var kept: Array = []
	for effect in state.pending_card_effects:
		if effect.get("type", "") == "cash_out_delay":
			_current_event_node.set_cash_out_delay(
				int(effect.get("target", 0)),
				int(effect.get("delay_ms", 750)),
			)
		else:
			kept.append(effect)
	state.pending_card_effects = kept

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
	# Sub-project #6 Plan A Task 8: thread house_twist + tuning_overrides
	ctx.house_twist = state.house_twist.duplicate(true)
	# tuning_overrides (Plan A wires infrastructure only; no Plan A twist
	# uses this yet, but Plan B's Sudden Death may). If state.house_twist
	# carries params.tuning_overrides, merge them into ctx.tuning AFTER
	# the event populates defaults in _run.
	# Note: the merge happens AFTER _run because event._run runs first
	# (it's called by _process_main_event after _build_event_context).
	# So we set a "pending overrides" key the event can read at end-of-_run,
	# or we delay the merge. Cleanest: keep tuning_overrides in
	# ctx.house_twist.params and let the event check it itself.
	# For Plan A: no merge implementation; just the snapshot. Plan B may
	# revisit.
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

# Walks state.pending_card_effects and mutates EventResult per-player
# deltas before the chip_changes broadcast. Currently handles wager_tax
# (20% chip redirect, no-op on bust or non-positive delta) and heat_delta
# (additive heat add). Called from RESOLUTION pipeline before chip_changes.
func _apply_card_effects_to_result(result) -> void:
	if result == null:
		state.pending_card_effects = []
		return
	for effect in state.pending_card_effects:
		var t = effect.get("type", "")
		match t:
			"wager_tax":
				var target_id = int(effect.get("target", 0))
				var source_id = int(effect.get("source", 0))
				if not result.per_player.has(target_id):
					continue
				if result.bust_for(target_id):
					continue  # no tax when target busted
				var target_delta = int(result.per_player[target_id].get("chip_delta", 0))
				if target_delta <= 0:
					continue  # only tax positive gains
				var tax = int(target_delta * 0.20)
				result.per_player[target_id]["chip_delta"] = target_delta - tax
				if result.per_player.has(source_id):
					var src_delta = int(result.per_player[source_id].get("chip_delta", 0))
					result.per_player[source_id]["chip_delta"] = src_delta + tax
			"heat_delta":
				var hd_target = int(effect.get("target", 0))
				var hd_delta = int(effect.get("delta", 0))
				if not result.per_player.has(hd_target):
					continue
				var existing = int(result.per_player[hd_target].get("heat_delta", 0))
				result.per_player[hd_target]["heat_delta"] = existing + hd_delta
	state.pending_card_effects = []

func _process_resolution_phase() -> void:
	var result = state.current_result
	if result == null:
		_advance_phase()
		return
	_emit_resolution_step("busts", _build_busts_payload(result))
	await _await_resolution_step_delay()
	_emit_resolution_step("cash_outs", _build_cash_outs_payload(result))
	await _await_resolution_step_delay()
	# NEW: apply pending card effects (Wager Tax, Heat Spike) before chip_changes
	# so the broadcast carries the modified deltas.
	_apply_card_effects_to_result(result)
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
	var placed = BountyResolver.auto_place(state)
	if placed.is_empty():
		return
	var serialized: Array = []
	for b in placed:
		serialized.append(b.to_dict())
		bounty_placed.emit(b.to_dict())
	_send_rpc("_rpc_bounties_placed", [serialized])

func _resolve_bounties(result) -> void:
	if not is_host:
		return
	var awards = BountyResolver.resolve(state, result)
	for award in awards:
		var claimant = int(award.get("claimant_peer_id", 0))
		var bounty_dict = award.get("bounty_dict", {})
		var reward = int(award.get("reward_chips", 0))
		if claimant == 0:
			_send_rpc("_rpc_bounty_unclaimed", [bounty_dict])
			bounty_unclaimed.emit(bounty_dict)
		else:
			player_resources_changed.emit(claimant)
			_send_rpc("_rpc_bounty_claimed", [claimant, bounty_dict, reward])
			bounty_claimed.emit(claimant, bounty_dict, reward)

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
	# Sub-project #6 Plan A: No Insurance twist gates the Insurance card.
	if card_id == "insurance" and state.house_twist.get("type", "") == "no_insurance":
		_send_rpc_to_peer(peer_id, "_rpc_card_play_rejected", [card_id, "no_insurance_twist"])
		return
	var ctx = _build_event_context()
	# For self-targeting cards, pass peer_id as target_peer_id; for target-required
	# cards, pass the actual target_peer_id the caller specified.
	var effect_target = peer_id if not card.get("target_required", false) else target_peer_id
	# Inject caller_peer_id + event_index for caller-aware cards (Plan B:
	# Wager Tax, Place Bounty, Copycat Bet). Pass-through any caller params.
	var dispatch_params = {}
	if params is Dictionary:
		dispatch_params = params.duplicate()
	dispatch_params["caller_peer_id"] = peer_id
	dispatch_params["event_index"] = state.event_index
	var effect_result = CardRegistry.apply_card(card_id, ctx, effect_target, dispatch_params)
	if not effect_result.get("applied", false):
		_send_rpc_to_peer(peer_id, "_rpc_card_play_rejected", [card_id, "effect_declined"])
		return
	_apply_effect_result(effect_result, peer_id)
	player.played_this_event.append(card_id)
	_send_rpc("_rpc_card_effect_applied", [peer_id, card_id, effect_result])
	card_effect_applied.emit(peer_id, card_id, effect_result)

# Client mirror of card play effects. Subtle emit symmetry: the host
# emits card_effect_applied in _rpc_card_play_requested (after broadcasting
# this RPC); clients emit here. With @rpc("call_remote") the host doesn't
# receive its own broadcast, so the host's emit happens only on the
# request side and the client's emit only on the mirror side — no double
# emits. If a future refactor changes the call mode, audit this carefully.
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
	CardEffectDispatcher.apply(state, peer_id, effect, is_host)
	# Outbound RPCs are host-only and post-state-mutation. The dispatcher
	# already updated state; we just need to broadcast for the 3 effect
	# types that broadcast.
	if not effect.get("applied", false):
		return
	if not is_host:
		return
	var t = effect.get("type", "")
	match t:
		"place_bounty":
			if state.bounties.size() > 0:
				var b = state.bounties.back()
				_send_rpc("_rpc_bounties_placed", [[b.to_dict()]])
				bounty_placed.emit(b.to_dict())
		"copycat_bet":
			var caller = int(effect.get("source", peer_id))
			var new_wager = int(effect.get("new_wager", 0))
			_send_rpc("_rpc_wager_acknowledged", [caller, new_wager])
		"double_or_nothing":
			var new_wager = int(effect.get("new_wager", 0))
			_send_rpc("_rpc_wager_acknowledged", [peer_id, new_wager])

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
