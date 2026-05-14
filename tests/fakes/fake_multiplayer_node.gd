# Records rpc(...) calls for sender-side tests. Each call is appended to
# rpc_calls as {method, args}. MatchController's _send_rpc helper invokes
# fake.rpc("method_name", arg1, arg2, ...) — we capture the method name
# and all positional arguments.
#
# Sub-project #7 Plan A Task 10: rpc / rpc_id accept up to 6 positional
# args (was 4) to support the callv-based MatchRpcSender that no longer
# caps at 3. If a future RPC needs more, extend the slots.
extends RefCounted

var rpc_calls: Array = []

func rpc(method: StringName, p1=null, p2=null, p3=null, p4=null, p5=null, p6=null) -> int:
	var args: Array = []
	if p1 != null: args.append(p1)
	if p2 != null: args.append(p2)
	if p3 != null: args.append(p3)
	if p4 != null: args.append(p4)
	if p5 != null: args.append(p5)
	if p6 != null: args.append(p6)
	rpc_calls.append({"method": String(method), "args": args})
	return OK

func rpc_id(peer_id: int, method: StringName, p1=null, p2=null, p3=null, p4=null, p5=null, p6=null) -> int:
	var args: Array = []
	if p1 != null: args.append(p1)
	if p2 != null: args.append(p2)
	if p3 != null: args.append(p3)
	if p4 != null: args.append(p4)
	if p5 != null: args.append(p5)
	if p6 != null: args.append(p6)
	rpc_calls.append({"method": String(method), "peer_id": peer_id, "args": args})
	return OK
