# Emergency Eject card: loaded during BET_LOADOUT; RocketClashEvent's
# per-frame check (Task 10) auto-cashes the player at 3.0x if they
# haven't cashed out yet and the multiplier is below crash.
# Returns a flag-only effect dict; dispatcher (Task 8) writes
# state.event_modifiers[peer_id]["auto_eject_loaded"] = true.
extends Object

const CARD_META: Dictionary = {
	"name": "Emergency Eject",
	"rarity": "rare",
	"category": "defense",
	"timing": "bet_loadout",
	"target_required": false,
	"cost_chips": 150,
	"description": "Auto-cash-out at 3.0x if you haven't cashed yet.",
}

static func apply(_context, _target_peer_id: int, _params = null) -> Dictionary:
	return {
		"type": "auto_eject_loaded",
		"applied": true,
		"threshold": 3.0,
	}
