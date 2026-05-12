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

# Scene-tree refs (resolved in _ready)
@onready var _multiplier_label: Label = $VBox/MultiplierLabel if has_node("VBox/MultiplierLabel") else null
@onready var _cash_out_button: Button = $VBox/CashOutButton if has_node("VBox/CashOutButton") else null

const MatchConfig = preload("res://scripts/match/match_config.gd")

# Override the EventNode contract methods:

func get_event_id() -> String:
	return "rocket_clash"

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
	if _is_host and mult >= _crash_at and not _finished:
		_finish()

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
	for player in context.players:
		var pid = player.peer_id
		var wager = int(context.wagers.get(pid, 0))
		if busted.has(pid):
			result.per_player[pid] = {
				"chip_delta": -wager,
				"crown_delta": 0,
				"heat_delta": 0,
				"bust": true,
				"cash_out_at": 0.0,
			}
			summary.append({
				"peer_id": pid, "name": player.name, "cash_out_at": 0.0,
				"chip_delta": -wager, "busted": true, "wager": wager,
			})
		else:
			var cash_out_at = float(cash_outs.get(pid, 0.0))
			var chip_delta = int(wager * cash_out_at)
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
	# Award the Crown to the highest-cash-out survivor (if any survived).
	if winner_peer_id != 0:
		result.per_player[winner_peer_id]["crown_delta"] = 1
	result.painful_reveal = {
		"crash_at": crash_at,
		"winner_peer_id": winner_peer_id,
		"winner_name": winner_name,
		"cash_outs_summary": summary,
	}
	return result
