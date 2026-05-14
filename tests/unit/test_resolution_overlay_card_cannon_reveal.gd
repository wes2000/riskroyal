extends GutTest

const ResolutionOverlay = preload("res://scripts/ui/resolution_overlay.gd")

func test_card_cannon_reveal_perfect_21():
	var payload = {
		"winner_peer_id": 2,
		"winner_score": 21,
		"scores_summary": [
			{"peer_id": 2, "name": "Maya", "score": 21, "locked_score": 21, "chip_delta": 200, "busted": false, "wager": 100},
			{"peer_id": 1, "name": "Alex", "score": 17, "locked_score": 17, "chip_delta": 150, "busted": false, "wager": 100},
		],
	}
	var s = ResolutionOverlay.format_painful_reveal_card_cannon(payload)
	assert_string_contains(s, "CANNONS", "headline mentions CANNONS")
	assert_string_contains(s, "Maya", "winner named")
	assert_string_contains(s, "21", "winner score in headline")
	assert_string_contains(s, "Alex", "other locker named")

func test_card_cannon_reveal_with_bust():
	# Standard case with a bust.
	var payload = {
		"winner_peer_id": 1,
		"winner_score": 20,
		"scores_summary": [
			{"peer_id": 1, "name": "Maya", "score": 20, "locked_score": 20, "chip_delta": 200, "busted": false, "wager": 100},
			{"peer_id": 2, "name": "Alex", "score": 17, "locked_score": 17, "chip_delta": 150, "busted": false, "wager": 100},
			{"peer_id": 3, "name": "Jordan", "score": 24, "locked_score": 0, "chip_delta": -100, "busted": true, "wager": 100},
		],
	}
	var s = ResolutionOverlay.format_painful_reveal_card_cannon(payload)
	assert_string_contains(s, "Maya wins with 20", "winner + score")
	assert_string_contains(s, "Jordan", "busted player named")
	assert_string_contains(s, "24", "bust score shown")

func test_card_cannon_reveal_no_winner():
	# All busted (degenerate).
	var payload = {
		"winner_peer_id": 0,
		"winner_score": 0,
		"scores_summary": [
			{"peer_id": 1, "name": "Alex", "score": 25, "locked_score": 0, "chip_delta": -100, "busted": true, "wager": 100},
			{"peer_id": 2, "name": "Maya", "score": 24, "locked_score": 0, "chip_delta": -100, "busted": true, "wager": 100},
		],
	}
	var s = ResolutionOverlay.format_painful_reveal_card_cannon(payload)
	assert_string_contains(s, "CANNONS", "non-empty fallback")
	assert_string_contains(s, "Alex", "busted players still named")
	assert_string_contains(s, "Maya")
