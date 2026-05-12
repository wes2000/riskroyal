extends GutTest

const TestEvent = preload("res://scripts/events/test_event/test_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_context(player_count: int, seed_value: int) -> RefCounted:
	var ctx = EventContext.new()
	for i in player_count:
		var p = MatchPlayer.new()
		p.peer_id = i + 1
		p.name = "P%d" % (i + 1)
		ctx.players.append(p)
	ctx.event_index = 0
	ctx.rng_seed = seed_value
	return ctx

func test_get_event_id():
	var e = TestEvent.new()
	assert_eq(e.get_event_id(), "test_event")

func test_run_emits_event_complete():
	var e = TestEvent.new()
	e.auto_complete_ms = 0  # synchronous
	var results: Array = []
	e.event_complete.connect(func(r): results.append(r))
	e._run(_make_context(2, 0xABCD))
	assert_eq(results.size(), 1)

func test_result_is_deterministic_with_seed():
	var e1 = TestEvent.new()
	e1.auto_complete_ms = 0
	var r1: Array = [null]
	e1.event_complete.connect(func(r): r1[0] = r)
	e1._run(_make_context(3, 0xCAFE))

	var e2 = TestEvent.new()
	e2.auto_complete_ms = 0
	var r2: Array = [null]
	e2.event_complete.connect(func(r): r2[0] = r)
	e2._run(_make_context(3, 0xCAFE))

	# Same seed -> same winner.
	var winners1: Array = []
	var winners2: Array = []
	for pid in r1[0].per_player:
		if r1[0].crown_delta_for(pid) > 0:
			winners1.append(pid)
	for pid in r2[0].per_player:
		if r2[0].crown_delta_for(pid) > 0:
			winners2.append(pid)
	assert_eq(winners1, winners2, "same seed should pick same winner")

func test_result_awards_one_crown_to_one_player():
	var e = TestEvent.new()
	e.auto_complete_ms = 0
	var r: Array = [null]
	e.event_complete.connect(func(result): r[0] = result)
	e._run(_make_context(4, 0xFFFF))
	var total_crowns := 0
	for pid in r[0].per_player:
		total_crowns += r[0].crown_delta_for(pid)
	assert_eq(total_crowns, 1, "exactly one player gets a Crown")

func test_painful_reveal_names_winner():
	var e = TestEvent.new()
	e.auto_complete_ms = 0
	var r: Array = [null]
	e.event_complete.connect(func(result): r[0] = result)
	e._run(_make_context(2, 0x1234))
	assert_true(r[0].painful_reveal.has("winner_peer_id"))
