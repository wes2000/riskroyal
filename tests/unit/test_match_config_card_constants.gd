extends GutTest

const MatchConfig = preload("res://scripts/match/match_config.gd")

func test_shop_timeout_sec():
	assert_eq(MatchConfig.SHOP_TIMEOUT_SEC, 10)

func test_max_hand_size():
	assert_eq(MatchConfig.MAX_HAND_SIZE, 5)

func test_max_loadout_size():
	assert_eq(MatchConfig.MAX_LOADOUT_SIZE, 2)

func test_starter_pack_size():
	assert_eq(MatchConfig.STARTER_PACK_SIZE, 3)

func test_shop_offer_size():
	assert_eq(MatchConfig.SHOP_OFFER_SIZE, 3)

func test_card_cost_common():
	assert_eq(MatchConfig.CARD_COST_COMMON, 50)

func test_card_cost_rare():
	assert_eq(MatchConfig.CARD_COST_RARE, 150)

func test_card_cost_royal():
	assert_eq(MatchConfig.CARD_COST_ROYAL, 400)

func test_bounty_base_reward():
	assert_eq(MatchConfig.BOUNTY_BASE_REWARD, 150)
