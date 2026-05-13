extends GutTest

const CashOutCardDrawer = preload("res://scripts/ui/cash_out_card_drawer.gd")

func test_filter_loadout_returns_cash_out_only():
	# cash_out_jammer is cash_out timing; insurance is bet_loadout
	var loadout = ["cash_out_jammer", "insurance"]
	var played: Array = []
	var filtered = CashOutCardDrawer.filter_loadout(loadout, played)
	assert_eq(filtered, ["cash_out_jammer"])

func test_filter_loadout_excludes_played():
	var loadout = ["cash_out_jammer"]
	var played = ["cash_out_jammer"]
	var filtered = CashOutCardDrawer.filter_loadout(loadout, played)
	assert_eq(filtered, [])

func test_filter_loadout_handles_unknown_card():
	var loadout = ["cash_out_jammer", "nonexistent"]
	var played: Array = []
	var filtered = CashOutCardDrawer.filter_loadout(loadout, played)
	assert_eq(filtered, ["cash_out_jammer"], "unknown cards excluded")
