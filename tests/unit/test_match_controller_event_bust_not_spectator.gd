extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const EventResult = preload("res://scripts/events/event_result.gd")

func _new_controller_with_local_peer(local_pid: int):
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
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

func test_local_bust_does_not_emit_spectator_signal():
	# Alpha feel remediation Phase A Change 1 (§5.4): event-local bust must
	# NOT trigger match-long spectator mode.
	var c = _new_controller_with_local_peer(1)
	var spectator_emits: Array = []
	c.local_player_spectator_mode_entered.connect(func(r): spectator_emits.append(r))
	# Build a fake EventResult with player 1 busted.
	var result = EventResult.new()
	result.per_player[1] = {"chip_delta": -100, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0}
	result.per_player[2] = {"chip_delta": 50, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 2.0}
	c._build_busts_payload(result)
	assert_eq(spectator_emits.size(), 0, "event bust must NOT trigger spectator mode")

func test_local_bust_sets_busted_this_event_flag():
	# The busted_this_event flag on MatchPlayer must be set so status chips
	# and overlays can display BUSTED for the current event.
	var c = _new_controller_with_local_peer(1)
	var result = EventResult.new()
	result.per_player[1] = {"chip_delta": -100, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0}
	c._build_busts_payload(result)
	var p1 = c.state.players[0]
	assert_true(p1.busted_this_event, "busted_this_event flag set on the busted player")

func test_player_busted_signal_still_fires_for_announcer_painful_reveal():
	# Plan B's player_busted signal must continue to fire — Announcer +
	# PainfulReveal subscribe to it for the bust UX.
	var c = _new_controller_with_local_peer(1)
	var bust_emits: Array = []
	c.player_busted.connect(func(pid, loss): bust_emits.append({"pid": pid, "loss": loss}))
	var result = EventResult.new()
	result.per_player[1] = {"chip_delta": -100, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0}
	c._build_busts_payload(result)
	assert_eq(bust_emits.size(), 1)
	assert_eq(int(bust_emits[0].pid), 1)
	assert_eq(int(bust_emits[0].loss), 100)
