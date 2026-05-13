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
	var d1 = HouseTwistOverlay.format_twist_description({"type": "double_bounty"})
	assert_true(d1.length() > 0, "double_bounty has description")
	var d2 = HouseTwistOverlay.format_twist_description({"type": "no_insurance"})
	assert_true(d2.length() > 0, "no_insurance has description")
	assert_eq(HouseTwistOverlay.format_twist_description({}), "",
		"empty twist returns empty description")
