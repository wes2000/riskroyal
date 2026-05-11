extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")

var transport
var signaling
var session

func before_each():
	transport = FakeTransport.new()
	signaling = FakeSignalingClient.new()
	session = NetSession.new(transport, signaling)
	session.host_session()
	signaling.emit_code_issued("ABC234")
	transport.emit_peer_joined(2)
	transport.emit_peer_joined(3)

func _slot(peer_id: int):
	for s in session.players:
		if s.peer_id == peer_id:
			return s
	return null

func test_host_can_set_own_ready():
	var ok = session.receive_set_ready(1, true)
	assert_true(ok)
	assert_true(_slot(1).ready)

func test_set_ready_rejects_unknown_peer():
	var ok = session.receive_set_ready(99, true)
	assert_false(ok)

func test_set_ready_rejects_outside_lobby_state():
	session._set_state(NetSessionState.State.MATCH)
	var ok = session.receive_set_ready(1, true)
	assert_false(ok)

func test_set_color_changes_color():
	var ok = session.receive_set_color(2, 5)
	assert_true(ok)
	assert_eq(_slot(2).color_index, 5)

func test_set_color_rejects_duplicate():
	session.receive_set_color(2, 5)
	var ok = session.receive_set_color(3, 5)
	assert_false(ok)
	assert_eq(_slot(3).color_index, -1)

func test_kick_removes_slot_when_host_calls():
	var ok = session.kick(2)
	assert_true(ok)
	assert_null(_slot(2))

func test_kick_rejects_when_not_host():
	var joiner_session = NetSession.new(FakeTransport.new(), FakeSignalingClient.new())
	joiner_session.join_session("ABC234")
	var ok = joiner_session.kick(2)
	assert_false(ok)

func test_kick_removes_slot():
	# In Plan C, kick will trigger transport.disconnect_peer(peer_id).
	# FakeTransport tracks any such call.
	session.kick(2)
	# For Plan B we just verify the slot is removed and player_changed emits;
	# the transport disconnect side-effect is wired up in Plan C.
	assert_null(_slot(2))

func test_kick_rejects_unknown_peer():
	var before = session.players.size()
	var ok = session.kick(99)
	assert_false(ok)
	assert_eq(session.players.size(), before, "players unchanged on unknown-peer kick")

func test_set_ready_public_wrapper_routes_through_host_validator():
	var ok_before = _slot(1).ready
	session.set_ready(true)
	assert_true(_slot(1).ready)
	# The wrapper should have flipped the host's slot via the simulated RPC path.
	assert_false(ok_before)

func test_set_color_public_wrapper_routes_through_host_validator():
	session.set_color(7)
	assert_eq(_slot(1).color_index, 7)

func test_actions_emit_players_changed():
	# Array (reference type) used because GDScript lambdas do not propagate
	# reassignment of captured value types back to outer scope.
	var emitted = [0]
	session.players_changed.connect(func(): emitted[0] += 1)
	session.receive_set_ready(2, true)
	session.receive_set_color(2, 5)
	session.kick(3)
	assert_eq(emitted[0], 3)
