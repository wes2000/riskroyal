extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")
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

func test_start_match_resets_house_twist_fields():
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	# Pause the phase machine so _schedule_advance doesn't auto-advance past
	# HOUSE_REVEAL before we can inspect state — otherwise EVENT_SELECTION
	# would re-populate previous_event_id.
	c.pause()
	# Pre-poison the controller's state as if a prior match left these set
	c.state.house_twist = {"type": "double_bounty", "params": {}}
	c.state.last_twist_type = "double_bounty"
	c.state.previous_event_id = "res://scenes/events/rocket_clash/rocket_clash_event.tscn"
	c.start_match(_build_match_start(2))
	assert_eq(c.state.house_twist, {}, "house_twist reset to empty")
	assert_eq(c.state.last_twist_type, "", "last_twist_type reset to empty string")
	assert_eq(c.state.previous_event_id, "", "previous_event_id reset to empty string")
