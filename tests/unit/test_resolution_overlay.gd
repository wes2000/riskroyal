extends GutTest

const ResolutionOverlay = preload("res://scripts/ui/resolution_overlay.gd")

func test_format_busts_with_peer_ids():
	var s = ResolutionOverlay.format_resolution_step("busts", {"bust_peer_ids": [2, 3]})
	assert_true(s.contains("Busts"))
	assert_true(s.contains("2"))
	assert_true(s.contains("3"))

func test_format_busts_with_no_busts():
	var s = ResolutionOverlay.format_resolution_step("busts", {"bust_peer_ids": []})
	assert_true(s.contains("No busts"))

func test_format_cash_outs():
	var s = ResolutionOverlay.format_resolution_step("cash_outs", {"cash_outs": {1: 2.5, 2: 0.0}})
	assert_true(s.contains("Cash-outs"))
	assert_true(s.contains("2.5x") or s.contains("2.5"))

func test_format_chip_changes():
	var s = ResolutionOverlay.format_resolution_step("chip_changes", {"deltas": [{"peer_id": 1, "delta": 100}, {"peer_id": 2, "delta": -50}]})
	assert_true(s.contains("Chips"))
	assert_true(s.contains("+100"))
	assert_true(s.contains("-50"))

func test_format_crown_awards():
	var s = ResolutionOverlay.format_resolution_step("crown_awards", {"deltas": [{"peer_id": 2, "delta": 1}]})
	assert_true(s.contains("Crown"))

func test_format_painful_reveal_with_winner():
	var s = ResolutionOverlay.format_resolution_step("painful_reveal", {"winner_peer_id": 2, "winner_name": "Maya"})
	assert_true(s.contains("Maya"))

func test_format_unknown_step_returns_step_name():
	var s = ResolutionOverlay.format_resolution_step("custom_step", {})
	assert_true(s.contains("custom_step"))
