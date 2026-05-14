# Base class for all events. Subclasses override _run and get_event_id and
# emit event_complete exactly once per run.
#
# Contract documented in spec section 6.3 and section 11.
extends Node

signal event_complete(result)
signal event_progress(payload: Dictionary)

# Sub-project #6 Plan A Task 3: hoisted from RC/BP/CC for M2 harmonization.
# Subclasses set _multiplayer_node directly (test injection) or call
# super._run(context) which self-wires when in-tree.
var _multiplayer_node = null

func _run(context) -> void:
	# Default self-wire; subclasses MUST call super._run(context) at the
	# top of their override to inherit this.
	if _multiplayer_node == null and is_inside_tree():
		_multiplayer_node = self

func _send_rpc(method_name: String, args: Array = []) -> void:
	if _multiplayer_node == null:
		return
	var callable = Callable(_multiplayer_node, "rpc")
	var combined = [method_name]
	for a in args:
		combined.append(a)
	callable.callv(combined)

func _send_rpc_to_peer(peer_id: int, method_name: String, args: Array = []) -> void:
	if _multiplayer_node == null:
		return
	var callable = Callable(_multiplayer_node, "rpc_id")
	var combined = [peer_id, method_name]
	for a in args:
		combined.append(a)
	callable.callv(combined)

func _send_rpc_to_host(host_peer_id: int, method_name: String, args: Array = []) -> void:
	_send_rpc_to_peer(host_peer_id, method_name, args)

func get_event_id() -> String:
	return "base"
