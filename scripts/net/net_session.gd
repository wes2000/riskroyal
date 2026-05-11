extends RefCounted

const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")
const NetConfig = preload("res://scripts/net/net_config.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")

signal players_changed()
signal state_changed(new_state: int)
signal session_ended(reason: String)
signal match_starting(match_start)

# _transport must honor res://scripts/net/transport_interface.gd signal contract.
# _signaling must honor res://scripts/net/signaling_client_interface.gd signal contract.
# In Plan B, FakeTransport/FakeSignalingClient are passed in by tests.
# In Plan C, real WebRTCTransport/SignalingClient will be wired by the autoload bootstrap.
var _transport
var _signaling
var state: int = NetSessionState.State.IDLE
var pre_pause_state: int = NetSessionState.State.IDLE
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
	_transport.peer_left.connect(_on_peer_left)
	_signaling.host_left.connect(_on_host_left)
	_signaling.peer_arriving.connect(_on_peer_arriving)

func host_session() -> void:
	is_host = true
	local_peer_id = NetConfig.HOST_PEER_ID
	_transport.start_host()
	_signaling.request_code()

func join_session(code_input: String) -> void:
	is_host = false
	_transport.start_client()
	_signaling.connect_to_code(code_input)

func leave_session() -> void:
	_transport.close()
	_signaling.close()
	var had_players := players.size() > 0
	players = []
	code = ""
	is_host = false
	local_peer_id = 0
	_set_state(NetSessionState.State.IDLE)
	if had_players:
		players_changed.emit()

func _on_code_issued(new_code: String) -> void:
	code = new_code
	var host_slot = PlayerSlot.new()
	host_slot.peer_id = NetConfig.HOST_PEER_ID
	host_slot.is_host = true
	host_slot.seat_index = 0
	players = [host_slot]
	_set_state(NetSessionState.State.LOBBY)
	players_changed.emit()

func _on_peer_joined(peer_id: int) -> void:
	if not is_host:
		return  # joiners see peer events too but the host owns the list
	if players.size() >= NetConfig.MAX_PLAYERS:
		return
	var slot = PlayerSlot.new()
	slot.peer_id = peer_id
	slot.seat_index = players.size()
	slot.connected = true
	slot.reconnect_token = _generate_token()
	players.append(slot)
	players_changed.emit()

func receive_player_info(peer_id: int, name: String, color_index: int) -> bool:
	if state != NetSessionState.State.LOBBY:
		return false
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

func receive_set_ready(peer_id: int, value: bool) -> bool:
	if state != NetSessionState.State.LOBBY:
		return false
	var slot = _find_slot(peer_id)
	if slot == null:
		return false
	slot.ready = value
	players_changed.emit()
	return true

func receive_set_color(peer_id: int, color_index: int) -> bool:
	if state != NetSessionState.State.LOBBY:
		return false
	var slot = _find_slot(peer_id)
	if slot == null:
		return false
	for other in players:
		if other.peer_id != peer_id and other.color_index == color_index and color_index >= 0:
			return false
	slot.color_index = color_index
	players_changed.emit()
	return true

func kick(peer_id: int) -> bool:
	if not is_host:
		return false
	if state != NetSessionState.State.LOBBY:
		return false
	var slot = _find_slot(peer_id)
	if slot == null:
		return false
	players.erase(slot)
	# Reassign seat indices to remain contiguous.
	for i in players.size():
		players[i].seat_index = i
	players_changed.emit()
	return true

func start_match() -> bool:
	if not is_host:
		return false
	if state != NetSessionState.State.LOBBY:
		return false
	if players.size() < 2:
		return false
	for p in players:
		if not p.ready:
			return false

	var ms = MatchStart.new()
	ms.seats = players.duplicate()
	ms.host_peer_id = NetConfig.HOST_PEER_ID
	ms.rng_seed = randi() | (randi() << 32)
	ms.mode = "quick_clash"
	ms.rules = {}

	_signaling.send_start_match()
	_set_state(NetSessionState.State.MATCH)
	match_starting.emit(ms)
	return true

func _on_peer_left(peer_id: int) -> void:
	var slot = _find_slot(peer_id)
	if slot != null:
		slot.connected = false
	if state != NetSessionState.State.PAUSED:
		pre_pause_state = state
		_set_state(NetSessionState.State.PAUSED)
	players_changed.emit()

func _on_host_left() -> void:
	if state == NetSessionState.State.IDLE:
		return
	if state == NetSessionState.State.PAUSED:
		return  # already paused; don't overwrite pre_pause_state
	pre_pause_state = state
	_set_state(NetSessionState.State.PAUSED)

func _on_peer_arriving(joiner_id: int, reconnect_token: String) -> void:
	if not is_host:
		return
	if reconnect_token != "":
		var slot = _find_disconnected_by_token(reconnect_token)
		if slot != null:
			slot.peer_id = joiner_id
			slot.connected = true
			slot.reconnect_token = _generate_token()
			if state == NetSessionState.State.PAUSED:
				_set_state(pre_pause_state)
			players_changed.emit()
			return
	# Not a recognized reconnect -> normal new-join SDP path
	_transport.add_peer(joiner_id)

func _find_disconnected_by_token(token: String):
	for s in players:
		if not s.connected and s.reconnect_token == token:
			return s
	return null

func _on_grace_timeout() -> void:
	if state != NetSessionState.State.PAUSED:
		return

	if is_host:
		# Remove disconnected slots and resume from pre_pause_state.
		var to_remove = []
		for s in players:
			if not s.connected:
				to_remove.append(s)
		if to_remove.is_empty():
			_set_state(pre_pause_state)
			return
		for s in to_remove:
			players.erase(s)
		for i in players.size():
			players[i].seat_index = i
		_set_state(pre_pause_state)
		players_changed.emit()
	else:
		# Client lost host -> end session.
		leave_session()
		session_ended.emit("host_lost")

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
