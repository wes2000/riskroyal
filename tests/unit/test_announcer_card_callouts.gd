extends GutTest

# Alpha remediation Phase F (Change 7 §11.3): public callouts when a
# card is played. The four "flavor" cards have specific spec strings;
# every other card uses the generic "<Player> played <CardName>." form
# off CardRegistry's display name.

const Announcer = preload("res://scripts/ui/announcer.gd")
const CardRegistry = preload("res://scripts/cards/card_registry.gd")

func test_cash_out_jammer_callout():
	var s = Announcer.format_card_callout(
		"cash_out_jammer", "Jordan", "Maya", "Cash-Out Jammer")
	assert_eq(s, "Jordan jammed Maya's cash-out.")

func test_insurance_callout():
	var s = Announcer.format_card_callout(
		"insurance", "Maya", "Maya", "Insurance")
	assert_eq(s, "Maya bought Insurance. Cowardly? Effective.")

func test_copycat_bet_callout():
	var s = Announcer.format_card_callout(
		"copycat_bet", "Alex", "Sam", "Copycat Bet")
	assert_eq(s, "Alex copied Sam's wager.")

func test_heat_spike_callout():
	var s = Announcer.format_card_callout(
		"heat_spike", "Jordan", "Maya", "Heat Spike")
	assert_eq(s, "Jordan spiked Maya's Heat.")

func test_generic_callout_for_other_cards():
	# All non-flavored cards get the generic fallback. Spot-check a few.
	for entry in [
		["wager_tax", "Maya", "Sam", "Wager Tax", "Maya played Wager Tax."],
		["multiplier_booster", "Sam", "", "Multiplier Booster", "Sam played Multiplier Booster."],
		["late_cash", "Alex", "", "Late Cash", "Alex played Late Cash."],
		["double_or_nothing", "Sam", "", "Double or Nothing", "Sam played Double or Nothing."],
		["underdog_odds", "Maya", "", "Underdog Odds", "Maya played Underdog Odds."],
		["place_bounty", "Maya", "Sam", "Place Bounty", "Maya played Place Bounty."],
		["heat_shield", "Sam", "", "Heat Shield", "Sam played Heat Shield."],
		["emergency_eject", "Jordan", "", "Emergency Eject", "Jordan played Emergency Eject."],
	]:
		var got = Announcer.format_card_callout(entry[0], entry[1], entry[2], entry[3])
		assert_eq(got, entry[4],
			"%s should produce generic callout" % entry[0])

func test_generic_callout_uses_card_registry_display_name():
	# Sanity-check the integration path: the live MatchController call
	# resolves display_name via CardRegistry.get_card(card_id).name. Make
	# sure that name is the human-readable form we expect for each card.
	for card_id in ["wager_tax", "multiplier_booster", "late_cash",
			"double_or_nothing", "underdog_odds", "place_bounty",
			"heat_shield", "emergency_eject"]:
		var card = CardRegistry.get_card(card_id)
		assert_false(card.is_empty(), "CardRegistry knows %s" % card_id)
		var name = String(card.get("name", ""))
		assert_ne(name, "", "CardRegistry exposes display name for %s" % card_id)

func test_unknown_card_falls_back_to_card_id():
	# Defensive: if a future card lands without a CARD_META.name, the
	# generic form should still produce some output rather than crash.
	var s = Announcer.format_card_callout("brand_new_card", "Alex", "", "")
	assert_string_contains(s, "Alex")
