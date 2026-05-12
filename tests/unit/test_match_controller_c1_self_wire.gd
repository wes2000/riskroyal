extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
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

func test_detached_controller_does_not_self_wire():
	var c = MatchController.new(true, null)
	# Detached — start_match should NOT self-wire because is_inside_tree() is false.
	c.start_match(_build_match_start(2))
	assert_eq(c._multiplayer_node, null, "detached: _multiplayer_node stays null")

func test_in_tree_controller_self_wires_when_null():
	var c = MatchController.new(true, null)
	c.no_op_phase_delay_ms_override = 0
	add_child_autofree(c)
	# In-tree with null injection — start_match should self-wire.
	c.start_match(_build_match_start(2))
	assert_eq(c._multiplayer_node, c, "in-tree: _multiplayer_node self-wires to controller")

func test_explicit_injection_is_preserved():
	var fake_node = Node.new()
	add_child_autofree(fake_node)
	var c = MatchController.new(true, fake_node)
	c.no_op_phase_delay_ms_override = 0
	add_child_autofree(c)
	c.start_match(_build_match_start(2))
	assert_eq(c._multiplayer_node, fake_node, "explicit injection wins over self-wire")
