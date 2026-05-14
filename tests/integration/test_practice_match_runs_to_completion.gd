# Integration test: Practice Mode end-to-end. Spins up a MatchController in
# host mode with no live network (FakeMultiplayerNode swallows RPCs) and
# attaches one BotController to every seat — including the human peer at
# peer_id=1 so the match self-drives. Drives a 5-event Quick Clash to
# completion via real BotController Timer nodes and asserts match_ended
# fires with rankings.size() == 3.
#
# Wall-clock cost is real (~30-90s). The natural BotController cash-out /
# pull-out delays and the Rocket Clash / Bomb Pot / Card Cannon event
# timing are NOT compressed; we only zero out the artificial inter-phase /
# resolution-step pacing. This means the test exercises the real timing
# logic the bots are calibrated against.
#
# Unlike the WebRTC integration tests, this test has no signaling-server
# dependency — practice mode is fully local — so it always runs to
# completion when invoked. Lives under tests/integration/ rather than
# tests/unit/ because of the wall-clock cost.
#
# IMPORTANT: MatchController's default event factory only INSTANTIATES the
# event node; in production MatchScene reparents it into the event slot,
# which is what puts it inside the SceneTree so `_process` and Timer-based
# event timing can tick. With no MatchScene above us, the test overrides
# `_event_factory` to add each event node as a child of the controller so
# event-internal timing fires.
extends GutTest

const PracticeSession = preload("res://scripts/net/practice_session.gd")
const MatchController = preload("res://scripts/match/match_controller.gd")
const BotController = preload("res://scripts/match/bot_controller.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

const MATCH_DEADLINE_MS: int = 120_000


func test_practice_match_5_events_to_completion():
	# 2 bot seats → MatchStart has 3 seats total (1 human + 2 bots). The
	# human seat also gets a BotController so the match self-drives without
	# any UI / human input.
	var ms = PracticeSession.build_match_start(2, 42)
	assert_eq(ms.seats.size(), 3, "MatchStart should have 3 seats (1 human + 2 bots)")

	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	add_child_autofree(c)
	# Eliminate the artificial inter-phase / resolution-step pacing. We keep
	# the natural Rocket Clash / Bomb Pot / Card Cannon timers because
	# BotController's decision delays are calibrated against them.
	c.no_op_phase_delay_ms_override = 0
	c.resolution_step_delay_ms_override = 0

	# Inject an event factory that adds the event node as a child of the
	# controller so `_process` and intrinsic event timers fire. In production
	# MatchScene reparents the node into its event slot; the controller
	# itself only instantiates.
	c._event_factory = func(path: String):
		var ps = load(path)
		if ps == null:
			return null
		var node = ps.instantiate()
		c.add_child(node)
		return node

	# Spawn a BotController for every seat, including peer_id=1 (the human).
	# Without a bot on the human seat, BET_LOADOUT hangs forever waiting for
	# a wager submission from peer 1.
	for seat in ms.seats:
		var bc = BotController.new()
		bc.controller = c
		bc.bot_peer_id = seat.peer_id
		bc.match_seed = ms.rng_seed
		add_child_autofree(bc)

	var ended: Array = [false]
	var rankings_out: Array = [[]]
	c.match_ended.connect(func(r):
		ended[0] = true
		rankings_out[0] = r
	)

	c.start_match(ms)

	# Yield to the SceneTree each frame so the BotController + event-node
	# Timer nodes can fire.
	var deadline_ms: int = Time.get_ticks_msec() + MATCH_DEADLINE_MS
	while not ended[0] and Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame

	assert_true(ended[0], "match_ended did not fire within %d ms — match stalled?" % MATCH_DEADLINE_MS)
	assert_eq(rankings_out[0].size(), 3, "rankings should include all 3 peers")
