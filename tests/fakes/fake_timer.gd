# Test double for Godot's Timer node. Synchronous: emit_timeout() fires
# the timeout signal immediately.
extends RefCounted

signal timeout()

var wait_time: float = 0.0
var one_shot: bool = true
var start_calls: int = 0
var stop_calls: int = 0
var running: bool = false

func start(time: float = -1.0) -> void:
	if time > 0.0:
		wait_time = time
	start_calls += 1
	running = true

func stop() -> void:
	stop_calls += 1
	running = false

func emit_timeout() -> void:
	running = false
	timeout.emit()
