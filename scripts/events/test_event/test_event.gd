# Stub event used by sub-project #2 to verify the EventNode contract and let
# the match loop run 5 events back-to-back without depending on real game
# logic. Awards 1 Crown and +1 Heat to a deterministic winner.
extends "res://scripts/events/event_node.gd"

const EventResult = preload("res://scripts/events/event_result.gd")

var auto_complete_ms: int = 0  # if > 0, completes after this delay via timer

func get_event_id() -> String:
	return "test_event"

func _run(context) -> void:
	if auto_complete_ms > 0:
		await get_tree().create_timer(auto_complete_ms / 1000.0).timeout
	var result = _compute_result(context)
	event_complete.emit(result)

func _compute_result(context):
	var rng = RandomNumberGenerator.new()
	rng.seed = context.rng_seed
	var n = context.players.size()
	var result = EventResult.new()
	result.event_id = get_event_id()
	if n == 0:
		return result
	var winner_index = rng.randi() % n
	var winner = context.players[winner_index]
	for p in context.players:
		var entry = {"chip_delta": 0, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 0.0}
		if p.peer_id == winner.peer_id:
			entry["crown_delta"] = 1
			entry["heat_delta"] = 1
		result.per_player[p.peer_id] = entry
	result.painful_reveal = {"winner_peer_id": winner.peer_id, "winner_name": winner.name}
	return result
