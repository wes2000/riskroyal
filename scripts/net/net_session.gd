extends RefCounted

const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

signal players_changed()
signal state_changed(new_state: int)
signal session_ended(reason: String)

var _transport
var _signaling
var state: int = NetSessionState.State.IDLE
var is_host: bool = false
var local_peer_id: int = 0
var code: String = ""
var players: Array = []

func _init(transport, signaling_client):
	_transport = transport
	_signaling = signaling_client
	_connect_signals()

func _connect_signals() -> void:
	_signaling.code_issued.connect(_on_code_issued)

func host_session() -> void:
	is_host = true
	local_peer_id = 1
	_transport.start_host()
	_signaling.request_code()

func join_session(code_input: String) -> void:
	is_host = false
	_transport.start_client()
	_signaling.connect_to_code(code_input)

func leave_session() -> void:
	_transport.close()
	_signaling.close()
	players = []
	code = ""
	is_host = false
	local_peer_id = 0
	_set_state(NetSessionState.State.IDLE)

func _on_code_issued(new_code: String) -> void:
	code = new_code
	var host_slot = PlayerSlot.new()
	host_slot.peer_id = 1
	host_slot.is_host = true
	host_slot.seat_index = 0
	players = [host_slot]
	_set_state(NetSessionState.State.LOBBY)
	players_changed.emit()

func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)
