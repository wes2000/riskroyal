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
	# Self-wire _multiplayer_node when in-tree and not explicitly injected
	# (e.g. by tests). Matches RocketClashEvent's pattern so production RPC
	# routing works whenever MatchController adds the event to the scene tree.
	if _multiplayer_node == null and is_inside_tree():
		_multiplayer_node = self
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

# Override EventNode._process
func _process(delta: float) -> void:
	if _finished or _start_time_ms == 0:
		return
	# UI: pot growth label (clients estimate from local elapsed; host-authoritative
	# at finish via locked_shares broadcast).
	if _pot_label != null:
		var elapsed = (Time.get_ticks_msec() - _start_time_ms) / 1000.0
		var growth = _pot_growth_rate_override if _pot_growth_rate_override >= 0.0 else MatchConfig.BOMB_POT_POT_GROWTH_PER_SEC
		_pot_label.text = "Pot: %d chips" % int(elapsed * growth)
	if _ticker_label != null:
		_ticker_label.text = "Ticking..."
	# Host-only per-frame logic
	if not _is_host:
		return
	# Per-tick share accumulation
	var active_count = _active_peers.size() - _pulled_out_peers.size()
	var growth_rate = _pot_growth_rate_override if _pot_growth_rate_override >= 0.0 else MatchConfig.BOMB_POT_POT_GROWTH_PER_SEC
	var per_tick = compute_per_tick_share(delta, growth_rate, active_count)
	if per_tick > 0.0:
		for pid in _active_peers:
			if not (pid in _pulled_out_peers):
				_shares_accumulator[pid] = _shares_accumulator.get(pid, 0.0) + per_tick
	# Bomb timer check
	var elapsed_sec = (Time.get_ticks_msec() - _start_time_ms) / 1000.0
	if elapsed_sec >= _bomb_at_sec:
		_finish()
		return
	# Early finish: all active peers pulled out
	if active_count == 0:
		_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	set_process(false)
	var result = compute_event_result(_stashed_context, _bomb_at_sec, _locked_shares, _pulled_out_peers, _pull_out_timestamps)
	event_complete.emit(result)

# ----- Static helpers (testable without scene) -----

# Per-tick share each active grabber accrues. Returns 0 when no active
# grabbers (no one to draw from the pot). delta in seconds.
static func compute_per_tick_share(delta: float, pot_growth_per_sec: float, active_grabbers: int) -> float:
	if active_grabbers <= 0:
		return 0.0
	return delta * pot_growth_per_sec / float(active_grabbers)

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

static func compute_event_result(context, bomb_at_sec: float, locked_shares: Dictionary,
								 pulled_out_peers: Array, pull_out_timestamps: Dictionary) -> RefCounted:
	var result = EventResult.new()
	result.event_id = "bomb_pot"
	var summary: Array = []
	var winner_peer_id = 0
	var winner_pull_out_ms = -1
	var winner_seat = INF
	var modifiers = {}
	if context != null and "event_modifiers" in context:
		modifiers = context.event_modifiers
	for player in context.players:
		var pid = player.peer_id
		var wager = int(context.wagers.get(pid, 0))
		var p_mods = modifiers.get(pid, {})
		if pid in pulled_out_peers:
			# Survivor
			var chip_delta = int(locked_shares.get(pid, 0))
			var wm = float(p_mods.get("wager_multiplier", 1.0))
			if wm != 1.0:
				chip_delta = int(chip_delta * wm)
			var um = float(p_mods.get("underdog_multiplier", 1.0))
			if um != 1.0:
				chip_delta = int(chip_delta * um)
			result.per_player[pid] = {
				"chip_delta": chip_delta,
				"crown_delta": 0,
				"heat_delta": 0,
				"bust": false,
				"cash_out_at": 0.0,
			}
			summary.append({
				"peer_id": pid, "name": player.name,
				"locked_share": locked_shares.get(pid, 0),
				"pull_out_ms": pull_out_timestamps.get(pid, 0),
				"chip_delta": chip_delta, "busted": false, "wager": wager,
			})
			# Track latest puller (with seat_index tie-break)
			var ts = int(pull_out_timestamps.get(pid, 0))
			if ts > winner_pull_out_ms or (ts == winner_pull_out_ms and player.seat_index < winner_seat):
				winner_pull_out_ms = ts
				winner_peer_id = pid
				winner_seat = player.seat_index
		else:
			# Bust
			var bust_loss = wager
			if p_mods.get("insurance_pre", false):
				bust_loss = int(wager / 2)
			result.per_player[pid] = {
				"chip_delta": -bust_loss,
				"crown_delta": 0,
				"heat_delta": 0,
				"bust": true,
				"cash_out_at": 0.0,
			}
			summary.append({
				"peer_id": pid, "name": player.name,
				"locked_share": 0, "pull_out_ms": 0,
				"chip_delta": -bust_loss, "busted": true, "wager": wager,
			})
	# Crown + heat to last puller
	if winner_peer_id != 0:
		result.per_player[winner_peer_id]["crown_delta"] = 1
		var winner_mods = modifiers.get(winner_peer_id, {})
		var heat_delta = 1
		if winner_mods.get("heat_shield", false):
			heat_delta = int(heat_delta / 2)
		result.per_player[winner_peer_id]["heat_delta"] = heat_delta
	result.painful_reveal = {
		"bomb_at_sec": bomb_at_sec,
		"winner_peer_id": winner_peer_id,
		"winner_pull_out_ms": winner_pull_out_ms,
		"pulls_summary": summary,
	}
	return result
