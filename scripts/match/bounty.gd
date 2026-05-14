# Bounty data class. Auto-placed at HOUSE_REVEAL (Leader + Heat) or
# manually placed via the Place Bounty card. Resolved at the end of
# BOUNTY_HEAT_UPDATE after heat application. Reward scales by Heat at
# placement time (captured in placed_at_target_heat) so Heat Shield can't
# suppress bounty rewards.
extends RefCounted

const CardRegistry = preload("res://scripts/cards/card_registry.gd")

var origin: String = ""            # "leader" | "heat" | "placed"
var target: int = 0                # peer_id
var condition: String = ""         # "bust" | "bust_after_sabotage" | ...
var reward_chips: int = 0          # base reward (pre-heat-multiplier)
var placed_by: int = 0             # peer_id of placer; 0 for auto
var placed_at_event: int = 0       # event_index at placement
var placed_at_target_heat: int = 0 # target's heat at placement time
# Alpha remediation Phase C Change 4 (§8.3) attribution fields. Default to
# "survivors" so existing auto-placed bounties keep public-split semantics.
var claim_mode: String = "survivors"  # "survivors" | "placer" | "saboteur" | "best"
var event_id: String = ""             # optional event restriction; "" = any event
var condition_params: Dictionary = {} # extra params per condition (e.g., target_score)

func to_dict() -> Dictionary:
	return {
		"origin": origin,
		"target": target,
		"condition": condition,
		"reward_chips": reward_chips,
		"placed_by": placed_by,
		"placed_at_event": placed_at_event,
		"placed_at_target_heat": placed_at_target_heat,
		"claim_mode": claim_mode,
		"event_id": event_id,
		"condition_params": condition_params.duplicate(true),
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
	b.claim_mode = String(d.get("claim_mode", "survivors"))
	b.event_id = String(d.get("event_id", ""))
	b.condition_params = d.get("condition_params", {}).duplicate(true)
	return b

# Returns true if the claimant satisfies the bounty against the given
# event result. Claimant must not be the target and must not have busted.
# Phase C Change 4 (§8.4): adds "bust_after_sabotage" condition which
# additionally requires the target's sabotaged_by list to be non-empty.
static func satisfies(bounty, result, claimant_peer_id: int) -> bool:
	if claimant_peer_id == bounty.target:
		return false
	if result.bust_for(claimant_peer_id):
		return false
	match bounty.condition:
		"bust":
			return result.bust_for(bounty.target)
		"bust_after_sabotage":
			if not result.bust_for(bounty.target):
				return false
			var target_entry = result.per_player.get(bounty.target, {})
			var sabotaged = target_entry.get("sabotaged_by", [])
			return sabotaged is Array and sabotaged.size() > 0
		_:
			return false

# Heat-scaled reward. Uses placed_at_target_heat captured at placement so
# Heat Shield (which halves event-time heat_delta) doesn't reduce payouts.
static func compute_reward(bounty) -> int:
	return int(bounty.reward_chips * CardRegistry.heat_multiplier(bounty.placed_at_target_heat))
