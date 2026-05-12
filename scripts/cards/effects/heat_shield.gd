# Heat Shield card: halves the heat_delta the player takes from this event.
# Set during BET_LOADOUT; resolved in compute_event_result by halving
# result.per_player[peer_id].heat_delta before it propagates.
extends Object

const CARD_META: Dictionary = {
	"name": "Heat Shield",
	"rarity": "common",
	"category": "defense",
	"timing": "bet_loadout",
	"target_required": false,
	"cost_chips": 50,
	"description": "Halve the Heat you take from this event.",
}

static func apply(_context, _target_peer_id: int, _params = null) -> Dictionary:
	return {"type": "heat_shield", "applied": true}
