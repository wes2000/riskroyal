# Data passed into an event's _run(context) method. Built by MatchController
# from the active players, the current event index, a derived per-event seed,
# and the wager dictionary (MVP: flat ante per active player).
extends RefCounted

const MatchPlayer = preload("res://scripts/match/match_player.gd")

var players: Array = []
var event_index: int = 0
var rng_seed: int = 0
var wagers: Dictionary = {}

func to_dict() -> Dictionary:
	var player_dicts: Array = []
	for p in players:
		player_dicts.append(p.to_dict())
	return {
		"players": player_dicts,
		"event_index": event_index,
		"rng_seed": rng_seed,
		"wagers": wagers,
	}

static func from_dict(d: Dictionary) -> RefCounted:
	var c = load("res://scripts/events/event_context.gd").new()
	c.event_index = d.get("event_index", 0)
	c.rng_seed = d.get("rng_seed", 0)
	c.wagers = d.get("wagers", {})
	c.players = []
	for raw in d.get("players", []):
		c.players.append(MatchPlayer.from_dict(raw))
	return c
