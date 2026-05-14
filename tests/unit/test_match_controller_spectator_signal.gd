extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _new_controller_with_local_peer(local_pid: int):
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	# Force the local peer id for the test seam.
	c._local_peer_id_override = local_pid
	for i in 2:
		var p = MatchPlayer.new()
		p.peer_id = i + 1
		p.seat_index = i
		p.name = "P%d" % (i + 1)
		p.chips = 500
		p.is_active_this_event = true
		c.state.players.append(p)
	return c

func test_local_player_spectator_mode_entered_emits_busted_reason():
	var c = _new_controller_with_local_peer(1)
	var got: Array = []
	c.local_player_spectator_mode_entered.connect(func(r): got.append(r))
	# Call the new helper that evaluates + emits when local player busts.
	c.notify_local_spectator_if_busted(1)
	assert_eq(got.size(), 1)
	assert_eq(String(got[0]), "busted")

func test_local_player_spectator_mode_entered_skips_remote_peer_bust():
	var c = _new_controller_with_local_peer(1)
	var got: Array = []
	c.local_player_spectator_mode_entered.connect(func(r): got.append(r))
	# A remote peer (peer_id=2) busts — local peer is still active, so
	# the signal must NOT fire on this controller instance.
	c.notify_local_spectator_if_busted(2)
	assert_eq(got.size(), 0, "remote bust doesn't emit on a non-affected peer")
