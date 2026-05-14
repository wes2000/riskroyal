extends GutTest

# Alpha remediation Phase F (Change 7 §11.3): resolution overlay surfaces
# visual tags for the four modifier cards so spectators can see why a
# resolution diverged from the "naked" event math.
#
# Spec doesn't pin the literal copy; these tests pin the chosen wording
# so future copy edits land deliberately rather than silently.

const ResolutionOverlay = preload("res://scripts/ui/resolution_overlay.gd")

func test_insurance_note():
	var note = ResolutionOverlay.format_modifier_note("insurance", {
		"target_name": "Maya",
		"refund_amount": 50,
	})
	assert_eq(note, "Insurance saved Maya 50 chips")

func test_wager_tax_note():
	var note = ResolutionOverlay.format_modifier_note("wager_tax", {
		"source_name": "Jordan",
		"target_name": "Maya",
		"tax_amount": 40,
	})
	assert_eq(note, "Wager Tax: Maya lost 40 chips to Jordan")

func test_multiplier_booster_note():
	var note = ResolutionOverlay.format_modifier_note("multiplier_booster", {
		"target_name": "Maya",
		"multiplier": 1.25,
	})
	assert_eq(note, "Maya's multiplier boosted (+25%)")

func test_cash_out_jammer_note():
	var note = ResolutionOverlay.format_modifier_note("cash_out_jammer", {
		"source_name": "Jordan",
		"target_name": "Maya",
		"delay_ms": 750,
	})
	assert_eq(note, "Cash-out delayed: Jordan held Maya for 750ms")

func test_unknown_card_returns_empty():
	# Cards that aren't one of the 4 modifier cards must return "" so the
	# overlay can skip rendering them. Spec only covers Insurance, Wager
	# Tax, Multiplier Booster, Cash-Out Jammer.
	for card_id in ["heat_spike", "place_bounty", "double_or_nothing",
			"underdog_odds", "late_cash", "heat_shield",
			"emergency_eject", "copycat_bet"]:
		assert_eq(ResolutionOverlay.format_modifier_note(card_id, {}), "",
			"%s is not a modifier-note card" % card_id)

func test_multiplier_booster_handles_non_integer_pct():
	# 1.5x → +50%. Confirms the pct formatter rounds + casts cleanly.
	var note = ResolutionOverlay.format_modifier_note("multiplier_booster", {
		"target_name": "Sam",
		"multiplier": 1.5,
	})
	assert_eq(note, "Sam's multiplier boosted (+50%)")

func test_insurance_suppressed_when_no_refund():
	# Insurance refund_amount lands on effect_result only when the player
	# busted. No-bust path keeps the note suppressed so the overlay doesn't
	# render "Insurance saved Maya 0 chips".
	assert_true(ResolutionOverlay.should_suppress_modifier_note("insurance", {
		"target_name": "Maya",
		"refund_amount": 0,
	}))

func test_insurance_not_suppressed_when_refund_present():
	assert_false(ResolutionOverlay.should_suppress_modifier_note("insurance", {
		"target_name": "Maya",
		"refund_amount": 30,
	}))

func test_wager_tax_suppressed_when_no_tax():
	# Wager Tax tax_amount lands only when the target had positive winnings.
	# Target-busted or 0-delta path keeps the note suppressed.
	assert_true(ResolutionOverlay.should_suppress_modifier_note("wager_tax", {
		"source_name": "Jordan",
		"target_name": "Maya",
		"tax_amount": 0,
	}))

func test_wager_tax_not_suppressed_when_tax_present():
	assert_false(ResolutionOverlay.should_suppress_modifier_note("wager_tax", {
		"source_name": "Jordan",
		"target_name": "Maya",
		"tax_amount": 40,
	}))

func test_multiplier_booster_not_suppressed_with_any_payload():
	# Multiplier Booster effect is known at card-play time; never suppress.
	assert_false(ResolutionOverlay.should_suppress_modifier_note("multiplier_booster", {
		"target_name": "Maya",
		"multiplier": 1.25,
	}))

func test_cash_out_jammer_not_suppressed_with_any_payload():
	# Cash-Out Jammer delay_ms is known at card-play time; never suppress.
	assert_false(ResolutionOverlay.should_suppress_modifier_note("cash_out_jammer", {
		"source_name": "Jordan",
		"target_name": "Maya",
		"delay_ms": 750,
	}))
