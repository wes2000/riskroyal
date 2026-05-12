extends GutTest

const MatchEndOverlay = preload("res://scripts/ui/match_end_overlay.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(name: String, crowns: int, chips: int, heat: int) -> RefCounted:
	var p = MatchPlayer.new()
	p.name = name; p.crowns = crowns; p.chips = chips; p.heat = heat
	return p

func test_format_rankings_lists_in_order():
	var rankings = [
		_make_player("Alice", 3, 700, 2),
		_make_player("Bob", 2, 800, 1),
		_make_player("Carol", 0, 500, 5),
	]
	var s = MatchEndOverlay.format_match_end_rankings(rankings)
	var alice_pos = s.find("Alice")
	var bob_pos = s.find("Bob")
	var carol_pos = s.find("Carol")
	assert_true(alice_pos < bob_pos, "Alice listed before Bob")
	assert_true(bob_pos < carol_pos, "Bob listed before Carol")

func test_format_rankings_shows_winner_first_line():
	var rankings = [_make_player("Alice", 5, 800, 0)]
	var s = MatchEndOverlay.format_match_end_rankings(rankings)
	assert_true(s.contains("Alice"))
	assert_true(s.contains("Winner"))

func test_format_rankings_shows_crowns_chips_heat():
	var rankings = [_make_player("Alice", 3, 750, 2)]
	var s = MatchEndOverlay.format_match_end_rankings(rankings)
	assert_true(s.contains("3"))
	assert_true(s.contains("750"))
	assert_true(s.contains("2"))

func test_format_rankings_handles_empty_list():
	var s = MatchEndOverlay.format_match_end_rankings([])
	assert_true(s.contains("No rankings"))
