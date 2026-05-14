extends GutTest

const ResolutionOverlay = preload("res://scripts/ui/resolution_overlay.gd")

func test_card_cannon_reveal_shows_attack_callout():
	var payload = {
		"winner_peer_id": 1,
		"winner_score": 21,
		"scores_summary": [
			{"peer_id": 1, "name": "Maya", "score": 21, "locked_score": 21, "chip_delta": 300, "busted": false, "wager": 100, "target_peer_id": 2, "attack_delta": 100},
			{"peer_id": 2, "name": "Alex", "score": 18, "locked_score": 18, "chip_delta": 100, "busted": false, "wager": 100, "target_peer_id": 1, "attack_delta": 50},
		],
	}
	var s = ResolutionOverlay.format_painful_reveal_card_cannon(payload)
	assert_string_contains(s, "hit Alex for 100", "Maya's attack on Alex shown")
	assert_string_contains(s, "hit Maya for 50", "Alex's attack on Maya shown")

func test_card_cannon_reveal_omits_attack_for_low_lock():
	# locked <= 10 means no attack — no "hit X for Y" clause.
	var payload = {
		"winner_peer_id": 1,
		"winner_score": 12,
		"scores_summary": [
			{"peer_id": 1, "name": "Maya", "score": 12, "locked_score": 12, "chip_delta": 125, "busted": false, "wager": 100, "target_peer_id": 2, "attack_delta": 25},
			{"peer_id": 2, "name": "Alex", "score": 8, "locked_score": 8, "chip_delta": 80, "busted": false, "wager": 100, "target_peer_id": 0, "attack_delta": 0},
		],
	}
	var s = ResolutionOverlay.format_painful_reveal_card_cannon(payload)
	# Maya's 12-lock hits Alex for 25.
	assert_string_contains(s, "hit Alex for 25")
	# Alex's 8-lock has no attack — reveal should NOT contain a "hit Maya"
	# clause for Alex.
	var alex_line_has_hit = false
	for line in s.split("\n"):
		if "Alex locked 8" in line and "hit" in line:
			alex_line_has_hit = true
			break
	assert_false(alex_line_has_hit, "Alex's no-attack row should not have a hit clause")
