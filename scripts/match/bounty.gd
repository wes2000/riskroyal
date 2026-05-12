# Bounty data class. Auto-placed at HOUSE_REVEAL (Leader + Heat) or
# manually placed via the Place Bounty card. Resolved at the end of
# BOUNTY_HEAT_UPDATE after heat application. Reward scales by Heat at
# placement time (captured in placed_at_target_heat) so Heat Shield can't
# suppress bounty rewards.
extends RefCounted

var origin: String = ""            # "leader" | "heat" | "placed"
var target: int = 0                # peer_id
var condition: String = ""         # "bust" (only condition in MVP)
var reward_chips: int = 0          # base reward (pre-heat-multiplier)
var placed_by: int = 0             # peer_id of placer; 0 for auto
var placed_at_event: int = 0       # event_index at placement
var placed_at_target_heat: int = 0 # target's heat at placement time

func to_dict() -> Dictionary:
	return {
		"origin": origin,
		"target": target,
		"condition": condition,
		"reward_chips": reward_chips,
		"placed_by": placed_by,
		"placed_at_event": placed_at_event,
		"placed_at_target_heat": placed_at_target_heat,
	}

static func from_dict(d: Dictionary) -> RefCounted:
	var b = load("res://scripts/match/bounty.gd").new()
	b.origin = d.get("origin", "")
	b.target = int(d.get("target", 0))
	b.condition = d.get("condition", "")
	b.reward_chips = int(d.get("reward_chips", 0))
	b.placed_by = int(d.get("placed_by", 0))
	b.placed_at_event = int(d.get("placed_at_event", 0))
	b.placed_at_target_heat = int(d.get("placed_at_target_heat", 0))
	return b

# Returns true if the claimant satisfies the bounty against the given
# event result. Claimant must not be the target and must not have busted.
static func satisfies(bounty, result, claimant_peer_id: int) -> bool:
	if claimant_peer_id == bounty.target:
		return false
	if result.bust_for(claimant_peer_id):
		return false
	match bounty.condition:
		"bust":
			return result.bust_for(bounty.target)
		_:
			return false

# Heat-scaled reward. Uses placed_at_target_heat captured at placement so
# Heat Shield (which halves event-time heat_delta) doesn't reduce payouts.
static func compute_reward(bounty) -> int:
	return int(bounty.reward_chips * _heat_multiplier(bounty.placed_at_target_heat))

# Heat-bounty scaling per design doc §6.5: 0-2 = base, 3-5 = +25%, 6-8 = +50%, 9-10 = +100%
static func _heat_multiplier(heat: int) -> float:
	if heat <= 2:
		return 1.0
	if heat <= 5:
		return 1.25
	if heat <= 8:
		return 1.5
	return 2.0
