extends GutTest

const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")

func test_run_populates_ctx_tuning_with_defaults():
	var e = Node.new()
	e.set_script(RocketClashEvent)
	var ctx = EventContext.new()
	ctx.rng_seed = 1
	e._run(ctx)
	assert_true(ctx.tuning.has("growth_rate"))
	assert_almost_eq(float(ctx.tuning.get("growth_rate", 0.0)), MatchConfig.ROCKET_GROWTH_RATE, 0.001)
	assert_true(ctx.tuning.has("instabust_prob"))
	assert_almost_eq(float(ctx.tuning.get("instabust_prob", 0.0)), RocketClashEvent.INSTABUST_PROB, 0.001)
	assert_true(ctx.tuning.has("max_crash_at"))
	assert_almost_eq(float(ctx.tuning.get("max_crash_at", 0.0)), RocketClashEvent.MAX_CRASH_AT, 0.001)
	e.free()
