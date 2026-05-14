extends GutTest

# Alpha remediation Phase F (Change 8 §12.3): announcer twist callouts
# now include the target name where applicable. Existing untargeted
# twists keep the legacy "HOUSE TWIST: <Title>!" form.

const Announcer = preload("res://scripts/ui/announcer.gd")

func test_leader_cursed_includes_target_name():
	var twist = {"type": "leader_cursed", "params": {"target_peer_id": 2}}
	var s = Announcer.format_twist_text(twist, "Maya")
	assert_string_contains(s, "HOUSE TWIST")
	assert_string_contains(s, "Leader Cursed")
	assert_string_contains(s, "Maya")

func test_lowest_chips_picks_includes_target_name():
	var twist = {"type": "lowest_chips_picks", "params": {"target_peer_id": 2}}
	var s = Announcer.format_twist_text(twist, "Maya")
	assert_string_contains(s, "HOUSE TWIST")
	assert_string_contains(s, "Maya")

func test_untargeted_twists_keep_legacy_format():
	for twist_type in ["double_bounty", "no_insurance", "power_surge", "sudden_death_jackpot"]:
		var s = Announcer.format_twist_text({"type": twist_type}, "Maya")
		assert_string_contains(s, "HOUSE TWIST",
			"%s still announces with HOUSE TWIST prefix" % twist_type)
		# Name must NOT appear when twist doesn't have a target.
		assert_false(s.contains("Maya"),
			"%s must not interpolate the unrelated target name" % twist_type)

func test_leader_cursed_without_name_falls_back_to_title_only():
	var twist = {"type": "leader_cursed", "params": {"target_peer_id": 0}}
	var s = Announcer.format_twist_text(twist, "")
	assert_string_contains(s, "Leader Cursed")
	# Should not have a dangling " — 's" fragment when name unknown.
	assert_false(s.contains("'s next"),
		"empty target_name must not produce a partial possessive")

func test_empty_twist_returns_empty():
	assert_eq(Announcer.format_twist_text({"type": ""}, ""), "")
