# HeatRules: static-only helper for per-event Heat scaling. Heat reflects
# how loudly a player succeeded — safe wins generate little Heat, greedy
# wins generate dramatic Heat, busts generate none. The bounty layer uses
# accumulated Heat to scale bounty rewards.
#
# Plan A/B/C precedent: static-only Object helper (mirrors EventHelpers,
# PlayerSelectors, BountyResolver). Alpha remediation Phase C Change 3.
extends Object

static func rocket_heat(cash_out_at: float, won_crown: bool) -> int:
	if cash_out_at >= 10.0:
		return 4
	if cash_out_at >= 5.0:
		return 3
	if cash_out_at >= 2.5:
		return 2
	if won_crown:
		return 1
	return 0

static func bomb_pot_heat(pull_out_ms: int, bomb_at_sec: float, won_crown: bool, locked_share: int) -> int:
	var ratio = float(pull_out_ms) / max(1.0, bomb_at_sec * 1000.0)
	if ratio >= 0.95:
		return 4
	if ratio >= 0.80:
		return 3
	if won_crown:
		return 2
	if locked_share > 0:
		return 1
	return 0

static func card_cannon_heat(locked_score: int, won_crown: bool) -> int:
	if locked_score == 21:
		return 3
	if locked_score >= 19:
		return 2
	if won_crown:
		return 1
	return 0

static func apply_heat_shield(base: int, modifiers: Dictionary) -> int:
	if modifiers.get("heat_shield", false):
		return int(floor(float(base) * 0.5))
	return base
