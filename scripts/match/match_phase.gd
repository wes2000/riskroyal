# Phase enum for the per-event 9-phase state machine.
# See docs/superpowers/specs/2026-05-11-match-loop-and-economy-design.md §5.5.
extends Object

enum Phase {
	HOUSE_REVEAL,
	ANTE,
	EVENT_SELECTION,
	BET_LOADOUT,
	MAIN_EVENT,
	RESOLUTION,
	BOUNTY_HEAT_UPDATE,
	SHOP,
	HOUSE_TWIST,
	MATCH_END,
}

static func name_for(phase: int) -> String:
	match phase:
		Phase.HOUSE_REVEAL: return "HOUSE_REVEAL"
		Phase.ANTE: return "ANTE"
		Phase.EVENT_SELECTION: return "EVENT_SELECTION"
		Phase.BET_LOADOUT: return "BET_LOADOUT"
		Phase.MAIN_EVENT: return "MAIN_EVENT"
		Phase.RESOLUTION: return "RESOLUTION"
		Phase.BOUNTY_HEAT_UPDATE: return "BOUNTY_HEAT_UPDATE"
		Phase.SHOP: return "SHOP"
		Phase.HOUSE_TWIST: return "HOUSE_TWIST"
		Phase.MATCH_END: return "MATCH_END"
		_: return "UNKNOWN"
