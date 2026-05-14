extends GutTest

const Bounty = preload("res://scripts/match/bounty.gd")

func test_default_claim_mode_is_survivors():
	var b = Bounty.new()
	assert_eq(b.claim_mode, "survivors", "default = legacy split behavior")

func test_default_event_id_empty():
	var b = Bounty.new()
	assert_eq(b.event_id, "", "default event_id allows any event")

func test_default_condition_params_empty_dict():
	var b = Bounty.new()
	assert_eq(b.condition_params, {})

func test_to_dict_round_trip_preserves_new_fields():
	var b = Bounty.new()
	b.origin = "placed"
	b.target = 2
	b.condition = "bust"
	b.reward_chips = 200
	b.claim_mode = "placer"
	b.event_id = "rocket_clash"
	b.condition_params = {"min_cash_out": 5.0}
	b.placed_by = 3
	var d = b.to_dict()
	var b2 = Bounty.from_dict(d)
	assert_eq(b2.claim_mode, "placer")
	assert_eq(b2.event_id, "rocket_clash")
	assert_almost_eq(float(b2.condition_params.get("min_cash_out", 0.0)), 5.0, 0.001)
	assert_eq(int(b2.placed_by), 3)

func test_from_dict_legacy_payload_defaults_to_survivors():
	# Old bounty payloads (no claim_mode key) must still deserialize
	# with the legacy public-split semantics.
	var legacy = {
		"origin": "leader",
		"target": 1,
		"condition": "bust",
		"reward_chips": 150,
		"placed_by": 0,
		"placed_at_event": 1,
		"placed_at_target_heat": 0,
	}
	var b = Bounty.from_dict(legacy)
	assert_eq(b.claim_mode, "survivors")
	assert_eq(b.event_id, "")
	assert_eq(b.condition_params, {})
