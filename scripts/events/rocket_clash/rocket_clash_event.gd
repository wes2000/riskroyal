# Rocket Clash event. Validates the EventNode contract with a real-time
# push-your-luck loop: live multiplier, hidden crash, host-authoritative
# cash-out validation. See docs/superpowers/specs/2026-05-12-rocket-clash
# -event-design.md for the full contract.
extends "res://scripts/events/event_node.gd"

const INSTABUST_PROB: float = 0.05
const MAX_CRASH_AT: float = 100.0
const CASH_OUT_TOLERANCE: float = 0.05

# Per-round state (host populates; mirrored on clients via _rpc_rocket_launched).
var _crash_at: float = 0.0
var _start_time_ms: int = 0
var _cash_outs: Dictionary = {}      # peer_id -> cash_out_at
var _active_peers: Array = []        # peer_ids active at launch
var _is_host: bool = false
var _finished: bool = false
var _stashed_context = null          # held so _finish can call compute_event_result

# RPC routing (mirror of MatchController's pattern). Tests inject
# FakeMultiplayerNode; production self-wires via the same pattern.
var _multiplayer_node = null

# Test seams
var _force_crash_at_override: float = -1.0  # negative = use RNG
var _growth_rate_override: float = -1.0     # negative = use MatchConfig

# Per-peer cash-out delay (ms). Populated by MatchController from
# Cash-Out Jammer card plays. Consumed in _rpc_cash_out_requested host
# handler — single use per entry, then erased.
var _pending_cash_out_delays: Dictionary = {}

# Scene-tree refs (resolved in _ready)
@onready var _multiplier_label: Label = $VBox/MultiplierLabel if has_node("VBox/MultiplierLabel") else null
@onready var _cash_out_button: Button = $VBox/CashOutButton if has_node("VBox/CashOutButton") else null

const MatchConfig = preload("res://scripts/match/match_config.gd")

# Override the EventNode contract methods:

func get_event_id() -> String:
	return "rocket_clash"

func _ready() -> void:
	if _cash_out_button != null:
		_cash_out_button.pressed.connect(_on_cash_out_button_pressed)

func _on_cash_out_button_pressed() -> void:
	# Local player wants to cash out. Snapshot the current multiplier and
	# route through _rpc_cash_out_requested. With the C1 fix (call_local),
	# the host's own click correctly dispatches to its own receiver too.
	if _start_time_ms == 0 or _finished:
		return  # rocket not running yet, or already crashed
	var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
	if _cash_outs.has(my_peer_id):
		return  # already cashed out
	var elapsed_ms = Time.get_ticks_msec() - _start_time_ms
	var growth = _growth_rate_override if _growth_rate_override >= 0.0 else MatchConfig.ROCKET_GROWTH_RATE
	var snapshot = multiplier_at(elapsed_ms, growth)
	_send_rpc("_rpc_cash_out_requested", [my_peer_id, snapshot])

func _run(context) -> void:
	_stashed_context = context
	_is_host = context.is_host
	_active_peers = []
	for p in context.players:
		_active_peers.append(p.peer_id)
	var rng = RandomNumberGenerator.new()
	rng.seed = context.rng_seed
	if not _is_host:
		return  # client waits for _rpc_rocket_launched
	# Production self-wire: if no injection and we're in tree, route via self.
	if _multiplayer_node == null and is_inside_tree():
		_multiplayer_node = self
	# Compute crash_at deterministically.
	if _force_crash_at_override >= 1.0:
		_crash_at = _force_crash_at_override
	else:
		_crash_at = compute_crash_at(rng)
	_start_time_ms = Time.get_ticks_msec()
	_send_rpc("_rpc_rocket_launched", [_start_time_ms, _crash_at])
	# Host also processes the rocket locally as if it received the broadcast.
	_on_rocket_launched_local(_start_time_ms, _crash_at)

func _send_rpc(method_name: String, args: Array = []) -> void:
	if _multiplayer_node == null:
		return
	match args.size():
		0: _multiplayer_node.rpc(method_name)
		1: _multiplayer_node.rpc(method_name, args[0])
		2: _multiplayer_node.rpc(method_name, args[0], args[1])
		3: _multiplayer_node.rpc(method_name, args[0], args[1], args[2])

func _on_rocket_launched_local(start_time_ms: int, crash_at: float) -> void:
	_start_time_ms = start_time_ms
	_crash_at = crash_at
	set_process(true)

func _process(_delta: float) -> void:
	if _finished or _start_time_ms == 0:
		return
	var elapsed_ms = Time.get_ticks_msec() - _start_time_ms
	var growth = _growth_rate_override if _growth_rate_override >= 0.0 else MatchConfig.ROCKET_GROWTH_RATE
	var mult = multiplier_at(elapsed_ms, growth)
	if _multiplier_label != null:
		_multiplier_label.text = "%.2fx" % mult
	# Auto-eject check (host only). Per-frame, single fire per peer.
	if _is_host:
		var ejected = _check_auto_ejects(mult)
		for peer_id in ejected:
			# Broadcast as if the player cashed out — clients mirror via
			# _rpc_cash_out_confirmed which already updates their _cash_outs.
			_send_rpc("_rpc_cash_out_confirmed", [peer_id, mult])
	if _is_host and mult >= _crash_at and not _finished:
		_finish()

