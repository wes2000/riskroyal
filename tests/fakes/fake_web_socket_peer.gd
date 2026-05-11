# Test double for Godot's WebSocketPeer.
# Tests drive incoming packets via emit_packet(dict).
extends RefCounted

const STATE_CONNECTING := 0
const STATE_OPEN := 1
const STATE_CLOSING := 2
const STATE_CLOSED := 3

var connect_to_url_calls: Array = []
var sent_packets: Array = []
var close_calls: int = 0
var ready_state: int = STATE_CONNECTING

var _inbound_queue: Array = []

func connect_to_url(url: String, _tls_options = null) -> int:
	connect_to_url_calls.append({"url": url})
	ready_state = STATE_OPEN
	return OK

func poll() -> void:
	pass

func get_ready_state() -> int:
	return ready_state

func put_packet(bytes: PackedByteArray) -> int:
	sent_packets.append(bytes.get_string_from_utf8())
	return OK

func get_available_packet_count() -> int:
	return _inbound_queue.size()

func get_packet() -> PackedByteArray:
	if _inbound_queue.is_empty():
		return PackedByteArray()
	var s: String = _inbound_queue.pop_front()
	return s.to_utf8_buffer()

func close(_code: int = 1000, _reason: String = "") -> void:
	close_calls += 1
	ready_state = STATE_CLOSED

# --- test helpers ---

func emit_packet(obj) -> void:
	var s: String = JSON.stringify(obj) if typeof(obj) != TYPE_STRING else obj
	_inbound_queue.append(s)

func set_ready_state(s: int) -> void:
	ready_state = s
