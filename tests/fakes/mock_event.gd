# Synchronous EventNode fake. Tests call emit_complete(result) to drive
# event_complete instead of waiting on real timers / button presses.
extends "res://scripts/events/event_node.gd"

var run_calls: Array = []  # array of contexts
var event_id_value: String = "mock_event"

func get_event_id() -> String:
	return event_id_value

func _run(context) -> void:
	run_calls.append(context)
	# Test drives completion explicitly via emit_complete.

func emit_complete(result) -> void:
	event_complete.emit(result)
