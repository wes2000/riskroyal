extends GutTest

const PlaceholderMatch = preload("res://scripts/ui/placeholder_match.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start():
	var ms = MatchStart.new()
	var s1 = PlayerSlot.new()
	s1.peer_id = 1; s1.is_host = true; s1.seat_index = 0; s1.name = "Host"; s1.color_index = 2
	var s2 = PlayerSlot.new()
	s2.peer_id = 2; s2.seat_index = 1; s2.name = "Maya"; s2.color_index = 5
	ms.seats = [s1, s2]
	ms.host_peer_id = 1
	ms.rng_seed = 0xCAFEBABE
	ms.mode = "quick_clash"
	return ms

func test_format_match_start_contains_seat_count():
	var ms = _build_match_start()
	var text = PlaceholderMatch.format_match_start(ms)
	assert_true("2 player" in text, "expected mention of player count, got: %s" % text)

func test_format_match_start_contains_seed_in_hex():
	var ms = _build_match_start()
	var text = PlaceholderMatch.format_match_start(ms)
	assert_true("cafebabe" in text.to_lower() or "CAFEBABE" in text, "expected seed in hex, got: %s" % text)

func test_format_match_start_lists_all_seat_names():
	var ms = _build_match_start()
	var text = PlaceholderMatch.format_match_start(ms)
	assert_true("Host" in text)
	assert_true("Maya" in text)

func test_format_match_start_contains_mode():
	var ms = _build_match_start()
	var text = PlaceholderMatch.format_match_start(ms)
	assert_true("quick_clash" in text)
