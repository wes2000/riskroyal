extends GutTest

const MatchState = preload("res://scripts/match/match_state.gd")

func test_bounties_defaults_empty():
	var s = MatchState.new()
	assert_eq(s.bounties, [])

func test_current_shop_offer_defaults_empty():
	var s = MatchState.new()
	assert_eq(s.current_shop_offer, [])

func test_shop_done_peers_defaults_empty():
	var s = MatchState.new()
	assert_eq(s.shop_done_peers, [])

func test_event_modifiers_defaults_empty_dict():
	var s = MatchState.new()
	assert_eq(s.event_modifiers, {})

func test_pending_card_effects_defaults_empty():
	var s = MatchState.new()
	assert_eq(s.pending_card_effects, [])

func test_round_trip_preserves_new_fields():
	var s = MatchState.new()
	s.bounties = [{"origin": "leader", "target": 1}]  # Bounty.to_dict shape (Task 4 produces real Bounty)
	s.current_shop_offer = ["insurance", "heat_shield"]
	s.shop_done_peers = [1, 2]
	s.event_modifiers = {1: {"insurance_pre": true}}
	s.pending_card_effects = [{"type": "wager_tax", "source": 1, "target": 2}]
	var d = s.to_dict()
	var s2 = MatchState.from_dict(d)
	assert_eq(s2.bounties.size(), 1)
	# After round-trip, bounties are reconstructed as Bounty instances
	# (not raw dicts), so use property access instead of .get().
	assert_eq(s2.bounties[0].origin, "leader")
	assert_eq(s2.current_shop_offer, ["insurance", "heat_shield"])
	assert_eq(s2.shop_done_peers, [1, 2])
	assert_eq(s2.event_modifiers.get(1, {}).get("insurance_pre", false), true)
	assert_eq(s2.pending_card_effects.size(), 1)
	assert_eq(s2.pending_card_effects[0].get("type", ""), "wager_tax")
	assert_eq(s2.pending_card_effects[0].get("source", 0), 1)
	assert_eq(s2.pending_card_effects[0].get("target", 0), 2)

func test_round_trip_bounty_instances_reconstructed():
	var Bounty = load("res://scripts/match/bounty.gd")
	var b = Bounty.new()
	b.origin = "leader"
	b.target = 5
	b.condition = "bust"
	b.reward_chips = 200
	b.placed_at_target_heat = 3
	var s = MatchState.new()
	s.bounties = [b]
	var d = s.to_dict()
	var s2 = MatchState.from_dict(d)
	assert_eq(s2.bounties.size(), 1)
	# Bounty instance properties accessible (not raw dict)
	assert_eq(s2.bounties[0].origin, "leader")
	assert_eq(s2.bounties[0].target, 5)
	assert_eq(s2.bounties[0].reward_chips, 200)
	assert_eq(s2.bounties[0].placed_at_target_heat, 3)
