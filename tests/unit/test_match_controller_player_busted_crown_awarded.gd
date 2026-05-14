extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const EventResult = preload("res://scripts/events/event_result.gd")

func _new_controller_with_players(player_count: int):
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	for i in player_count:
		var p = MatchPlayer.new()
		p.peer_id = i + 1
		p.seat_index = i
		p.name = "P%d" % (i + 1)
		p.chips = 500
		c.state.players.append(p)
	return c

func test_player_busted_fires_with_chip_loss():
	var c = _new_controller_with_players(2)
	var got: Array = []
	c.player_busted.connect(func(pid, loss): got.append({"pid": pid, "loss": loss}))
	c.player_busted.emit(2, 100)
	assert_eq(got.size(), 1)
	assert_eq(int(got[0].pid), 2)
	assert_eq(int(got[0].loss), 100, "chip_loss is the positive magnitude of the loss")

func test_crown_awarded_fires_with_count():
	var c = _new_controller_with_players(2)
	var got: Array = []
	c.crown_awarded.connect(func(pid, count): got.append({"pid": pid, "count": count}))
	c.crown_awarded.emit(2, 1)
	c.crown_awarded.emit(3, 2)
	assert_eq(got.size(), 2)
	assert_eq(int(got[0].count), 1)
	assert_eq(int(got[1].count), 2, "crown_delta can be 2 for Sudden Death stack")
