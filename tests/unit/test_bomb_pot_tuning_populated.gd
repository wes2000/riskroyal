extends GutTest

const BombPotEvent = preload("res://scripts/events/bomb_pot/bomb_pot_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")

func test_run_populates_ctx_tuning_with_defaults():
	var e = Node.new()
	e.set_script(BombPotEvent)
	var ctx = EventContext.new()
	ctx.rng_seed = 1
	e._run(ctx)
	assert_almost_eq(float(ctx.tuning.get("pot_growth_per_sec", 0.0)), MatchConfig.BOMB_POT_POT_GROWTH_PER_SEC, 0.001)
	assert_almost_eq(float(ctx.tuning.get("min_detonation_sec", 0.0)), MatchConfig.BOMB_POT_MIN_DETONATION_SEC, 0.001)
	assert_almost_eq(float(ctx.tuning.get("max_detonation_sec", 0.0)), MatchConfig.BOMB_POT_MAX_DETONATION_SEC, 0.001)
	assert_almost_eq(float(ctx.tuning.get("instabust_prob", 0.0)), MatchConfig.BOMB_POT_INSTABUST_PROB, 0.001)
	e.free()
