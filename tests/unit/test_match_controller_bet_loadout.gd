extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")
const MockEvent = preload("res://tests/fakes/mock_event.gd")

func _build_match_start(player_count: int) -> RefCounted:
	var ms = MatchStart.new()
	for i in player_count:
		var s = PlayerSlot.new()
		s.peer_id = i + 1; s.seat_index = i; s.name = "P%d" % (i + 1)
		ms.seats.append(s)
	ms.host_peer_id = 1; ms.rng_seed = 1
	return ms

func _new_synchronous_controller() -> MatchController:
	var c = MatchController.new(true, null)
	c.no_op_phase_delay_ms_override = 0
	c.bet_loadout_timeout_sec_override = 0.0
	var mock = MockEvent.new()
	c._event_factory = func(_path): return mock
	c.start_match(_build_match_start(2))
	return c

func test_bet_loadout_emits_started_signal():
	var c = _new_synchronous_controller()
	add_child_autofree(c)
	# GDScript 4.x lambdas capture bool/primitive by value; use a container array.
	var started_payload: Array = []
	c.bet_loadout_started.connect(func(active, max_per): started_payload.append([active, max_per]))
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c._enter_phase_behavior()
	await get_tree().process_frame
	assert_eq(started_payload.size(), 1, "bet_loadout_started fired once")
	assert_eq(started_payload[0][0].size(), 2, "two active peers")

func test_bet_loadout_clears_pending_wagers_on_entry():
	var c = _new_synchronous_controller()
	add_child_autofree(c)
	c.state.pending_wagers = {1: 500}  # leftover
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c._enter_phase_behavior()
	await get_tree().process_frame
	# After bet_loadout_started, pending_wagers should be cleared so this
	# phase starts fresh
	assert_eq(c.state.pending_wagers, {})

func test_bet_loadout_fast_advances_when_all_ready():
	var c = _new_synchronous_controller()
	c.bet_loadout_timeout_sec_override = 60.0  # slow timer
	add_child_autofree(c)
	# GDScript 4.x lambdas capture bool/primitive by value; use a container array.
	var finished = [false]
	c.bet_loadout_finished.connect(func(): finished[0] = true)
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c._enter_phase_behavior()
	await get_tree().process_frame
	# Submit wagers for both active peers
	c._rpc_set_wager(1, 100)
	c._rpc_set_wager(2, 100)
	# Give the polling loop a frame to detect "all ready"
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(finished[0], "phase should advance once all active peers submit")

func test_bet_loadout_advances_on_timeout_with_missing_wagers():
	var c = _new_synchronous_controller()
	c.bet_loadout_timeout_sec_override = 0.05  # 50ms
	add_child_autofree(c)
	# GDScript 4.x lambdas capture bool/primitive by value; use a container array.
	var finished = [false]
	c.bet_loadout_finished.connect(func(): finished[0] = true)
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c._enter_phase_behavior()
	await get_tree().create_timer(0.2).timeout
	assert_true(finished[0], "timer expired -> bet_loadout_finished fired")
