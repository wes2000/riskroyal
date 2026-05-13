extends GutTest

const HouseTwistOverlay = preload("res://scripts/ui/house_twist_overlay.gd")

func test_format_twist_title_per_twist_type():
	assert_eq(HouseTwistOverlay.format_twist_title({"type": "double_bounty"}), "Double Bounty Round")
	assert_eq(HouseTwistOverlay.format_twist_title({"type": "no_insurance"}), "No Insurance")
	assert_eq(HouseTwistOverlay.format_twist_title({"type": "leader_cursed"}), "Leader Cursed")
	assert_eq(HouseTwistOverlay.format_twist_title({"type": "power_surge"}), "Power Surge")
	assert_eq(HouseTwistOverlay.format_twist_title({"type": "lowest_chips_picks"}), "Lowest Chips Picks")
	assert_eq(HouseTwistOverlay.format_twist_title({"type": "sudden_death_jackpot"}), "Sudden Death Jackpot")
	assert_eq(HouseTwistOverlay.format_twist_title({}), "")

func test_format_twist_description_per_twist_type():
	for twist_type in ["double_bounty", "no_insurance", "leader_cursed",
			"power_surge", "lowest_chips_picks", "sudden_death_jackpot"]:
		var desc = HouseTwistOverlay.format_twist_description({"type": twist_type})
		assert_true(desc.length() > 0, "%s has non-empty description" % twist_type)
	assert_eq(HouseTwistOverlay.format_twist_description({}), "",
		"empty twist returns empty description")
