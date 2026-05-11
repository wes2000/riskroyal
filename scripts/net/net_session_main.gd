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

	# Wire MultiplayerAPI so Godot RPCs work once peers connect.
	multiplayer.multiplayer_peer = _transport.get_multiplayer_peer()

	# Route NetSession welcome / sync emissions to actual RPCs.
	session.send_welcome_to.connect(_send_welcome)
	session.sync_player_list_to_all.connect(_broadcast_player_list)

func _process(_delta: float) -> void:
	if _signaling != null:
		_signaling.pump()
	if _transport != null:
		_transport.pump()

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
