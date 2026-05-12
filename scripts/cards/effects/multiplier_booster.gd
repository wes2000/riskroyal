# Multiplier Booster card: if the player survives, multiply their chip
# gain by 1.25. Set during BET_LOADOUT; resolved in compute_event_result.
extends Object

const CARD_META: Dictionary = {
	"name": "Multiplier Booster",
	"rarity": "rare",
	"category": "greed",
	"timing": "bet_loadout",
	"target_required": false,
	"cost_chips": 150,
	"description": "If you survive, your chip gain is multiplied by 1.25.",
}

static func apply(_context, _target_peer_id: int, _params = null) -> Dictionary:
	return {"type": "wager_multiplier", "applied": true, "multiplier": 1.25}
