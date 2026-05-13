extends GutTest

const ShopController = preload("res://scripts/match/shop_controller.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _new_state(player_count: int) -> RefCounted:
	var s = MatchState.new()
	for i in player_count:
		var p = MatchPlayer.new()
		p.peer_id = i + 1; p.chips = 500; p.is_active_this_event = true
		s.players.append(p)
	return s

func test_open_populates_offer():
	var s = _new_state(2)
	ShopController.open(s)
	assert_eq(s.current_shop_offer.size(), 3)
	assert_eq(s.shop_done_peers, [])

func test_close_clears_state():
	var s = _new_state(2)
	s.current_shop_offer = ["insurance", "heat_shield", "multiplier_booster"]
	s.shop_done_peers = [1, 2]
	ShopController.close(s)
	assert_eq(s.current_shop_offer, [])
	assert_eq(s.shop_done_peers, [])

func test_validate_buy_returns_ok():
	var s = _new_state(2)
	s.current_shop_offer = ["insurance"]
	var v = ShopController.validate_buy(s, 1, "insurance")
	assert_eq(v.get("status", ""), "ok")
	assert_eq(v.get("cost", -1), 50)

func test_validate_buy_card_not_in_offer():
	var s = _new_state(2)
	s.current_shop_offer = ["insurance"]
	var v = ShopController.validate_buy(s, 1, "heat_shield")
	assert_eq(v.get("status", ""), "not_in_offer")

func test_validate_buy_insufficient_chips():
	var s = _new_state(2)
	s.current_shop_offer = ["multiplier_booster"]
	s.players[0].chips = 100
	var v = ShopController.validate_buy(s, 1, "multiplier_booster")
	assert_eq(v.get("status", ""), "insufficient_chips")

func test_validate_buy_hand_full():
	var s = _new_state(2)
	s.current_shop_offer = ["insurance"]
	s.players[0].hand = ["a", "b", "c", "d", "e"]
	var v = ShopController.validate_buy(s, 1, "insurance")
	assert_eq(v.get("status", ""), "hand_full")

func test_apply_buy_mutates_state():
	var s = _new_state(2)
	s.current_shop_offer = ["insurance"]
	ShopController.apply_buy(s, 1, "insurance", 50)
	assert_eq(s.players[0].chips, 450)
	assert_true("insurance" in s.players[0].hand)
	assert_true(1 in s.shop_done_peers)
