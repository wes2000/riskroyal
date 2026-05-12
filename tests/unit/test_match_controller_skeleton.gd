extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")
const MockEvent = preload("res://tests/fakes/mock_event.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")

func _build_match_start(player_count: int) -> RefCounted:
	var ms = MatchStart.new()
	for i in player_count:
		var s = PlayerSlot.new()
		s.peer_id = i + 1
		s.seat_index = i
		s.name = "P%d" % (i + 1)
		s.color_index = i
		s.is_host = (i == 0)
		ms.seats.append(s)
	ms.host_peer_id = 1
	ms.rng_seed = 0xCAFEBABE
	ms.mode = "quick_clash"
	return ms

func test_initial_state():
	var c = MatchController.new(true, null)
	assert_eq(c.state.event_index, 0)
	assert_eq(c.state.phase, MatchPhase.Phase.HOUSE_REVEAL)
	assert_eq(c.state.players.size(), 0)
	assert_true(c.is_host)

func test_start_match_builds_players_from_seats():
	var c = MatchController.new(true, null)
	var mock = MockEvent.new()
	c._event_factory = func(_path): return mock
	c.start_match(_build_match_start(3))
	assert_eq(c.state.players.size(), 3)
	assert_eq(c.state.players[0].peer_id, 1)
	assert_eq(c.state.players[0].name, "P1")
	assert_eq(c.state.players[1].name, "P2")

func test_start_match_initializes_chips_from_player_count():
	# start_match initializes chips then the scheduler cascade immediately runs
	# ANTE (deducting ante[0]=25 per player before blocking at MAIN_EVENT with
	# the mock). Verify the starting value via MatchConfig rather than a
	# hardcoded post-ante value.
	var c = MatchController.new(true, null)
	var mock = MockEvent.new()
	c._event_factory = func(_path): return mock
	c.start_match(_build_match_start(4))
	var starting = MatchConfig.starting_chips_for_player_count(4)
	var ante0 = MatchConfig.ANTE_BY_EVENT_INDEX[0]
	for p in c.state.players:
		assert_eq(p.chips, starting - ante0,
			"4 players: starting %d minus first ante %d" % [starting, ante0])

func test_start_match_initializes_chips_for_two_players():
	var c = MatchController.new(true, null)
	var mock = MockEvent.new()
	c._event_factory = func(_path): return mock
	c.start_match(_build_match_start(2))
	var starting = MatchConfig.starting_chips_for_player_count(2)
	var ante0 = MatchConfig.ANTE_BY_EVENT_INDEX[0]
	for p in c.state.players:
		assert_eq(p.chips, starting - ante0)

func test_start_match_seeds_rng():
	var c = MatchController.new(true, null)
	var mock = MockEvent.new()
	c._event_factory = func(_path): return mock
	c.start_match(_build_match_start(2))
	assert_not_null(c.state.rng)
	assert_eq(c.state.rng_seed, 0xCAFEBABE)

func test_start_match_emits_phase_changed_signal():
	var c = MatchController.new(true, null)
	var mock = MockEvent.new()
	c._event_factory = func(_path): return mock
	var phases: Array = []
	c.phase_changed.connect(func(p): phases.append(p))
	c.start_match(_build_match_start(2))
	assert_true(MatchPhase.Phase.HOUSE_REVEAL in phases)
