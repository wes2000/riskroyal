extends GutTest

# Alpha remediation Phase F (Change 8 §12.3): table-driven verification
# of the twist subtitle copy. Spec pins these strings as literal output.

const HouseTwistOverlay = preload("res://scripts/ui/house_twist_overlay.gd")

func test_double_bounty_subtitle():
	var s = HouseTwistOverlay.format_twist_subtitle({"type": "double_bounty"}, "")
	assert_eq(s, "Bounties doubled. Make it personal.")

func test_no_insurance_subtitle():
	var s = HouseTwistOverlay.format_twist_subtitle({"type": "no_insurance"}, "")
	assert_eq(s, "No Insurance. Greed has no helmet.")

func test_leader_cursed_subtitle_with_name():
	var twist = {"type": "leader_cursed", "params": {"target_peer_id": 2}}
	var s = HouseTwistOverlay.format_twist_subtitle(twist, "Maya")
	assert_eq(s, "Leader Cursed. Maya's next reward is cut.")

func test_leader_cursed_subtitle_without_name_omits_second_sentence():
	var twist = {"type": "leader_cursed", "params": {"target_peer_id": 0}}
	var s = HouseTwistOverlay.format_twist_subtitle(twist, "")
	assert_eq(s, "Leader Cursed.",
		"empty target_name falls back to the title sentence only")

func test_power_surge_subtitle():
	var s = HouseTwistOverlay.format_twist_subtitle({"type": "power_surge"}, "")
	assert_eq(s, "Power Surge. Everyone gets a fresh trick.")

func test_lowest_chips_picks_subtitle_with_name():
	var twist = {"type": "lowest_chips_picks", "params": {"target_peer_id": 2}}
	var s = HouseTwistOverlay.format_twist_subtitle(twist, "Maya")
	assert_eq(s, "Underdog's Choice. Maya picks the next table.")

func test_lowest_chips_picks_subtitle_without_name_omits_second_sentence():
	var twist = {"type": "lowest_chips_picks", "params": {"target_peer_id": 0}}
	var s = HouseTwistOverlay.format_twist_subtitle(twist, "")
	assert_eq(s, "Underdog's Choice.")

func test_sudden_death_jackpot_subtitle():
	var s = HouseTwistOverlay.format_twist_subtitle({"type": "sudden_death_jackpot"}, "")
	assert_eq(s, "Bonus Crown live. Take the dangerous route.")

func test_unknown_twist_returns_empty():
	assert_eq(HouseTwistOverlay.format_twist_subtitle({"type": ""}, ""), "")
	assert_eq(HouseTwistOverlay.format_twist_subtitle({}, ""), "")
