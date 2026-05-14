extends GutTest

const ResolutionOverlay = preload("res://scripts/ui/resolution_overlay.gd")

func test_bomb_pot_reveal_with_last_safe_puller():
	# Standard Bomb Pot: one player pulls late and wins, another pulls
	# early, a third busts when the bomb pops.
	var payload = {
		"bomb_at_sec": 14.6,
		"winner_peer_id": 2,
		"winner_pull_out_ms": 13900,
		"pulls_summary": [
			{"peer_id": 2, "name": "Maya", "locked_share": 220, "pull_out_ms": 13900, "chip_delta": 220, "busted": false, "wager": 100},
			{"peer_id": 1, "name": "Alex", "locked_share": 95, "pull_out_ms": 8100, "chip_delta": 95, "busted": false, "wager": 100},
			{"peer_id": 3, "name": "Jordan", "locked_share": 0, "pull_out_ms": 0, "chip_delta": -100, "busted": true, "wager": 100},
		],
	}
	var s = ResolutionOverlay.format_painful_reveal_bomb_pot(payload)
	assert_string_contains(s, "BOMB", "headline mentions BOMB")
	assert_string_contains(s, "14.6", "bomb time in headline")
	assert_string_contains(s, "Maya", "winner named")
	assert_string_contains(s, "13.9", "winner pull time")
	assert_string_contains(s, "Alex", "early puller named")
	assert_string_contains(s, "Jordan", "busted player named")
	assert_string_contains(s, "busted", "bust language present")

func test_bomb_pot_reveal_all_busted():
	# Degenerate case: nobody pulled in time. winner_peer_id == 0.
	var payload = {
		"bomb_at_sec": 8.5,
		"winner_peer_id": 0,
		"winner_pull_out_ms": 0,
		"pulls_summary": [
			{"peer_id": 1, "name": "Alex", "locked_share": 0, "pull_out_ms": 0, "chip_delta": -100, "busted": true, "wager": 100},
			{"peer_id": 2, "name": "Maya", "locked_share": 0, "pull_out_ms": 0, "chip_delta": -100, "busted": true, "wager": 100},
		],
	}
	var s = ResolutionOverlay.format_painful_reveal_bomb_pot(payload)
	assert_string_contains(s, "BOMB", "headline mentions BOMB")
	assert_string_contains(s, "8.5", "bomb time in headline")
	# When no winner, the reveal should still call out the carnage
	assert_string_contains(s, "Alex", "all-bust players named")
	assert_string_contains(s, "Maya")

func test_bomb_pot_reveal_empty_pulls_summary():
	# Degenerate: empty pulls summary (no participants — shouldn't happen
	# in practice but the formatter must not crash).
	var payload = {
		"bomb_at_sec": 10.0,
		"winner_peer_id": 0,
		"winner_pull_out_ms": 0,
		"pulls_summary": [],
	}
	var s = ResolutionOverlay.format_painful_reveal_bomb_pot(payload)
	assert_string_contains(s, "BOMB", "non-empty fallback")
