extends GutTest

const CashOutJammer = preload("res://scripts/cards/effects/cash_out_jammer.gd")

func test_jammer_meta():
	var m = CashOutJammer.CARD_META
	assert_eq(m.name, "Cash-Out Jammer")
	assert_eq(m.rarity, "rare")
	assert_eq(m.category, "sabotage")
	assert_eq(m.timing, "cash_out")
	assert_eq(m.target_required, true)
	assert_eq(m.cost_chips, 150)

func test_apply_returns_cash_out_delay():
	var result = CashOutJammer.apply(null, 5, {"caller_peer_id": 1})
	assert_true(result.applied)
	assert_eq(result.type, "cash_out_delay")
	assert_eq(result.target, 5)
	assert_eq(result.delay_ms, 750)

func test_apply_no_op_when_self_target():
	var result = CashOutJammer.apply(null, 1, {"caller_peer_id": 1})
	assert_false(result.applied)
