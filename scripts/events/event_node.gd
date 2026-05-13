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
	match args.size():
		0: _multiplayer_node.rpc(method_name)
		1: _multiplayer_node.rpc(method_name, args[0])
		2: _multiplayer_node.rpc(method_name, args[0], args[1])
		3: _multiplayer_node.rpc(method_name, args[0], args[1], args[2])
		4: _multiplayer_node.rpc(method_name, args[0], args[1], args[2], args[3])
		_:
			push_error("EventNode._send_rpc: unsupported arity %d" % args.size())

func _send_rpc_to_peer(peer_id: int, method_name: String, args: Array = []) -> void:
	if _multiplayer_node == null:
		return
	match args.size():
		0: _multiplayer_node.rpc_id(peer_id, method_name)
		1: _multiplayer_node.rpc_id(peer_id, method_name, args[0])
		2: _multiplayer_node.rpc_id(peer_id, method_name, args[0], args[1])
		_:
			push_error("EventNode._send_rpc_to_peer: unsupported arity %d" % args.size())

func get_event_id() -> String:
	return "base"
