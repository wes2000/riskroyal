extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const EventNode = preload("res://scripts/events/event_node.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func test_status_changed_signal_exists_and_carries_peer_id_and_string():
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	var got: Array = []
	c.status_changed.connect(func(pid, s): got.append({"pid": pid, "s": s}))
	c.status_changed.emit(2, "CASHED")
	assert_eq(got.size(), 1)
	assert_eq(int(got[0].pid), 2)
	assert_eq(String(got[0].s), "CASHED")

func test_rpc_status_changed_reemits_local_signal():
	# Receiver path: when _rpc_status_changed fires (via the network), the
	# controller re-emits status_changed so widgets subscribed locally see it.
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(false, fake)
	var got: Array = []
	c.status_changed.connect(func(pid, s): got.append({"pid": pid, "s": s}))
	c._rpc_status_changed(3, "BUSTED")
	assert_eq(got.size(), 1)
	assert_eq(int(got[0].pid), 3)
	assert_eq(String(got[0].s), "BUSTED")

func test_emit_status_changed_routes_through_controller():
	# C1 fixup production-path test: an EventNode calls _emit_status_changed;
	# the controller's signal must fire locally on the host AND a broadcast
	# RPC named _rpc_status_changed must be recorded. The bug being guarded
	# against was routing _rpc_status_changed via the event's own
	# _multiplayer_node (the event itself), which has no such @rpc method;
	# StatusGrid would receive zero updates in production.
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	var ctx = EventContext.new()
	ctx.is_host = true
	ctx.controller = c
	var node = EventNode.new()
	var got: Array = []
	c.status_changed.connect(func(pid, s): got.append({"pid": pid, "s": s}))
	fake.rpc_calls.clear()
	node._emit_status_changed(ctx, 2, "CASHED")
	assert_eq(got.size(), 1, "host's local signal fired")
	assert_eq(int(got[0].pid), 2)
	assert_eq(String(got[0].s), "CASHED")
	var found = false
	for call in fake.rpc_calls:
		if String(call.get("method", "")) == "_rpc_status_changed":
			found = true
			break
	assert_true(found, "_rpc_status_changed broadcast recorded via controller")
	node.free()
