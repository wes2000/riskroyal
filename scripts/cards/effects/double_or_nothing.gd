# Double or Nothing card: double the player's wager (capped at chip count).
# Greedy: 2x reward on success, 2x penalty on bust. Returns the new wager
# amount; the dispatcher mutates state.pending_wagers[peer_id] = new_wager.
extends Object

const CARD_META: Dictionary = {
	"name": "Double or Nothing",
	"rarity": "rare",
	"category": "greed",
	"timing": "bet_loadout",
	"target_required": false,
	"cost_chips": 150,
	"description": "Double your wager. 2x reward, 2x bust penalty.",
}

static func apply(context, target_peer_id: int, _params = null) -> Dictionary:
	if context == null:
		return {"applied": false, "type": "double_or_nothing"}
	var current_wager = int(context.wagers.get(target_peer_id, 0))
	var caller_chips = 0
	for p in context.players:
		if p.peer_id == target_peer_id:
			caller_chips = p.chips
			break
	var new_wager = min(current_wager * 2, caller_chips)
	return {
		"type": "double_or_nothing",
		"applied": true,
		"new_wager": new_wager,
	}
