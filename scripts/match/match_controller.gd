# Owns MatchState and drives the per-event 9-phase state machine.
# Host-authoritative: only the host mutates state and broadcasts via RPC.
# See spec sections 5 and 6.5 for the full design.
extends Node

const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")

signal phase_changed(new_phase: int)
signal event_starting(event_id: String, event_index: int)
signal resolution_step(step_name: String, payload: Dictionary)
signal match_ended(rankings: Array)
signal player_resources_changed(peer_id: int)

var state: MatchState
var is_host: bool = false
var _multiplayer_node = null  # for RPC routing in production; null in unit tests

func _init(p_is_host: bool = false, multiplayer_node = null) -> void:
	is_host = p_is_host
	_multiplayer_node = multiplayer_node
	state = MatchState.new()

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
