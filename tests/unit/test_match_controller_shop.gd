extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")
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

func _new_host_with_fake() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.shop_timeout_sec_override = 0.0
	c.start_match(_build_match_start(2))
	return {"controller": c, "fake": fake}

func test_shop_entry_offers_3_cards():
	var d = _new_host_with_fake()
	var c = d.controller
	add_child_autofree(c)
	c.state.phase = MatchPhase.Phase.SHOP
	c._process_shop()
	await get_tree().process_frame
	assert_eq(c.state.current_shop_offer.size(), MatchConfig.SHOP_OFFER_SIZE)

func test_shop_emits_opened_signal():
	var d = _new_host_with_fake()
	var c = d.controller
	add_child_autofree(c)
	var opened_payload: Array = []
	c.shop_opened.connect(func(offered): opened_payload.append(offered))
	c.state.phase = MatchPhase.Phase.SHOP
	c._process_shop()
	await get_tree().process_frame
	assert_eq(opened_payload.size(), 1)
	assert_eq(opened_payload[0].size(), MatchConfig.SHOP_OFFER_SIZE)

func test_buy_valid_card_deducts_chips_and_adds_to_hand():
	var d = _new_host_with_fake()
	var c = d.controller
	add_child_autofree(c)
	c.state.phase = MatchPhase.Phase.SHOP
	c.state.current_shop_offer = ["insurance", "heat_shield", "multiplier_booster"]
	var p1_chips_before = c.state.players[0].chips
	c._rpc_shop_buy_requested(1, "insurance")
	assert_eq(c.state.players[0].chips, p1_chips_before - 50, "Insurance costs 50")
	assert_true("insurance" in c.state.players[0].hand)

func test_buy_insufficient_chips_rejected():
	var d = _new_host_with_fake()
	var c = d.controller
	add_child_autofree(c)
	c.state.phase = MatchPhase.Phase.SHOP
	c.state.current_shop_offer = ["multiplier_booster"]
	c.state.players[0].chips = 100
	var hand_before = c.state.players[0].hand.size()
	c._rpc_shop_buy_requested(1, "multiplier_booster")
	assert_eq(c.state.players[0].hand.size(), hand_before, "buy rejected; hand unchanged")

func test_buy_card_not_in_offer_rejected():
	var d = _new_host_with_fake()
	var c = d.controller
	add_child_autofree(c)
	c.state.phase = MatchPhase.Phase.SHOP
	c.state.current_shop_offer = ["insurance"]
	c.state.players[0].hand = []
	c._rpc_shop_buy_requested(1, "heat_shield")
	assert_false("heat_shield" in c.state.players[0].hand)

func test_buy_hand_full_rejected():
	var d = _new_host_with_fake()
	var c = d.controller
	add_child_autofree(c)
	c.state.phase = MatchPhase.Phase.SHOP
	c.state.current_shop_offer = ["insurance"]
	c.state.players[0].hand = ["c1", "c2", "c3", "c4", "c5"]
	c._rpc_shop_buy_requested(1, "insurance")
	assert_eq(c.state.players[0].hand.size(), 5, "hand full; no buy")
	assert_false("insurance" in c.state.players[0].hand)

func test_buy_twice_per_visit_rejected():
	var d = _new_host_with_fake()
	var c = d.controller
	add_child_autofree(c)
	c.state.phase = MatchPhase.Phase.SHOP
	c.state.current_shop_offer = ["insurance", "heat_shield"]
	c.state.players[0].hand = []
	c._rpc_shop_buy_requested(1, "insurance")
	c._rpc_shop_buy_requested(1, "heat_shield")
	assert_true("insurance" in c.state.players[0].hand)
	assert_false("heat_shield" in c.state.players[0].hand, "second buy rejected")

func test_submit_done_marks_peer_done():
	var d = _new_host_with_fake()
	var c = d.controller
	add_child_autofree(c)
	c.state.phase = MatchPhase.Phase.SHOP
	c._rpc_shop_done(1)
	assert_true(1 in c.state.shop_done_peers)
