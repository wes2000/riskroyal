# Autoload Node that bootstraps production NetSession with real
# SignalingClient, WebRTCTransport, and a Timer child. Exposed globally
# as `NetSessionMain`. Consumers access state via NetSessionMain.session.
extends Node

const _NetSession = preload("res://scripts/net/net_session.gd")
const _SignalingClient = preload("res://scripts/net/signaling_client.gd")
const _WebRTCTransport = preload("res://scripts/net/web_rtc_transport.gd")
const _NetConfig = preload("res://scripts/net/net_config.gd")

var session  # _NetSession
var _signaling  # _SignalingClient
var _transport  # _WebRTCTransport
var _timer: Timer
var _last_match_start = null
# Practice mode flag: when true, MatchScene treats the local peer as host
# regardless of session state and spawns BotControllers for non-host seats.
# Set by PracticeSession.start() before transitioning to the match scene.
var practice_mode: bool = false

func _ready() -> void:
	_signaling = _SignalingClient.new()
	_transport = _WebRTCTransport.new()
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = _NetConfig.RECONNECT_GRACE_SEC
	add_child(_timer)

	session = _NetSession.new(_transport, _signaling, _timer)

	# SDP/ICE bridge.
	_signaling.signal_received.connect(_transport.feed_remote_signal)
	_transport.signal_to_send.connect(_signaling.send_signal)

	# NOTE: multiplayer.multiplayer_peer is NOT set here. The WebRTCMultiplayerPeer
	# is in STATE_DISCONNECTED at autoload time (create_server / create_client
	# have not been called yet), and SceneMultiplayer rejects peers that are not
	# CONNECTING or CONNECTED. The attachment is deferred to _process via
	# _ensure_multiplayer_peer_attached() and happens once the transport has
	# started (host_session -> start_host or _on_peer_id_assigned -> start_client).

	# Route NetSession welcome / sync emissions to actual RPCs.
	session.send_welcome_to.connect(_send_welcome)
	session.sync_player_list_to_all.connect(_broadcast_player_list)

	# Cache the MatchStart payload so the placeholder match scene can read it
	# after the lobby transitions away.
	session.match_starting.connect(_on_match_starting)

	# Tell signaling when a P2P link is up so it can release relay slots.
	session.notify_signaling_connected.connect(_signaling.notify_connected)

func _process(_delta: float) -> void:
	_ensure_multiplayer_peer_attached()
	if _signaling != null:
		_signaling.pump()
	if _transport != null:
		_transport.pump()

func _ensure_multiplayer_peer_attached() -> void:
	if _transport == null:
		return
	if multiplayer.multiplayer_peer != _transport.get_multiplayer_peer():
		var peer = _transport.get_multiplayer_peer()
		if peer != null:
			var state = peer.get_connection_status()
			if state == MultiplayerPeer.CONNECTION_CONNECTING or state == MultiplayerPeer.CONNECTION_CONNECTED:
				multiplayer.multiplayer_peer = peer

func _send_welcome(target_peer_id: int, payload: Dictionary) -> void:
	rpc_id(target_peer_id, "_rpc_receive_welcome", payload)

func _broadcast_player_list(serialized_players: Array) -> void:
	rpc("_rpc_sync_player_list", serialized_players)

@rpc("any_peer", "reliable", "call_remote")
func _rpc_receive_welcome(payload: Dictionary) -> void:
	session.rpc_receive_welcome(payload)

@rpc("any_peer", "reliable", "call_remote")
func _rpc_sync_player_list(serialized_players: Array) -> void:
	session.rpc_sync_player_list(serialized_players)

func _on_match_starting(match_start) -> void:
	_last_match_start = match_start

func get_last_match_start():
	return _last_match_start

func set_last_match_start(ms) -> void:
	_last_match_start = ms
