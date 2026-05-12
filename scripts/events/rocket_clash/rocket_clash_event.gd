# Rocket Clash event. Validates the EventNode contract with a real-time
# push-your-luck loop: live multiplier, hidden crash, host-authoritative
# cash-out validation. See docs/superpowers/specs/2026-05-12-rocket-clash
# -event-design.md for the full contract.
extends "res://scripts/events/event_node.gd"

const INSTABUST_PROB: float = 0.05
const MAX_CRASH_AT: float = 100.0
const CASH_OUT_TOLERANCE: float = 0.05

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
