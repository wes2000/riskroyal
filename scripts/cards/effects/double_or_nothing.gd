# Stub effect — Task 7-9 fill in real logic.
extends Object

const CARD_META: Dictionary = {
	"name": "stub",
	"rarity": "common",
	"category": "stub",
	"timing": "bet_loadout",
	"target_required": false,
	"cost_chips": 0,
	"description": "Stub effect — Task 7-9 fills this in.",
}

static func apply(_context, _target_peer_id: int, _params = null) -> Dictionary:
	return {"applied": false, "type": "stub"}
