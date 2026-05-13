# Wager Tax card: 20% of target's post-event chip gain redirected to
# caller. No-op if target busts (handled in RESOLUTION via bust_for guard).
# Apply-time guards: target must be active; caller cannot self-target.
extends Object

const CARD_META: Dictionary = {
	"name": "Wager Tax",
	"rarity": "common",
	"category": "sabotage",
	"timing": "bet_loadout",
	"target_required": true,
	"cost_chips": 50,
	"description": "Take 20% of target's chip gain this event.",
}

static func apply(context, target_peer_id: int, params = null) -> Dictionary:
	var caller_peer_id = 0
	if params != null and params is Dictionary:
		caller_peer_id = int(params.get("caller_peer_id", 0))
	if caller_peer_id == target_peer_id:
		return {"applied": false, "type": "post_event_wager_tax"}
	if context != null:
		for p in context.players:
			if p.peer_id == target_peer_id and not p.is_active_this_event:
				return {"applied": false, "type": "post_event_wager_tax"}
	return {
		"type": "post_event_wager_tax",
		"applied": true,
		"source": caller_peer_id,
		"target": target_peer_id,
	}
