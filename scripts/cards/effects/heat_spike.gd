# Heat Spike card: target gains +2 Heat post-event. Queued via
# state.pending_card_effects; applied to EventResult.per_player.heat_delta
# before chip_changes broadcast in RESOLUTION.
extends Object

const CARD_META: Dictionary = {
	"name": "Heat Spike",
	"rarity": "common",
	"category": "sabotage",
	"timing": "bet_loadout",
	"target_required": true,
	"cost_chips": 50,
	"description": "Target gains +2 Heat after this event.",
}

static func apply(_context, target_peer_id: int, _params = null) -> Dictionary:
	return {
		"type": "post_event_heat_delta",
		"applied": true,
		"target": target_peer_id,
		"delta": 2,
	}
