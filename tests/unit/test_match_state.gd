extends GutTest

const MatchState = preload("res://scripts/match/match_state.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")

func test_defaults():
	var s = MatchState.new()
	assert_eq(s.event_index, 0)
	assert_eq(s.phase, MatchPhase.Phase.HOUSE_REVEAL)
	assert_eq(s.players.size(), 0)
	assert_eq(s.current_event_id, "")
	assert_null(s.current_result)
	assert_eq(s.rng_seed, 0)

func test_seed_rng_seeds_random_number_generator():
	var s = MatchState.new()
	s.rng_seed = 0xDEADBEEF
	s.seed_rng()
	assert_not_null(s.rng)
	var first = s.rng.randi()
	var s2 = MatchState.new()
	s2.rng_seed = 0xDEADBEEF
	s2.seed_rng()
	assert_eq(s2.rng.randi(), first, "same seed should produce same sequence")

func test_find_player_returns_match_player():
	var s = MatchState.new()
	var p = MatchPlayer.new()
	p.peer_id = 2
	s.players = [p]
	assert_eq(s.find_player(2), p)
	assert_null(s.find_player(99))

func test_round_trip_includes_players():
	var s = MatchState.new()
	s.event_index = 2
	s.phase = MatchPhase.Phase.RESOLUTION
	s.rng_seed = 0xABCD
	var p = MatchPlayer.new()
	p.peer_id = 1; p.name = "Host"; p.chips = 500
	s.players = [p]
	var d = s.to_dict()
	var s2 = MatchState.from_dict(d)
	assert_eq(s2.event_index, 2)
	assert_eq(s2.phase, MatchPhase.Phase.RESOLUTION)
	assert_eq(s2.rng_seed, 0xABCD)
	assert_eq(s2.players.size(), 1)
	assert_eq(s2.players[0].chips, 500)
