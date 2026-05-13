extends GutTest

const CardCannonEvent = preload("res://scripts/events/card_cannon/card_cannon_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")

func test_run_populates_ctx_tuning_with_defaults():
	var e = Node.new()
	e.set_script(CardCannonEvent)
	var ctx = EventContext.new()
	ctx.rng_seed = 1
	e._run(ctx)
	assert_eq(int(ctx.tuning.get("target_score", 0)), MatchConfig.CARD_CANNON_TARGET_SCORE)
	var bands = ctx.tuning.get("payout_bands", {})
	assert_almost_eq(float(bands.get("low", 0.0)), MatchConfig.CARD_CANNON_PAYOUT_BAND_LOW, 0.001)
	assert_almost_eq(float(bands.get("perfect", 0.0)), MatchConfig.CARD_CANNON_PAYOUT_BAND_PERFECT, 0.001)
	e.free()
