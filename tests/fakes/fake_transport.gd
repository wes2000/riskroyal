# Test double for the future WebRTCTransport.
# Tests drive it by calling emit_* helpers directly.
extends RefCounted

signal peer_joined(id: int)
signal peer_left(id: int)
signal transport_failed(reason: String)

var is_hosting: bool = false
var add_peer_calls: Array = []
var closed: bool = false
var start_client_calls: Array = []  # array of peer_ids passed

func start_host() -> void:
	is_hosting = true

func start_client(local_peer_id: int = 0) -> void:
	is_hosting = false
	start_client_calls.append(local_peer_id)

func add_peer(joiner_id: int) -> void:
	add_peer_calls.append(joiner_id)

func close() -> void:
	closed = true

# --- test helpers ---

func emit_peer_joined(id: int) -> void:
	peer_joined.emit(id)

func emit_peer_left(id: int) -> void:
	peer_left.emit(id)

func emit_transport_failed(reason: String) -> void:
	transport_failed.emit(reason)
