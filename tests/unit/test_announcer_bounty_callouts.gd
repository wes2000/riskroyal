extends GutTest

# Alpha remediation Phase G S1: rivalry-callout announcer lines for bounty
# events. Pillar #5: Bounties create permission to attack friends — the
# announcer should react when bounties are placed and claimed by players.

const Announcer = preload("res://scripts/ui/announcer.gd")

func test_place_bounty_card_callout():
	# Place Bounty fires through the format_card_callout dispatcher (card
	# play). Should produce the spec-pinned rivalry banner.
	var s = Announcer.format_card_callout(
		"place_bounty", "Maya", "Sam", "Place Bounty")
	assert_eq(s, "Maya put a bounty on Sam.")

func test_bounty_claimed_callout():
	var s = Announcer.format_bounty_claimed_text("Jordan", "Maya")
	assert_eq(s, "Jordan claimed their bounty on Maya.")
