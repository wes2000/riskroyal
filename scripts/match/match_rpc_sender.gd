# Outbound RPC sender. Extracted from MatchController in Plan B Phase 7.
# Wraps the multiplayer_node so MatchController can construct one with
# either `self` (production: routes through the Node's rpc/rpc_id) or
# a FakeMultiplayerNode (tests: records calls in rpc_calls array).
#
# Receivers (@rpc-annotated methods) MUST stay on MatchController because
# Godot's MultiplayerAPI dispatches RPCs by NodePath. This class only
# handles the sender side.
#
# Sub-project #7 Plan A Task 10: arity-cap rewrite via Callable.callv.
# Previously a match args.size() dispatcher capped at 3 args and
# silently push_error'd on 4+. Now passes through any arity via callv.
extends RefCounted

var _multiplayer_node = null

func _init(multiplayer_node) -> void:
	_multiplayer_node = multiplayer_node

# Broadcast to all peers. Routes through _multiplayer_node.rpc with
# Callable.callv for arbitrary arity.
func send(method_name: String, args: Array = []) -> void:
	if _multiplayer_node == null:
		return
	var callable = Callable(_multiplayer_node, "rpc")
	var combined = [method_name]
	for a in args:
		combined.append(a)
	callable.callv(combined)

# Targeted send. Routes through _multiplayer_node.rpc_id with callv.
# Alpha feel remediation Phase A §13.4: guard against sending to an unknown
# peer. In unit tests with no real multiplayer session, calling rpc_id with
# a peer_id that is not in the connected peer list emits "Attempt to call RPC
# with unknown peer ID". Skip the call if the node's multiplayer API does not
# know about that peer. The guard is a no-op when the multiplayer node is a
# FakeMultiplayerNode (doesn't expose .multiplayer) or when the peer list
# contains the target id (production runtime).
func send_to_peer(peer_id: int, method_name: String, args: Array = []) -> void:
	if _multiplayer_node == null:
		return
	# Peer-presence guard: if the multiplayer_node is a real Node (has a
	# .multiplayer property) and that API has peers, only send if peer_id
	# is in the connected peer list. If the API has NO peers at all (offline
	# unit test), skip all targeted sends. FakeMultiplayerNode lacks the
	# .multiplayer property and so skips this guard entirely (it records all
	# calls unconditionally for test inspection).
	if _multiplayer_node is Node:
		var mp = _multiplayer_node.multiplayer
		if mp != null:
			var peers: Array = mp.get_peers()
			if peer_id not in peers:
				return
	var callable = Callable(_multiplayer_node, "rpc_id")
	var combined = [peer_id, method_name]
	for a in args:
		combined.append(a)
	callable.callv(combined)

# Convenience wrapper for the common "client submits to host" pattern.
# Delegates to send_to_peer with the host's peer_id; the @rpc receiver's
# `if not is_host: return` guard remains as defense in depth.
func send_to_host(host_peer_id: int, method_name: String, args: Array = []) -> void:
	send_to_peer(host_peer_id, method_name, args)
