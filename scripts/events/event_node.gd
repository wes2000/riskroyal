# Base class for all events. Subclasses override _run and get_event_id and
# emit event_complete exactly once per run.
#
# Contract documented in spec section 6.3 and section 11.
extends Node

signal event_complete(result)
signal event_progress(payload: Dictionary)

# Subclasses override.
func _run(_context) -> void:
	push_error("EventNode._run must be overridden")

func get_event_id() -> String:
	return "base"