# Host-only per-frame check: auto-cashes any loaded player whose
# multiplier has reached their threshold. Returns the list of peer_ids
# that were auto-ejected this frame (used for broadcast).
func _check_auto_ejects(current_mult: float) -> Array:
	if not _is_host or _finished:
		return []
	if _stashed_context == null:
		return []
	var modifiers = _stashed_context.event_modifiers if "event_modifiers" in _stashed_context else {}
	var triggered: Array = []
	for peer_id in _active_peers:
		var m = modifiers.get(peer_id, {})
		if not m.get("auto_eject_loaded", false):
			continue
		if _cash_outs.has(peer_id):
			continue
		var threshold = float(m.get("auto_eject_threshold", 3.0))
		if current_mult >= threshold and current_mult < _crash_at:
			_cash_outs[peer_id] = current_mult
			triggered.append(peer_id)
			# Mark as played so the loadout-based per-frame check is idempotent
			# (no re-trigger). Spec sect 5.5. Find the player object via
			# _stashed_context.players (read-by-ref from state.players).
			for p in _stashed_context.players:
				if p.peer_id == peer_id and not ("emergency_eject" in p.played_this_event):
					p.played_this_event.append("emergency_eject")
					break
	return triggered

func _finish() -> void:
	_finished = true
	set_process(false)
	var busted: Array = []
	for pid in _active_peers:
		if not _cash_outs.has(pid):
			busted.append(pid)
	var result = compute_event_result(_stashed_context, _crash_at, _cash_outs, busted)
	event_complete.emit(result)

# RPC receiver for clients (and the host's own local invocation via _on_rocket_launched_local)
@rpc("authority", "call_remote", "reliable")
func _rpc_rocket_launched(start_time_ms: int, crash_at: float) -> void:
	_on_rocket_launched_local(start_time_ms, crash_at)

# Static helper: deterministic Aviator-style crash distribution from a
# seeded RNG. 5% instabust at 1.00x; otherwise max(1.0, 0.99 / (1 - r))
# capped at MAX_CRASH_AT. Tested without scene instantiation.
static func compute_crash_at(rng: RandomNumberGenerator) -> float:
	var instabust_roll = rng.randf()
	if instabust_roll < INSTABUST_PROB:
		return 1.0
	var r = rng.randf()
	if r >= 0.99:
		return MAX_CRASH_AT
	var crash = 0.99 / (1.0 - r)
	return max(1.0, min(crash, MAX_CRASH_AT))

# Exponential growth: multiplier(t) = exp(growth_rate × elapsed_sec).
# Used by every peer to compute its local display multiplier from the
# host-broadcast start_time_ms. Pure math, no SceneTree dependency.
static func multiplier_at(elapsed_ms: int, growth_rate: float) -> float:
	var elapsed_sec = float(elapsed_ms) / 1000.0
	return exp(growth_rate * elapsed_sec)

# Test seam: force a specific "current multiplier" for cash-out validation
# tests instead of computing from elapsed time. Negative = use real elapsed.
var _force_current_mult_for_testing: float = -1.0

func _current_multiplier_host() -> float:
	if _force_current_mult_for_testing >= 0.0:
		return _force_current_mult_for_testing
	var elapsed_ms = Time.get_ticks_msec() - _start_time_ms
	var growth = _growth_rate_override if _growth_rate_override >= 0.0 else MatchConfig.ROCKET_GROWTH_RATE
	return multiplier_at(elapsed_ms, growth)

func set_cash_out_delay(peer_id: int, delay_ms: int) -> void:
	_pending_cash_out_delays[peer_id] = delay_ms

@rpc("any_peer", "call_local", "reliable")
func _rpc_cash_out_requested(peer_id: int, snapshot_mult: float) -> void:
	if not _is_host:
		return  # only host validates
	if _finished:
		# Crash already fired; this cash-out arrived too late.
		_send_rpc_to_peer(peer_id, "_rpc_cash_out_rejected", [peer_id])
		return
	if _cash_outs.has(peer_id):
		# Double-click; silently drop.
		return
	# Cash-Out Jammer delay (Plan B). Track was_delayed locally so the
	# relaxed tolerance branch below fires even after we erase the entry.
	var was_delayed = false
	if _pending_cash_out_delays.has(peer_id):
		var delay_ms = _pending_cash_out_delays[peer_id]
		_pending_cash_out_delays.erase(peer_id)
		was_delayed = true
		if delay_ms > 0:
			await get_tree().create_timer(delay_ms / 1000.0).timeout
			# After the delay, re-evaluate. Bail if crashed during the wait
			# or if the peer somehow got cashed already.
			if _finished or _cash_outs.has(peer_id):
				return
	var host_mult = _current_multiplier_host()
	# Relaxed tolerance after a jammer delay (per spec sect 7.4): 5x CASH_OUT_TOLERANCE
	var tolerance = CASH_OUT_TOLERANCE * 5.0 if was_delayed else CASH_OUT_TOLERANCE
	if abs(snapshot_mult - host_mult) > tolerance:
		_send_rpc_to_peer(peer_id, "_rpc_cash_out_rejected", [peer_id])
		return
	_cash_outs[peer_id] = host_mult
	_send_rpc("_rpc_cash_out_confirmed", [peer_id, host_mult])

