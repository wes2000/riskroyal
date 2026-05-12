extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start(player_count: int) -> RefCounted:
	var ms = MatchStart.new()
	for i in player_count:
		var s = PlayerSlot.new()
		s.peer_id = i + 1; s.seat_index = i; s.name = "P%d" % (i + 1)
		ms.seats.append(s)
	ms.host_peer_id = 1; ms.rng_seed = 1
	return ms

func _new_client() -> MatchController:
	var c = MatchController.new(false, null)  # non-host
	for i in 2:
		var p = MatchPlayer.new()
		p.peer_id = i + 1
		p.name = "P%d" % (i + 1)
		p.chips = 800
		c.state.players.append(p)
	return c

func test_rpc_phase_changed_updates_local_state():
	var c = _new_client()
	c._rpc_phase_changed(MatchPhase.Phase.ANTE, {"event_index": 0, "current_event_id": ""})
	assert_eq(c.state.phase, MatchPhase.Phase.ANTE)
	assert_eq(c.state.event_index, 0)

func test_rpc_phase_changed_emits_signal():
	var c = _new_client()
	var phases: Array = []
	c.phase_changed.connect(func(p): phases.append(p))
	c._rpc_phase_changed(MatchPhase.Phase.EVENT_SELECTION, {"event_index": 1, "current_event_id": "x"})
	assert_true(MatchPhase.Phase.EVENT_SELECTION in phases)

func test_rpc_apply_deltas_mutates_chips():
	var c = _new_client()
	c._rpc_apply_deltas([{"peer_id": 1, "chip_delta": -25, "crown_delta": 0, "heat_delta": 0}])
	assert_eq(c.state.players[0].chips, 775)

func test_rpc_apply_deltas_ignores_unknown_peer():
	var c = _new_client()
	c._rpc_apply_deltas([{"peer_id": 99, "chip_delta": -25, "crown_delta": 0, "heat_delta": 0}])
	assert_eq(c.state.players[0].chips, 800)
	assert_eq(c.state.players[1].chips, 800)

func test_rpc_resolution_step_emits_signal():
	var c = _new_client()
	var steps: Array = []
	c.resolution_step.connect(func(name, _payload): steps.append(name))
	c._rpc_resolution_step("painful_reveal", {"winner_peer_id": 1})
	assert_eq(steps, ["painful_reveal"])

func test_rpc_match_ended_emits_signal_with_deserialized_rankings():
	var c = _new_client()
	var rankings_seen = [null]
	c.match_ended.connect(func(r): rankings_seen[0] = r)
	var serialized: Array = [
		{"peer_id": 2, "name": "P2", "chips": 800, "crowns": 1, "heat": 0, "seat_index": 1, "color_index": 1, "is_active_this_event": true},
		{"peer_id": 1, "name": "P1", "chips": 700, "crowns": 0, "heat": 0, "seat_index": 0, "color_index": 0, "is_active_this_event": true},
	]
	c._rpc_match_ended(serialized)
	assert_eq(rankings_seen[0].size(), 2)
	assert_eq(rankings_seen[0][0].peer_id, 2)
