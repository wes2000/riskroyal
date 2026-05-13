# Bomb Pot event. Ante-locked timed survival. Hidden bomb timer (5-25s
# window with 5% instabust at 5s). Shared Pot Drain: per-tick share rate
# scales with active grabber count. Single player action: pull out to
# lock current share.
#
# Extends EventNode (sub-project #2 contract). compute_bomb_at +
# compute_event_result are testable without scene instantiation.
extends "res://scripts/events/event_node.gd"

const MatchConfig = preload("res://scripts/match/match_config.gd")
const EventResult = preload("res://scripts/events/event_result.gd")

# Per-round state (host populates; clients mirror per-RPC).
var _bomb_at_sec: float = 0.0             # hidden; set in _run via compute_bomb_at
var _start_time_ms: int = 0
var _pulled_out_peers: Array = []         # peer_ids who pulled out
var _pull_out_timestamps: Dictionary = {} # peer_id -> int elapsed_ms at pull-out
var _locked_shares: Dictionary = {}       # peer_id -> int chips locked at pull-out
var _shares_accumulator: Dictionary = {}  # peer_id -> float fractional chips (host-only)
var _active_peers: Array = []             # peer_ids active at launch
var _is_host: bool = false
var _finished: bool = false
var _stashed_context = null

# RPC routing (mirror of MatchController + RocketClashEvent pattern).
var _multiplayer_node = null

# Test seams
var _force_bomb_at_override: float = -1.0      # negative = use RNG
var _pot_growth_rate_override: float = -1.0    # negative = use MatchConfig

# Scene-tree refs (resolved in _ready; null in detached tests).
@onready var _pot_label: Label = $VBox/PotLabel if has_node("VBox/PotLabel") else null
@onready var _ticker_label: Label = $VBox/TickerLabel if has_node("VBox/TickerLabel") else null
@onready var _pull_out_button: Button = $VBox/PullOutButton if has_node("VBox/PullOutButton") else null

func get_event_id() -> String:
	return "bomb_pot"

func _ready() -> void:
	if _pull_out_button != null:
		_pull_out_button.pressed.connect(_on_pull_out_button_pressed)

func _on_pull_out_button_pressed() -> void:
	if _start_time_ms == 0 or _finished:
		return
	submit_pull_out()

func submit_pull_out() -> void:
	var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
	_send_rpc("_rpc_pull_out_requested", [my_peer_id])

# Override EventNode._run
func _run(context) -> void:
	_stashed_context = context
	_is_host = context.is_host
	_active_peers = []
	for p in context.players:
		if p.is_active_this_event:
			_active_peers.append(p.peer_id)
	if _is_host:
		if _force_bomb_at_override >= 0.0:
			_bomb_at_sec = _force_bomb_at_override
		else:
			# EventContext exposes rng_seed (not rng); derive a fresh RNG per
			# event from the seed for determinism. Same pattern as
			# RocketClashEvent._on_rocket_launched_local.
			var rng = RandomNumberGenerator.new()
			rng.seed = context.rng_seed
			_bomb_at_sec = compute_bomb_at(rng)
		_start_time_ms = Time.get_ticks_msec()
		_send_rpc("_rpc_bomb_pot_started", [_start_time_ms])
	set_process(true)

# Host broadcast -> clients sync start time
@rpc("authority", "call_remote", "reliable")
func _rpc_bomb_pot_started(start_time_ms: int) -> void:
	_start_time_ms = start_time_ms

func _send_rpc(method_name: String, args: Array = []) -> void:
	if _multiplayer_node == null:
		return
	match args.size():
		0: _multiplayer_node.rpc(method_name)
		1: _multiplayer_node.rpc(method_name, args[0])
		2: _multiplayer_node.rpc(method_name, args[0], args[1])
		3: _multiplayer_node.rpc(method_name, args[0], args[1], args[2])
		_:
			push_error("BombPotEvent._send_rpc: unsupported arity %d" % args.size())

func _send_rpc_to_peer(peer_id: int, method_name: String, args: Array = []) -> void:
	if _multiplayer_node == null:
		return
	match args.size():
		0: _multiplayer_node.rpc_id(peer_id, method_name)
		1: _multiplayer_node.rpc_id(peer_id, method_name, args[0])
		2: _multiplayer_node.rpc_id(peer_id, method_name, args[0], args[1])
		_:
			push_error("BombPotEvent._send_rpc_to_peer: unsupported arity %d" % args.size())

@rpc("any_peer", "call_local", "reliable")
func _rpc_pull_out_requested(peer_id: int) -> void:
	if not _is_host:
		return
	if _finished or _start_time_ms == 0:
		return
	if peer_id in _pulled_out_peers:
		return  # silent double-tap drop
	if not (peer_id in _active_peers):
		return  # peer not in this event
	var elapsed_ms = Time.get_ticks_msec() - _start_time_ms
	_locked_shares[peer_id] = int(_shares_accumulator.get(peer_id, 0.0))
	_pull_out_timestamps[peer_id] = elapsed_ms
	_pulled_out_peers.append(peer_id)
	_send_rpc("_rpc_pull_out_confirmed", [peer_id, _locked_shares[peer_id], elapsed_ms])

@rpc("authority", "call_remote", "reliable")
func _rpc_pull_out_confirmed(peer_id: int, locked_share: int, pull_out_time_ms: int) -> void:
	if not (peer_id in _pulled_out_peers):
		_pulled_out_peers.append(peer_id)
	_locked_shares[peer_id] = locked_share
	_pull_out_timestamps[peer_id] = pull_out_time_ms

# ----- Static helpers (testable without scene) -----

# Returns a bomb detonation time in seconds, in [MIN, MAX]. ~5% chance
# of "instabust" at exactly MIN_DETONATION_SEC; otherwise uniform over
# the full window.
static func compute_bomb_at(rng: RandomNumberGenerator) -> float:
	var instabust_roll = rng.randf()
	if instabust_roll < MatchConfig.BOMB_POT_INSTABUST_PROB:
		return MatchConfig.BOMB_POT_MIN_DETONATION_SEC
	var r = rng.randf()
	var span = MatchConfig.BOMB_POT_MAX_DETONATION_SEC - MatchConfig.BOMB_POT_MIN_DETONATION_SEC
	var t = MatchConfig.BOMB_POT_MIN_DETONATION_SEC + span * r
	return clamp(t, MatchConfig.BOMB_POT_MIN_DETONATION_SEC, MatchConfig.BOMB_POT_MAX_DETONATION_SEC)
