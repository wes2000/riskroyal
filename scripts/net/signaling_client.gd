# Real WebSocket signaling client.
# Honors res://scripts/net/signaling_client_interface.gd's signal contract.
extends RefCounted

const NetConfig = preload("res://scripts/net/net_config.gd")

signal code_issued(code: String)
signal peer_arriving(joiner_id: int, reconnect_token: String)
signal peer_id_assigned(peer_id: int)
signal match_started_ack()
signal host_left()
signal joiner_left(joiner_id: int)
signal signaling_error(reason: String)
signal signal_received(from_peer: int, payload: Dictionary)

var _ws
var _url: String
var _connected_url := false

func _init(ws_peer = null, url: String = NetConfig.SIGNALING_URL) -> void:
	if ws_peer == null:
		ws_peer = WebSocketPeer.new()
	_ws = ws_peer
	_url = url

func _ensure_connected() -> void:
	if _connected_url:
		return
	_ws.connect_to_url(_url)
	_connected_url = true

func _send(obj: Dictionary) -> void:
	_ensure_connected()
	var s := JSON.stringify(obj)
	_ws.put_packet(s.to_utf8_buffer())

func request_code() -> void:
	_send({"type": "host"})

func connect_to_code(code: String, reconnect_token: String = "") -> void:
	var msg := {"type": "join", "code": code}
	if reconnect_token != "":
		msg["reconnect_token"] = reconnect_token
	_send(msg)

func send_signal(to_peer: int, payload: Dictionary) -> void:
	_send({"type": "signal", "to": to_peer, "payload": payload})

func notify_connected(peer_id: int = 0) -> void:
	var msg := {"type": "connected"}
	if peer_id != 0:
		msg["peerId"] = peer_id
	_send(msg)

func send_start_match() -> void:
	_send({"type": "start_match"})

func close() -> void:
	_ws.close()
	_connected_url = false

# Called every tick by the autoload to drain inbound packets.
func pump() -> void:
	_ws.poll()
	while _ws.get_available_packet_count() > 0:
		var bytes: PackedByteArray = _ws.get_packet()
		var s: String = bytes.get_string_from_utf8()
		var parsed = JSON.parse_string(s)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		_dispatch_inbound(parsed)

func _dispatch_inbound(msg: Dictionary) -> void:
	match msg.get("type", ""):
		"code":
			code_issued.emit(msg.get("code", ""))
		"joined":
			peer_id_assigned.emit(int(msg.get("peerId", 0)))
		"joiner":
			var tok: String = msg.get("reconnect_token", "")
			peer_arriving.emit(int(msg.get("joinerId", 0)), tok)
		"signal":
			var payload = msg.get("payload", {})
			if typeof(payload) != TYPE_DICTIONARY:
				payload = {}
			signal_received.emit(int(msg.get("from", 0)), payload)
		"match_started":
			match_started_ack.emit()
		"host_left":
			host_left.emit()
		"joiner_left":
			joiner_left.emit(int(msg.get("joinerId", 0)))
		_:
			pass  # Other types in Task 6.
