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
