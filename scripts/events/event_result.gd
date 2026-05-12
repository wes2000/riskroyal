# Data returned from an event via event_complete(result). Per-player deltas
# describe the event's economic outcome; painful_reveal is opaque UI payload
# for the ResolutionOverlay (Plan B).
extends RefCounted

var event_id: String = ""
var per_player: Dictionary = {}
var painful_reveal: Dictionary = {}

func chip_delta_for(peer_id: int) -> int:
	var entry = per_player.get(peer_id, null)
	if entry == null:
		return 0
	return int(entry.get("chip_delta", 0))

func crown_delta_for(peer_id: int) -> int:
	var entry = per_player.get(peer_id, null)
	if entry == null:
		return 0
	return int(entry.get("crown_delta", 0))

func heat_delta_for(peer_id: int) -> int:
	var entry = per_player.get(peer_id, null)
	if entry == null:
		return 0
	return int(entry.get("heat_delta", 0))

func bust_for(peer_id: int) -> bool:
	var entry = per_player.get(peer_id, null)
	if entry == null:
		return false
	return bool(entry.get("bust", false))

func to_dict() -> Dictionary:
	return {
		"event_id": event_id,
		"per_player": per_player.duplicate(true),
		"painful_reveal": painful_reveal.duplicate(true),
	}

static func from_dict(d: Dictionary) -> RefCounted:
	var r = load("res://scripts/events/event_result.gd").new()
	r.event_id = d.get("event_id", "")
	r.per_player = d.get("per_player", {}).duplicate(true)
	r.painful_reveal = d.get("painful_reveal", {}).duplicate(true)
	return r
