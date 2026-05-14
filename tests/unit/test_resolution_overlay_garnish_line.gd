extends GutTest

# Alpha remediation Phase G S2 (Pillar #7: Comebacks require risk, not
# charity). The debt-garnish resolution step renders one line per
# garnished player so the painful-reveal shows the House taking its cut
# instead of silently shrinking the chip_delta.
#
# format_resolution_step is static; it cannot resolve names from
# controller state. Tests pin the static "P<id>" output. Name-resolved
# rendering happens at the instance dispatch path (covered by overlay
# integration tests elsewhere).

const ResolutionOverlay = preload("res://scripts/ui/resolution_overlay.gd")

func test_garnish_line_single_player():
	var s = ResolutionOverlay.format_resolution_step("debt_garnish", {
		"garnishes": [{"peer_id": 1, "garnish": 40}],
	})
	assert_eq(s, "House garnished 40 chips from P1's winnings.")

func test_garnish_line_multiple_players():
	var s = ResolutionOverlay.format_resolution_step("debt_garnish", {
		"garnishes": [
			{"peer_id": 1, "garnish": 40},
			{"peer_id": 2, "garnish": 25},
		],
	})
	assert_eq(s,
		"House garnished 40 chips from P1's winnings.\n" +
		"House garnished 25 chips from P2's winnings.")

func test_garnish_line_empty_returns_empty_string():
	var s = ResolutionOverlay.format_resolution_step("debt_garnish", {
		"garnishes": [],
	})
	assert_eq(s, "")

func test_garnish_line_missing_garnishes_key_returns_empty():
	# Defensive: missing key behaves like empty array.
	var s = ResolutionOverlay.format_resolution_step("debt_garnish", {})
	assert_eq(s, "")
