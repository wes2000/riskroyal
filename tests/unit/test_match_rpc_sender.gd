extends GutTest

const MatchRpcSender = preload("res://scripts/match/match_rpc_sender.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func test_send_records_broadcast():
	var fake = FakeMultiplayerNode.new()
	var sender = MatchRpcSender.new(fake)
	sender.send("test_method", [1, "hello"])
	assert_eq(fake.rpc_calls.size(), 1)
	assert_eq(fake.rpc_calls[0].method, "test_method")
	assert_eq(fake.rpc_calls[0].args, [1, "hello"])

func test_send_to_peer_records_targeted():
	var fake = FakeMultiplayerNode.new()
	var sender = MatchRpcSender.new(fake)
	sender.send_to_peer(42, "targeted_method", ["payload"])
	assert_eq(fake.rpc_calls.size(), 1)
	assert_eq(fake.rpc_calls[0].method, "targeted_method")
	assert_eq(fake.rpc_calls[0].peer_id, 42)

func test_send_null_node_noops():
	var sender = MatchRpcSender.new(null)
	sender.send("test_method", [])  # should not crash
	sender.send_to_peer(1, "test_method", [])
	assert_true(true)

func test_send_arity_4_pushes_error():
	# Sender supports up to 3 args; 4+ is push_error. We verify by
	# checking no fake.rpc_calls entry was recorded.
	var fake = FakeMultiplayerNode.new()
	var sender = MatchRpcSender.new(fake)
	sender.send("test_method", [1, 2, 3, 4])
	assert_eq(fake.rpc_calls.size(), 0, "4-arg overflow drops the call")
