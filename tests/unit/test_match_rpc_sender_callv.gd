extends GutTest

const MatchRpcSender = preload("res://scripts/match/match_rpc_sender.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func test_send_4_args_passes_through_to_rpc():
	var fake = FakeMultiplayerNode.new()
	var sender = MatchRpcSender.new(fake)
	sender.send("_rpc_foo", ["a", "b", "c", "d"])
	assert_eq(fake.rpc_calls.size(), 1, "exactly 1 rpc call recorded")
	var call = fake.rpc_calls[0]
	assert_eq(String(call.method), "_rpc_foo")
	assert_eq(call.args, ["a", "b", "c", "d"],
		"4-arg send must pass all 4 args through (was silently push_error'd before)")

func test_send_to_peer_5_args_passes_through_to_rpc_id():
	var fake = FakeMultiplayerNode.new()
	var sender = MatchRpcSender.new(fake)
	sender.send_to_peer(2, "_rpc_bar", [1, 2, 3, 4, 5])
	assert_eq(fake.rpc_calls.size(), 1)
	var call = fake.rpc_calls[0]
	assert_eq(String(call.method), "_rpc_bar")
	assert_eq(int(call.peer_id), 2)
	assert_eq(call.args, [1, 2, 3, 4, 5],
		"5-arg send_to_peer must pass all 5 args through")
