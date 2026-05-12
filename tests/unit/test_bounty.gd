extends GutTest

const Bounty = preload("res://scripts/match/bounty.gd")
const EventResult = preload("res://scripts/events/event_result.gd")

func _make_bounty(origin: String, target: int, target_heat: int = 0) -> RefCounted:
	var b = Bounty.new()
	b.origin = origin
	b.target = target
	b.condition = "bust"
	b.reward_chips = 150
	b.placed_by = 0
	b.placed_at_event = 1
	b.placed_at_target_heat = target_heat
	return b

func _make_result_with_bust(target_peer_id: int, claimant_peer_id: int) -> RefCounted:
	var r = EventResult.new()
	r.per_player[target_peer_id] = {"chip_delta": -100, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0}
	r.per_player[claimant_peer_id] = {"chip_delta": 100, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 2.0}
	return r

func test_defaults():
	var b = Bounty.new()
	assert_eq(b.origin, "")
	assert_eq(b.target, 0)
	assert_eq(b.condition, "")
	assert_eq(b.reward_chips, 0)
	assert_eq(b.placed_by, 0)
	assert_eq(b.placed_at_event, 0)
	assert_eq(b.placed_at_target_heat, 0)

func test_round_trip():
	var b = _make_bounty("leader", 1, 4)
	var d = b.to_dict()
	var b2 = Bounty.from_dict(d)
	assert_eq(b2.origin, "leader")
	assert_eq(b2.target, 1)
	assert_eq(b2.condition, "bust")
	assert_eq(b2.placed_at_target_heat, 4)

func test_satisfies_bust_condition_target_busted():
	var b = _make_bounty("leader", 1)
	var r = _make_result_with_bust(1, 2)
	assert_true(Bounty.satisfies(b, r, 2))

func test_satisfies_excludes_self_claim():
	var b = _make_bounty("leader", 1)
	var r = _make_result_with_bust(1, 2)
	assert_false(Bounty.satisfies(b, r, 1), "target cannot claim their own bounty")

func test_satisfies_excludes_busted_claimant():
	var b = _make_bounty("leader", 1)
	var r = EventResult.new()
	r.per_player[1] = {"chip_delta": -100, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0}
	r.per_player[2] = {"chip_delta": -100, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0}
	assert_false(Bounty.satisfies(b, r, 2), "busted claimant cannot claim")

func test_satisfies_target_not_busted():
	var b = _make_bounty("leader", 1)
	var r = EventResult.new()
	r.per_player[1] = {"chip_delta": 200, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 2.0}
	r.per_player[2] = {"chip_delta": 100, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 1.5}
	assert_false(Bounty.satisfies(b, r, 2), "target survived; bounty condition not met")

func test_compute_reward_no_heat_bonus():
	var b = _make_bounty("leader", 1, 0)
	b.reward_chips = 150
	assert_eq(Bounty.compute_reward(b), 150)

func test_compute_reward_heat_band_noticed():
	var b = _make_bounty("heat", 1, 4)
	b.reward_chips = 150
	assert_eq(Bounty.compute_reward(b), 187)

func test_compute_reward_heat_band_hot_seat():
	var b = _make_bounty("heat", 1, 7)
	b.reward_chips = 150
	assert_eq(Bounty.compute_reward(b), 225)

func test_compute_reward_heat_band_public_enemy():
	var b = _make_bounty("heat", 1, 10)
	b.reward_chips = 150
	assert_eq(Bounty.compute_reward(b), 300)

func test_compute_reward_uses_card_registry_heat_multiplier():
	# Single source of truth: Bounty.compute_reward delegates to
	# CardRegistry.heat_multiplier. Verify that calling
	# CardRegistry.heat_multiplier directly with the same heat produces
	# the same scaling factor as compute_reward applies.
	var b = _make_bounty("heat", 1, 7)
	b.reward_chips = 200
	var CardRegistry = load("res://scripts/cards/card_registry.gd")
	var expected = int(200 * CardRegistry.heat_multiplier(7))
	assert_eq(Bounty.compute_reward(b), expected)
