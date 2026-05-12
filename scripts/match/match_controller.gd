# Owns MatchState and drives the per-event 9-phase state machine.
# Host-authoritative: only the host mutates state and broadcasts via RPC.
# See spec sections 5 and 6.5 for the full design.
extends Node

const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")
const EventContext = preload("res://scripts/events/event_context.gd")

signal phase_changed(new_phase: int)
signal event_starting(event_id: String, event_index: int)
signal resolution_step(step_name: String, payload: Dictionary)
signal match_ended(rankings: Array)
signal player_resources_changed(peer_id: int)

var state: MatchState
var is_host: bool = false
var _multiplayer_node = null  # for RPC routing in production; null in unit tests

# Test seam: override per-step delay to 0 for synchronous tests.
# Plan A: declared for forward-compat; the synchronous pipeline below
# ignores it. Plan B wires this into a Timer-driven pacing path.
var resolution_step_delay_ms_override: int = -1

# Factory injected by tests; production code uses _default_event_factory.
# IMPORTANT: do NOT initialize at declaration — instance methods aren't
# bindable at field-init time in GDScript 2.0. Assigned in _init instead.
var _event_factory: Callable
var _current_event_node = null

func _default_event_factory(path: String):
	var ps = load(path)
	if ps == null:
		return null
	return ps.instantiate()

func _init(p_is_host: bool = false, multiplayer_node = null) -> void:
	is_host = p_is_host
	_multiplayer_node = multiplayer_node
	state = MatchState.new()
	_event_factory = Callable(self, "_default_event_factory")

func start_match(match_start) -> void:
	if not is_host:
		return
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
	_set_phase(MatchPhase.Phase.HOUSE_REVEAL)

func _set_phase(new_phase: int) -> void:
	state.phase = new_phase
	phase_changed.emit(new_phase)
	_enter_phase_behavior()

# Called on host when entering a phase to execute MVP behavior. Phases not
# covered here are no-ops (handled by _advance_phase chaining alone).
func _enter_phase_behavior() -> void:
	if not is_host:
		return
	match state.phase:
		MatchPhase.Phase.ANTE:
			_process_ante_phase()
		MatchPhase.Phase.EVENT_SELECTION:
			_process_event_selection()
		MatchPhase.Phase.MAIN_EVENT:
			_process_main_event()
		MatchPhase.Phase.RESOLUTION:
			_process_resolution_phase()
		MatchPhase.Phase.BOUNTY_HEAT_UPDATE:
			_process_bounty_heat_update()
		MatchPhase.Phase.MATCH_END:
			_process_match_end()
		_:
			pass

func _process_ante_phase() -> void:
	var ante = MatchConfig.ANTE_BY_EVENT_INDEX[state.event_index]
	for p in state.players:
		if p.chips >= ante:
			p.chips -= ante
			p.is_active_this_event = true
			player_resources_changed.emit(p.peer_id)
		else:
			p.is_active_this_event = false

func _process_event_selection() -> void:
	var pool = MatchConfig.EVENT_POOL
	var idx = state.rng.randi() % pool.size()
	state.current_event_id = pool[idx]

func _process_main_event() -> void:
	if state.current_event_id.is_empty():
		return
	_current_event_node = _event_factory.call(state.current_event_id)
	if _current_event_node == null:
		# Load failed for a non-empty path; synthesize empty result and advance.
		var empty_result = preload("res://scripts/events/event_result.gd").new()
		state.current_result = empty_result
		_advance_phase()
		return
	_current_event_node.event_complete.connect(_on_event_complete)
	event_starting.emit(_current_event_node.get_event_id(), state.event_index)
	var context = _build_event_context()
	_current_event_node._run(context)

func _build_event_context():
	var ctx = EventContext.new()
	for p in state.players:
		if p.is_active_this_event:
			ctx.players.append(p)
	ctx.event_index = state.event_index
	ctx.rng_seed = state.rng_seed ^ (state.event_index * 0x9E3779B9)
	var ante = MatchConfig.ANTE_BY_EVENT_INDEX[state.event_index]
	for p in ctx.players:
		ctx.wagers[p.peer_id] = ante
	return ctx

func _on_event_complete(result) -> void:
	state.current_result = result
	if _current_event_node != null:
		_current_event_node.queue_free()
		_current_event_node = null
	_advance_phase()

# Internal: advance the phase machine. Each phase decides what to do next.
# Real phase behavior (ANTE deduction, EVENT_SELECTION pick, MAIN_EVENT run,
# RESOLUTION pipeline) is filled in by Tasks 9-12.
func _advance_phase() -> void:
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

func _process_resolution_phase() -> void:
	var result = state.current_result
	if result == null:
		_advance_phase()
		return
	# Sequential substep emission. For tests, delay = 0 advances synchronously.
	_emit_resolution_step("busts", _build_busts_payload(result))
	_emit_resolution_step("cash_outs", _build_cash_outs_payload(result))
	_apply_and_emit("chip_changes", result, "chip_delta")
	_apply_and_emit("crown_awards", result, "crown_delta")
	_emit_resolution_step("painful_reveal", result.painful_reveal)
	_advance_phase()

func _emit_resolution_step(name: String, payload: Dictionary) -> void:
	resolution_step.emit(name, payload)

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
			"crown_delta":
				p.crowns += d
		deltas.append({"peer_id": pid, "delta": d})
		player_resources_changed.emit(pid)
	_emit_resolution_step(step_name, {"deltas": deltas})

func _process_bounty_heat_update() -> void:
	var result = state.current_result
	if result == null:
		return
	for pid in result.per_player.keys():
		var d = result.heat_delta_for(pid)
		if d == 0:
			continue
		var p = state.find_player(pid)
		if p == null:
			continue
		p.heat = clamp(p.heat + d, 0, MatchConfig.HEAT_MAX)
		player_resources_changed.emit(pid)

func _process_match_end() -> void:
	var rankings: Array = []
	for p in state.players:
		rankings.append(p)
	rankings.sort_custom(func(a, b):
		if a.crowns != b.crowns:
			return a.crowns > b.crowns
		if a.chips != b.chips:
			return a.chips > b.chips
		return a.heat > b.heat
	)
	match_ended.emit(rankings)
