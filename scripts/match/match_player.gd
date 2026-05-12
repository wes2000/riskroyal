# Per-player match-time state. Distinct from PlayerSlot (lobby identity).
# Built at match start by copying name/color/peer_id from PlayerSlot and
# initializing economy fields per MatchConfig.STARTING_CHIPS_BY_PLAYER_COUNT.
extends RefCounted

var peer_id: int = 0
var seat_index: int = -1
var name: String = ""
var color_index: int = -1
var chips: int = 0
var crowns: int = 0
var heat: int = 0
var is_active_this_event: bool = true
var hand: Array = []
var loadout: Array = []
var played_this_event: Array = []

func to_dict() -> Dictionary:
	return {
		"peer_id": peer_id,
		"seat_index": seat_index,
		"name": name,
		"color_index": color_index,
		"chips": chips,
		"crowns": crowns,
		"heat": heat,
		"is_active_this_event": is_active_this_event,
		"hand": hand.duplicate(),
		"loadout": loadout.duplicate(),
		"played_this_event": played_this_event.duplicate(),
	}

static func from_dict(d: Dictionary) -> RefCounted:
	var p = load("res://scripts/match/match_player.gd").new()
	p.peer_id = d.get("peer_id", 0)
	p.seat_index = d.get("seat_index", -1)
	p.name = d.get("name", "")
	p.color_index = d.get("color_index", -1)
	p.chips = d.get("chips", 0)
	p.crowns = d.get("crowns", 0)
	p.heat = d.get("heat", 0)
	p.is_active_this_event = d.get("is_active_this_event", true)
	p.hand = d.get("hand", []).duplicate()
	p.loadout = d.get("loadout", []).duplicate()
	p.played_this_event = d.get("played_this_event", []).duplicate()
	return p
