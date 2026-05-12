# Insurance card: if the player busts this event, recover 50% of wager
# (chip_delta = -wager/2 instead of -wager). Set during BET_LOADOUT;
# resolved in compute_event_result via the insurance_pre flag.
extends Object

const CARD_META: Dictionary = {
	"name": "Insurance",
	"rarity": "common",
	"category": "defense",
	"timing": "bet_loadout",
	"target_required": false,
	"cost_chips": 50,
	"description": "If you bust this event, recover 50% of your wager.",
}

static func apply(_context, _target_peer_id: int, _params = null) -> Dictionary:
	return {"type": "insurance_pre", "applied": true}
