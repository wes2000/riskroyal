# Test double for the future SignalingClient.
# Tests drive it by calling emit_* helpers directly.
extends RefCounted

signal code_issued(code: String)
signal peer_arriving(joiner_id: int, reconnect_token: String)
signal peer_id_assigned(peer_id: int)
signal match_started_ack()
signal host_left()
signal joiner_left(joiner_id: int)
signal signaling_error(reason: String)

var request_code_calls: int = 0
var connect_to_code_calls: Array = []
var send_signal_calls: Array = []
var notify_connected_calls: Array = []
var send_start_match_calls: int = 0
var closed: bool = false

func request_code() -> void:
	request_code_calls += 1

func connect_to_code(code: String, reconnect_token: String = "") -> void:
	connect_to_code_calls.append({"code": code, "reconnect_token": reconnect_token})

func send_signal(to: int, payload: Dictionary) -> void:
	send_signal_calls.append({"to": to, "payload": payload})

func notify_connected(peer_id: int = 0) -> void:
	notify_connected_calls.append(peer_id)

func send_start_match() -> void:
	send_start_match_calls += 1

func close() -> void:
	closed = true

# --- test helpers ---

func emit_code_issued(code: String) -> void:
	code_issued.emit(code)

func emit_peer_arriving(joiner_id: int, reconnect_token: String = "") -> void:
	peer_arriving.emit(joiner_id, reconnect_token)

func emit_peer_id_assigned(peer_id: int) -> void:
	peer_id_assigned.emit(peer_id)

func emit_match_started_ack() -> void:
	match_started_ack.emit()

func emit_host_left() -> void:
	host_left.emit()

func emit_joiner_left(joiner_id: int) -> void:
	joiner_left.emit(joiner_id)

func emit_signaling_error(reason: String) -> void:
	signaling_error.emit(reason)
