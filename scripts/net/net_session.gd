extends RefCounted

const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")
const NetConfig = preload("res://scripts/net/net_config.gd")

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
	_transport.peer_joined.connect(_on_peer_joined)

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

func _on_peer_joined(peer_id: int) -> void:
	if not is_host:
		return  # joiners see peer events too but the host owns the list
	var slot = PlayerSlot.new()
	slot.peer_id = peer_id
	slot.seat_index = players.size()
	slot.connected = true
	slot.reconnect_token = _generate_token()
	players.append(slot)
	players_changed.emit()

func receive_player_info(peer_id: int, name: String, color_index: int) -> bool:
	var slot = _find_slot(peer_id)
	if slot == null:
		return false
	# validate color collision (skip the requesting slot itself if it had one)
	for other in players:
		if other.peer_id != peer_id and other.color_index == color_index and color_index >= 0:
			return false
	var normalized = _normalize_name(name, slot.seat_index + 1)
	slot.name = normalized
	slot.color_index = color_index
	players_changed.emit()
	return true

func _find_slot(peer_id: int):
	for s in players:
		if s.peer_id == peer_id:
			return s
	return null

func _normalize_name(name: String, fallback_index: int) -> String:
	var trimmed = name.strip_edges().substr(0, 16)
	if trimmed.is_empty():
		return "Player %d" % fallback_index
	return trimmed

func _generate_token() -> String:
	return "%016x" % [randi() | (randi() << 32)]

func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)
