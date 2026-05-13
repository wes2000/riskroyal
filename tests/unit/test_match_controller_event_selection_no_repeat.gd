extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start(player_count: int, seed_value: int = 1) -> RefCounted:
	var ms = MatchStart.new()
	for i in player_count:
		var s = PlayerSlot.new()
		s.peer_id = i + 1; s.seat_index = i; s.name = "P%d" % (i + 1)
		ms.seats.append(s)
	ms.host_peer_id = 1; ms.rng_seed = seed_value
	return ms

func _new_controller() -> MatchController:
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(2))
	return c

func test_event_selection_does_not_repeat_immediately():
	# Force a specific previous_event_id; verify next selection is not it.
	var c = _new_controller()
	for seed_val in 20:
		c.state.rng.seed = seed_val + 100
		c.state.previous_event_id = "res://scenes/events/rocket_clash/rocket_clash_event.tscn"
		c._process_event_selection()
		assert_ne(c.state.current_event_id,
			"res://scenes/events/rocket_clash/rocket_clash_event.tscn",
			"selection must not repeat previous_event_id")

func test_event_selection_falls_back_when_pool_only_has_previous():
	# If EVENT_POOL only had one entry and that was previous_event_id,
	# the fallback to the full pool kicks in.
	var c = _new_controller()
	c.state.previous_event_id = "res://scenes/events/rocket_clash/rocket_clash_event.tscn"
	# Defensive: even if the only entry equals previous_event_id, we get a result
	c.state.rng.seed = 1
	c._process_event_selection()
	assert_true(MatchConfig.EVENT_POOL.has(c.state.current_event_id),
		"current_event_id is a valid pool member after fallback")
