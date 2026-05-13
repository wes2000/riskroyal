# Place Bounty card: places a "placed"-origin Bounty on target. Reward
# scales by heat at placement time via captured placed_at_target_heat.
# Pure state mutation in dispatcher (appends to state.bounties).
extends Object

const MatchConfig = preload("res://scripts/match/match_config.gd")

const CARD_META: Dictionary = {
	"name": "Place Bounty",
	"rarity": "rare",
	"category": "social",
	"timing": "bet_loadout",
	"target_required": true,
	"cost_chips": 150,
	"description": "Place a 150-chip bounty on target. Anyone who busts them claims it.",
}

static func apply(context, target_peer_id: int, params = null) -> Dictionary:
	var caller_peer_id = 0
	var event_index = 0
	if params != null and params is Dictionary:
		caller_peer_id = int(params.get("caller_peer_id", 0))
		event_index = int(params.get("event_index", 0))
	if caller_peer_id == target_peer_id:
		return {"applied": false, "type": "place_bounty"}
	var target_heat = 0
	if context != null:
		for p in context.players:
			if p.peer_id == target_peer_id:
				target_heat = p.heat
				break
	return {
		"type": "place_bounty",
		"applied": true,
		"target": target_peer_id,
		"placed_by": caller_peer_id,
		"placed_at_target_heat": target_heat,
		"placed_at_event": event_index,
		"reward_chips": MatchConfig.BOUNTY_BASE_REWARD,
	}
