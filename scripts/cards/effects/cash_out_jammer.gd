# Cash-Out Jammer card: delays target's next cash-out by 750ms during
# the rocket. Effect dict carries target + delay_ms; dispatcher queues
# into RocketClashEvent._pending_cash_out_delays. Consumed by the next
# _rpc_cash_out_requested handler on host.
extends Object

const CARD_META: Dictionary = {
	"name": "Cash-Out Jammer",
	"rarity": "rare",
	"category": "sabotage",
	"timing": "cash_out",
	"target_required": true,
	"cost_chips": 150,
	"description": "Delay target's next cash-out attempt by 750ms.",
}

static func apply(_context, target_peer_id: int, params = null) -> Dictionary:
	var caller_peer_id = 0
	if params != null and params is Dictionary:
		caller_peer_id = int(params.get("caller_peer_id", 0))
	if caller_peer_id == target_peer_id:
		return {"applied": false, "type": "cash_out_delay"}
	return {
		"type": "cash_out_delay",
		"applied": true,
		"target": target_peer_id,
		"delay_ms": 750,
	}
