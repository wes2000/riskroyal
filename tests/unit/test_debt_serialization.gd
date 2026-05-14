extends GutTest

# Alpha feel remediation Phase E §10.3: MatchPlayer.debt field must
# round-trip through to_dict() / from_dict() with a default of 0 and
# correct propagation of non-zero values.

const MatchPlayer = preload("res://scripts/match/match_player.gd")

func test_debt_defaults_to_zero():
	var p = MatchPlayer.new()
	assert_eq(p.debt, 0, "debt defaults to 0")

func test_debt_round_trips_default():
	var p = MatchPlayer.new()
	p.peer_id = 7
	var d = p.to_dict()
	assert_true(d.has("debt"), "to_dict() must include 'debt' key")
	assert_eq(int(d["debt"]), 0, "default debt serializes to 0")
	var p2 = MatchPlayer.from_dict(d)
	assert_eq(p2.debt, 0, "from_dict() round-trips default debt 0")

func test_debt_round_trips_non_zero():
	var p = MatchPlayer.new()
	p.peer_id = 7
	p.debt = 150
	var d = p.to_dict()
	assert_eq(int(d["debt"]), 150, "non-zero debt serializes")
	var p2 = MatchPlayer.from_dict(d)
	assert_eq(p2.debt, 150, "from_dict() round-trips non-zero debt")

func test_from_dict_missing_debt_defaults_to_zero():
	# Backwards-compat: dicts produced before Phase E must still load
	# cleanly with debt defaulting to 0.
	var d = {"peer_id": 3, "chips": 500}
	var p = MatchPlayer.from_dict(d)
	assert_eq(p.debt, 0, "missing 'debt' key defaults to 0")
