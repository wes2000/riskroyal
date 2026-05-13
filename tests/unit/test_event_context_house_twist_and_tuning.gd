extends GutTest

const EventContext = preload("res://scripts/events/event_context.gd")

func test_house_twist_defaults_empty_dict():
	var ctx = EventContext.new()
	assert_eq(ctx.house_twist, {})

func test_tuning_defaults_empty_dict():
	var ctx = EventContext.new()
	assert_eq(ctx.tuning, {})

func test_round_trip_preserves_house_twist_and_tuning():
	var ctx = EventContext.new()
	ctx.house_twist = {"type": "leader_cursed", "params": {"leader_peer_id": 3, "reward_multiplier": 0.75}}
	ctx.tuning = {"growth_rate": 0.18, "instabust_prob": 0.05}
	var d = ctx.to_dict()
	var ctx2 = EventContext.from_dict(d)
	assert_eq(ctx2.house_twist.get("type", ""), "leader_cursed")
	assert_eq(ctx2.house_twist.get("params", {}).get("leader_peer_id", 0), 3)
	assert_almost_eq(float(ctx2.tuning.get("growth_rate", 0.0)), 0.18, 0.001)