@rpc("authority", "call_remote", "reliable")
func _rpc_cash_out_confirmed(peer_id: int, accepted_mult: float) -> void:
	# Mirrored to all peers for HUD update. Host already updated _cash_outs.
	if not _is_host:
		_cash_outs[peer_id] = accepted_mult

@rpc("authority", "call_remote", "reliable")
func _rpc_cash_out_rejected(_peer_id: int) -> void:
	# Local UI hook only; data already correct on host.
	pass

# Targeted send (for rejecting back to the originator only).
func _send_rpc_to_peer(peer_id: int, method_name: String, args: Array) -> void:
	if _multiplayer_node == null:
		return
	match args.size():
		0: _multiplayer_node.rpc_id(peer_id, method_name)
		1: _multiplayer_node.rpc_id(peer_id, method_name, args[0])
		2: _multiplayer_node.rpc_id(peer_id, method_name, args[0], args[1])

const EventResult = preload("res://scripts/events/event_result.gd")

# Builds the EventResult per spec section 6.1. Survivors:
# chip_delta = wager × cash_out_at; bust: false; cash_out_at recorded.
# Busts: chip_delta = -wager; bust: true; cash_out_at = 0.
# Crown: 1 for the survivor with the highest cash_out_at; 0 otherwise.
# painful_reveal payload: crash_at + winner identity + per-player summary.
static func compute_event_result(context, crash_at: float, cash_outs: Dictionary, busted: Array) -> RefCounted:
	var result = EventResult.new()
	result.event_id = "rocket_clash"
	var summary: Array = []
	var winner_peer_id = 0
	var winner_name = ""
	var winner_cash_out = -1.0
	var modifiers = {}
	if context != null and "event_modifiers" in context:
		modifiers = context.event_modifiers
	for player in context.players:
		var pid = player.peer_id
		var wager = int(context.wagers.get(pid, 0))
		var p_mods = modifiers.get(pid, {})
		if busted.has(pid):
			var bust_loss = wager
			if p_mods.get("insurance_pre", false):
				bust_loss = int(wager / 2)  # Insurance halves bust penalty
			result.per_player[pid] = {
				"chip_delta": -bust_loss,
				"crown_delta": 0,
				"heat_delta": 0,
				"bust": true,
				"cash_out_at": 0.0,
			}
			summary.append({
				"peer_id": pid, "name": player.name, "cash_out_at": 0.0,
				"chip_delta": -bust_loss, "busted": true, "wager": wager,
			})
		else:
			var cash_out_at = float(cash_outs.get(pid, 0.0))
			var chip_delta = int(wager * cash_out_at)
			# Wager multiplier (Multiplier Booster)
			var wm = float(p_mods.get("wager_multiplier", 1.0))
			if wm != 1.0:
				chip_delta = int(chip_delta * wm)
			# Underdog multiplier
			var um = float(p_mods.get("underdog_multiplier", 1.0))
			if um != 1.0:
				chip_delta = int(chip_delta * um)
			# Late Cash bonus
			if p_mods.get("late_cash_bonus", false):
				var threshold = float(p_mods.get("late_cash_threshold", 5.0))
				var bonus = int(p_mods.get("late_cash_bonus_chips", 200))
				if cash_out_at > threshold:
					chip_delta += bonus
			result.per_player[pid] = {
				"chip_delta": chip_delta,
				"crown_delta": 0,
				"heat_delta": 0,
				"bust": false,
				"cash_out_at": cash_out_at,
			}
			summary.append({
				"peer_id": pid, "name": player.name, "cash_out_at": cash_out_at,
				"chip_delta": chip_delta, "busted": false, "wager": wager,
			})
			if cash_out_at > winner_cash_out:
				winner_cash_out = cash_out_at
				winner_peer_id = pid
				winner_name = player.name
	# Award the Crown + heat_delta to the highest-cash-out survivor
	if winner_peer_id != 0:
		result.per_player[winner_peer_id]["crown_delta"] = 1
		var winner_mods = modifiers.get(winner_peer_id, {})
		var heat_delta = 1
		if winner_mods.get("heat_shield", false):
			heat_delta = int(heat_delta / 2)  # Heat Shield halves heat_delta (1 -> 0)
		result.per_player[winner_peer_id]["heat_delta"] = heat_delta
	result.painful_reveal = {
		"crash_at": crash_at,
		"winner_peer_id": winner_peer_id,
		"winner_name": winner_name,
		"cash_outs_summary": summary,
	}
	return result
