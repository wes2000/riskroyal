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
