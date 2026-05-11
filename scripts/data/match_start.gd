extends RefCounted

const PlayerSlot = preload("res://scripts/data/player_slot.gd")

var seats: Array = []
var host_peer_id: int = 0
var rng_seed: int = 0
var mode: String = "quick_clash"
var rules: Dictionary = {}

func to_dict() -> Dictionary:
	var seat_dicts: Array = []
	for s in seats:
		seat_dicts.append(s.to_dict())
	return {
		"seats": seat_dicts,
		"host_peer_id": host_peer_id,
		"rng_seed": rng_seed,
		"mode": mode,
		"rules": rules,
	}

static func from_dict(d: Dictionary) -> RefCounted:
	var m = load("res://scripts/data/match_start.gd").new()
	var raw_seats: Array = d.get("seats", [])
	m.seats = []
	for seat_dict in raw_seats:
		m.seats.append(PlayerSlot.from_dict(seat_dict))
	m.host_peer_id = d.get("host_peer_id", 0)
	m.rng_seed = d.get("rng_seed", 0)
	m.mode = d.get("mode", "quick_clash")
	m.rules = d.get("rules", {})
	return m
