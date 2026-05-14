extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")
const MockEvent = preload("res://tests/fakes/mock_event.gd")

func _build_match_start(player_count: int) -> RefCounted:
	var ms = MatchStart.new()
	for i in player_count:
		var s = PlayerSlot.new()
		s.peer_id = i + 1
		s.seat_index = i
		s.name = "P%d" % (i + 1)
		ms.seats.append(s)
	ms.host_peer_id = 1
	ms.rng_seed = 1
	return ms

func _new_controller(player_count: int = 2) -> MatchController:
	var c = MatchController.new(true, null)
	# Inject a blocking mock so start_match's cascade stops at MAIN_EVENT
	# without completing the event. Reset chip state after the cascade runs.
	var mock = MockEvent.new()
	c._event_factory = func(_path): return mock
	c.start_match(_build_match_start(player_count))
	# The cascade ran ANTE during start_match; restore initial chip state so
	# ante tests begin from a clean baseline.
	var starting_chips = MatchConfig.starting_chips_for_player_count(player_count)
	for p in c.state.players:
		p.chips = starting_chips
		p.is_active_this_event = true
	c.state.event_index = 0
	return c

func test_ante_deducts_chips_for_event_0():
	var c = _new_controller(2)  # 800 starting chips
	c.state.phase = MatchPhase.Phase.ANTE
	c._enter_phase_behavior()
	var ante = MatchConfig.ANTE_BY_EVENT_INDEX[0]
	for p in c.state.players:
		assert_eq(p.chips, 800 - ante, "ante deducted for event 0")
		assert_true(p.is_active_this_event)

func test_ante_uses_event_index_for_amount():
	var c = _new_controller(2)
	c.state.event_index = 4  # final event, ante 100
	c.state.phase = MatchPhase.Phase.ANTE
	c._enter_phase_behavior()
	var ante = MatchConfig.ANTE_BY_EVENT_INDEX[4]
	for p in c.state.players:
		assert_eq(p.chips, 800 - ante)

func test_ante_player_with_insufficient_chips_sits_out():
	# Alpha feel remediation Phase E §10.3: a broke player now auto-takes
	# a House Loan when debt + 150 <= MAX_DEBT (300). To exercise the
	# original skip path the player must also be locked out of the loan:
	# set their debt high enough that debt + 150 > 300.
	var c = _new_controller(2)
	c.state.event_index = 4  # ante 100
	c.state.players[0].chips = 50  # not enough for ante
	c.state.players[0].debt = 200  # 200 + 150 = 350 > MAX_DEBT 300 -> loan refused
	c.state.phase = MatchPhase.Phase.ANTE
	c._enter_phase_behavior()
	assert_eq(c.state.players[0].chips, 50, "no deduction")
	assert_eq(c.state.players[0].debt, 200, "loan refused, debt unchanged")
	assert_false(c.state.players[0].is_active_this_event)
	assert_eq(c.state.players[1].chips, 800 - 100, "other player paid")
	assert_true(c.state.players[1].is_active_this_event)

func test_ante_emits_player_resources_changed_per_paying_player():
	var c = _new_controller(2)
	c.state.phase = MatchPhase.Phase.ANTE
	var changed: Array = []
	c.player_resources_changed.connect(func(pid): changed.append(pid))
	c._enter_phase_behavior()
	assert_eq(changed.size(), 2, "both players paid -> two emissions")
