extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
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
