extends RefCounted

var peer_id: int = 0
var name: String = ""
var color_index: int = -1
var ready: bool = false
var is_host: bool = false
var connected: bool = true
var seat_index: int = -1
var reconnect_token: String = ""

func to_dict() -> Dictionary:
	return {
		"peer_id": peer_id,
		"name": name,
		"color_index": color_index,
		"ready": ready,
		"is_host": is_host,
		"connected": connected,
		"seat_index": seat_index,
		"reconnect_token": reconnect_token,
	}

static func from_dict(d: Dictionary) -> RefCounted:
	var s = load("res://scripts/data/player_slot.gd").new()
	s.peer_id = d.get("peer_id", 0)
	s.name = d.get("name", "")
	s.color_index = d.get("color_index", -1)
	s.ready = d.get("ready", false)
	s.is_host = d.get("is_host", false)
	s.connected = d.get("connected", true)
	s.seat_index = d.get("seat_index", -1)
	s.reconnect_token = d.get("reconnect_token", "")
	return s
