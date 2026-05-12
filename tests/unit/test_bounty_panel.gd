extends GutTest

const BountyPanel = preload("res://scripts/ui/bounty_panel.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(peer_id: int, name: String, heat: int = 0) -> RefCounted:
	var p = MatchPlayer.new()
	p.peer_id = peer_id; p.name = name; p.heat = heat
	return p

func test_format_bounty_summary_leader():
	var bounty_dict = {
		"origin": "leader", "target": 2, "condition": "bust",
		"reward_chips": 150, "placed_at_target_heat": 0,
	}
	var target = _make_player(2, "Maya")
	var s = BountyPanel.format_bounty_summary(bounty_dict, target)
	assert_true(s.contains("Maya"))
	assert_true(s.contains("Leader"))
	assert_true(s.contains("150"))

func test_format_bounty_summary_heat_scaled():
	var bounty_dict = {
		"origin": "heat", "target": 2, "condition": "bust",
		"reward_chips": 150, "placed_at_target_heat": 7,
	}
	var target = _make_player(2, "Maya", 7)
	var s = BountyPanel.format_bounty_summary(bounty_dict, target)
	# Should include heat-scaled reward (150 * 1.5 = 225 at heat 7)
	assert_true(s.contains("225") or s.contains("1.5"))
