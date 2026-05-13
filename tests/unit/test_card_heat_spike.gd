extends GutTest

const HeatSpike = preload("res://scripts/cards/effects/heat_spike.gd")

func test_heat_spike_meta():
	var m = HeatSpike.CARD_META
	assert_eq(m.name, "Heat Spike")
	assert_eq(m.rarity, "common")
	assert_eq(m.category, "sabotage")
	assert_eq(m.timing, "bet_loadout")
	assert_eq(m.target_required, true)
	assert_eq(m.cost_chips, 50)

func test_apply_returns_post_event_heat_delta():
	var result = HeatSpike.apply(null, 5, null)
	assert_true(result.applied)
	assert_eq(result.type, "post_event_heat_delta")
	# Effect carries the target peer_id + delta for the dispatcher to queue.
	assert_eq(result.target, 5)
	assert_eq(result.delta, 2)
