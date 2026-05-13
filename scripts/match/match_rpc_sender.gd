# Outbound RPC sender. Extracted from MatchController in Plan B Phase 7.
# Wraps the multiplayer_node so MatchController can construct one with
# either `self` (production: routes through the Node's rpc/rpc_id) or
# a FakeMultiplayerNode (tests: records calls in rpc_calls array).
#
# Receivers (@rpc-annotated methods) MUST stay on MatchController because
# Godot's MultiplayerAPI dispatches RPCs by NodePath. This class only
# handles the sender side.
extends RefCounted

var _multiplayer_node = null

func _init(multiplayer_node) -> void:
	_multiplayer_node = multiplayer_node

# Broadcast to all peers. Routes through _multiplayer_node.rpc.
func send(method_name: String, args: Array = []) -> void:
	if _multiplayer_node == null:
		return
	match args.size():
		0: _multiplayer_node.rpc(method_name)
		1: _multiplayer_node.rpc(method_name, args[0])
		2: _multiplayer_node.rpc(method_name, args[0], args[1])
		3: _multiplayer_node.rpc(method_name, args[0], args[1], args[2])
		_:
			push_error("MatchRpcSender.send: unsupported arity %d" % args.size())

# Targeted send. Routes through _multiplayer_node.rpc_id.
func send_to_peer(peer_id: int, method_name: String, args: Array = []) -> void:
	if _multiplayer_node == null:
		return
	match args.size():
		0: _multiplayer_node.rpc_id(peer_id, method_name)
		1: _multiplayer_node.rpc_id(peer_id, method_name, args[0])
		2: _multiplayer_node.rpc_id(peer_id, method_name, args[0], args[1])
		3: _multiplayer_node.rpc_id(peer_id, method_name, args[0], args[1], args[2])
		_:
			push_error("MatchRpcSender.send_to_peer: unsupported arity %d" % args.size())
