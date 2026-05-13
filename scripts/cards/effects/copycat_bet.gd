# Copycat Bet card: caller's wager copied from target's. Capped at
# caller's chip count (Plan A's Double-or-Nothing pattern).
# Dispatcher writes state.pending_wagers[caller] = new_wager and
# broadcasts _rpc_wager_acknowledged for caller only (target unchanged).
extends Object

const CARD_META: Dictionary = {
	"name": "Copycat Bet",
	"rarity": "rare",
	"category": "greed",
	"timing": "bet_loadout",
	"target_required": true,
	"cost_chips": 150,
	"description": "Copy target's wager amount. Capped at your chip count.",
}

static func apply(context, target_peer_id: int, params = null) -> Dictionary:
	var caller_peer_id = 0
	if params != null and params is Dictionary:
		caller_peer_id = int(params.get("caller_peer_id", 0))
	if caller_peer_id == target_peer_id:
		return {"applied": false, "type": "copycat_bet"}
	if context == null:
		return {"applied": false, "type": "copycat_bet"}
	var target_wager = int(context.wagers.get(target_peer_id, 0))
	var caller_chips = 0
	for p in context.players:
		if p.peer_id == caller_peer_id:
			caller_chips = p.chips
			break
	var new_wager = min(target_wager, caller_chips)
	return {
		"type": "copycat_bet",
		"applied": true,
		"source": caller_peer_id,
		"new_wager": new_wager,
	}
