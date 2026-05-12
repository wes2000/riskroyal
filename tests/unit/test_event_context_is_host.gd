extends GutTest

const EventContext = preload("res://scripts/events/event_context.gd")

func test_is_host_default_false():
	var ctx = EventContext.new()
	assert_false(ctx.is_host)

func test_is_host_round_trip():
	var ctx = EventContext.new()
	ctx.is_host = true
	ctx.event_index = 2
	ctx.rng_seed = 0xCAFE
	var d = ctx.to_dict()
	var ctx2 = EventContext.from_dict(d)
	assert_true(ctx2.is_host)
	assert_eq(ctx2.event_index, 2)
	assert_eq(ctx2.rng_seed, 0xCAFE)
