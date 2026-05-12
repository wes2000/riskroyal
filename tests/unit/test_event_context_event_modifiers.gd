extends GutTest

const EventContext = preload("res://scripts/events/event_context.gd")

func test_event_modifiers_defaults_empty():
	var ctx = EventContext.new()
	assert_eq(ctx.event_modifiers, {})

func test_event_modifiers_round_trip():
	var ctx = EventContext.new()
	ctx.event_modifiers = {
		1: {"insurance_pre": true, "wager_multiplier": 1.25},
		2: {"heat_shield": true},
	}
	var d = ctx.to_dict()
	var ctx2 = EventContext.from_dict(d)
	assert_eq(ctx2.event_modifiers.get(1, {}).get("insurance_pre", false), true)
	assert_almost_eq(float(ctx2.event_modifiers.get(1, {}).get("wager_multiplier", 0.0)), 1.25, 0.001)
	assert_eq(ctx2.event_modifiers.get(2, {}).get("heat_shield", false), true)
