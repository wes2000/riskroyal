extends GutTest

const PlayerSelectors = preload("res://scripts/match/player_selectors.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _new_state(chips_array: Array, seat_indices: Array = []) -> RefCounted:
	var s = MatchState.new()
	for i in chips_array.size():
		var p = MatchPlayer.new()
		p.peer_id = i + 1
		p.seat_index = seat_indices[i] if i < seat_indices.size() else i
		p.chips = chips_array[i]
		s.players.append(p)
	return s

func test_find_max_returns_highest_chips_peer():
	var s = _new_state([300, 700, 500])  # P2 wins
	assert_eq(PlayerSelectors.find_chips_extremum(s, "max", false), 2)

func test_find_max_with_tie_break_picks_lowest_seat_index():
	# P1 and P3 tied at 700; P1 has seat_index 0, P3 has seat_index 2 -> P1 wins
	var s = _new_state([700, 300, 700], [0, 1, 2])
	assert_eq(PlayerSelectors.find_chips_extremum(s, "max", true), 1,
		"tie-break picks lowest seat_index (P1 over P3)")

func test_find_min_with_tie_break_picks_lowest_seat_index():
	# P1 and P3 tied at 300; P1 has seat_index 0 -> P1 wins
	var s = _new_state([300, 700, 300], [0, 1, 2])
	assert_eq(PlayerSelectors.find_chips_extremum(s, "min", true), 1,
		"min direction with tie-break picks lowest seat_index")

func test_empty_state_returns_zero():
	var s = MatchState.new()  # players is []
	assert_eq(PlayerSelectors.find_chips_extremum(s, "max", true), 0)
	assert_eq(PlayerSelectors.find_chips_extremum(s, "min", true), 0)

func test_single_player_returns_that_peer():
	var s = _new_state([500])
	assert_eq(PlayerSelectors.find_chips_extremum(s, "max", true), 1)
	assert_eq(PlayerSelectors.find_chips_extremum(s, "min", true), 1)
