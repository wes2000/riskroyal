# Wraps Godot 4.6's WebRTCMultiplayerPeer + per-peer WebRTCPeerConnection
# objects. Honors transport_interface.gd's signal contract plus signal_to_send
# for outbound SDP/ICE delivery (consumed by SignalingClient via NetSessionMain).
#
# Lifecycle:
#   1. start_host() creates the server-side multiplayer peer (peer_id=1).
#      start_client(local_peer_id) creates the client-side peer with the id
#      the signaling server assigned (must be >= 2; see Task 1).
#   2. add_peer(remote_id) creates a WebRTCPeerConnection for that remote.
#      Host calls create_offer() (host initiates); joiner waits for offer
#      via feed_remote_signal().
#   3. SDP and ICE flow out via signal_to_send(to_peer, payload).
#   4. SDP and ICE arrive via feed_remote_signal(from_peer, payload).
#   5. When connection reaches CONNECTED, emits peer_joined(remote_id).
extends RefCounted

const NetConfig = preload("res://scripts/net/net_config.gd")

signal peer_joined(id: int)
signal peer_left(id: int)
signal transport_failed(reason: String)
signal signal_to_send(to_peer: int, payload: Dictionary)

const _ICE_SERVERS := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]}

var _multiplayer_peer  # WebRTCMultiplayerPeer
var _connections: Dictionary = {}        # remote_peer_id -> WebRTCPeerConnection
var _join_emitted: Dictionary = {}       # remote_peer_id -> bool (dedupe peer_joined)
var _left_emitted: Dictionary = {}       # remote_peer_id -> bool (dedupe peer_left)
var _is_host: bool = false
var _local_peer_id: int = 0

func _init() -> void:
	_multiplayer_peer = WebRTCMultiplayerPeer.new()

func get_multiplayer_peer():
	return _multiplayer_peer

func start_host() -> void:
	_is_host = true
	_local_peer_id = NetConfig.HOST_PEER_ID
	_multiplayer_peer.create_server()

func start_client(local_peer_id: int) -> void:
	if local_peer_id < 2:
		transport_failed.emit("invalid_local_peer_id:%d" % local_peer_id)
		return
	_is_host = false
	_local_peer_id = local_peer_id
	_multiplayer_peer.create_client(local_peer_id)

func add_peer(remote_id: int) -> void:
	if _connections.has(remote_id):
		return
	var conn := WebRTCPeerConnection.new()
	var err := conn.initialize(_ICE_SERVERS)
	if err != OK:
		transport_failed.emit("ice_init_failed:%d" % err)
		return
	conn.session_description_created.connect(_on_sdp_created.bind(remote_id))
	conn.ice_candidate_created.connect(_on_ice_created.bind(remote_id))
	_connections[remote_id] = conn
	_multiplayer_peer.add_peer(conn, remote_id)
	if _is_host:
		conn.create_offer()
	# Else (joiner): wait for host's offer via feed_remote_signal.

func feed_remote_signal(from_peer: int, payload: Dictionary) -> void:
	if not _connections.has(from_peer):
		# Joiner receiving host's first offer — create the conn lazily.
		add_peer(from_peer)
	if not _connections.has(from_peer):
		return  # add_peer failed; transport_failed already emitted.
	var conn = _connections[from_peer]
	if payload.has("sdp_type"):
		var t: String = payload["sdp_type"]
		var sdp: String = payload.get("sdp", "")
		conn.set_remote_description(t, sdp)
		if t == "offer":
			conn.create_answer()
	elif payload.has("ice_candidate"):
		var ic: Dictionary = payload["ice_candidate"]
		var media: String = ic.get("media", "")
		var index: int = int(ic.get("index", 0))
		var cand_name: String = ic.get("name", "")
		conn.add_ice_candidate(media, index, cand_name)
	# else: malformed payload, ignore.

func close() -> void:
	for id in _connections.keys():
		var c = _connections[id]
		if c != null:
			c.close()
	_connections.clear()
	_join_emitted.clear()
	_left_emitted.clear()
	if _multiplayer_peer != null:
		_multiplayer_peer.close()

# Called every tick by the autoload. Detects newly-CONNECTED connections
# and emits peer_joined exactly once per peer.
#
# Note: We don't call _multiplayer_peer.poll() here because the autoload
# assigns this peer to MultiplayerAPI, which polls it every frame.
func pump() -> void:
	for id in _connections.keys():
		var c = _connections[id]
		if c == null:
			continue
		var s: int = c.get_connection_state()
		if s == WebRTCPeerConnection.STATE_CONNECTED and not _join_emitted.get(id, false):
			_join_emitted[id] = true
			peer_joined.emit(id)
		# Detect disconnect transitions for peer_left dedupe.
		if _join_emitted.get(id, false) and s != WebRTCPeerConnection.STATE_CONNECTED and not _left_emitted.get(id, false):
			_left_emitted[id] = true
			peer_left.emit(id)

func _on_sdp_created(type: String, sdp: String, remote_id: int) -> void:
	if not _connections.has(remote_id):
		return
	_connections[remote_id].set_local_description(type, sdp)
	signal_to_send.emit(remote_id, {"sdp_type": type, "sdp": sdp})

func _on_ice_created(media: String, index: int, cand_name: String, remote_id: int) -> void:
	signal_to_send.emit(remote_id, {"ice_candidate": {"media": media, "index": index, "name": cand_name}})
