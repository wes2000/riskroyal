extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
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

func test_start_match_deals_starter_pack_size_3():
	var c = MatchController.new(true, null)
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(2))
	for p in c.state.players:
		assert_eq(p.hand.size(), 3, "%s should have 3 starter cards" % p.name)

func test_starter_pack_excludes_sabotage():
	var c = MatchController.new(true, null)
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(2))
	var sabotage_count = 0
	var CardRegistry = load("res://scripts/cards/card_registry.gd")
	for p in c.state.players:
		for card_id in p.hand:
			var card = CardRegistry.get_card(card_id)
			if card.get("category", "") == "sabotage":
				sabotage_count += 1
	assert_eq(sabotage_count, 0, "no sabotage cards in starter pack")

func test_starter_pack_is_deterministic_with_seed():
	var c1 = MatchController.new(true, null)
	c1.no_op_phase_delay_ms_override = 0
	c1.start_match(_build_match_start(2, 0xCAFE))
	var c2 = MatchController.new(true, null)
	c2.no_op_phase_delay_ms_override = 0
	c2.start_match(_build_match_start(2, 0xCAFE))
	assert_eq(c1.state.players[0].hand, c2.state.players[0].hand,
		"same seed -> same starter pack")
