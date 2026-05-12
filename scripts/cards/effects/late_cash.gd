# Late Cash card: if the player cashes out above 5.0x, +200 bonus chips.
# Always applies the flag; resolution in compute_event_result checks the
# cash_out_at threshold.
extends Object

const CARD_META: Dictionary = {
	"name": "Late Cash",
	"rarity": "common",
	"category": "greed",
	"timing": "bet_loadout",
	"target_required": false,
	"cost_chips": 50,
	"description": "If you cash out above 5.0x, +200 chips.",
}

static func apply(_context, _target_peer_id: int, _params = null) -> Dictionary:
	return {
		"type": "late_cash_bonus",
		"applied": true,
		"threshold": 5.0,
		"bonus_chips": 200,
	}
