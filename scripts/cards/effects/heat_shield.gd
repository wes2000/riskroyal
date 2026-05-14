# Heat Shield card: halves the heat_delta the player takes from this event.
# Set during BET_LOADOUT; resolved in compute_event_result by halving
# result.per_player[peer_id].heat_delta before it propagates.
#
# Sub-project #7 Plan A Task 8: integer-division contract.
# The halving math lives in each event's Crown-award block:
#   var heat_delta = 1
#   if winner_mods.get("heat_shield", false):
#       heat_delta = int(heat_delta / 2)   # 1 -> 0
#
# All 3 events award heat_delta = 1 to the Crown winner today, so
# int(1 / 2) = 0 is the intentional "fully shield the rare 1-point
# heat hit" semantic — Heat Shield is a binary cancel under this
# value table. If a future House Twist or rebalance promotes
# heat_delta to 2 for some event, this card silently becomes "halve
# 2 to 1" (int(2/2) = 1) which is a behavior change — flag for spec
# revisit at that time.
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
