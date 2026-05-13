extends GutTest

const CardCannonEvent = preload("res://scripts/events/card_cannon/card_cannon_event.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func _new_card_cannon_at_main() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var e = Node.new()
	e.set_script(CardCannonEvent)
	e._is_host = true
	e._multiplayer_node = fake
	e._active_peers = [1, 2]
	e._hands = {1: [], 2: []}
	e._scores = {1: 0, 2: 0}
	e._busted = {1: false, 2: false}
	var EventContext = load("res://scripts/events/event_context.gd")
	var ctx = EventContext.new()
	ctx.rng_seed = 1
	e._stashed_context = ctx
	return {"event": e, "fake": fake}

func test_draw_during_main_event_updates_score():
	var d = _new_card_cannon_at_main()
	var e = d.event
	e._force_next_rank_override = 7
	e._rpc_draw_requested(1)
	assert_eq(e._scores[1], 7)
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_card_drawn":
			found = true
			break
	assert_true(found, "_rpc_card_drawn broadcast")
	e.free()

func test_lock_during_main_event_freezes_score():
	var d = _new_card_cannon_at_main()
	var e = d.event
	e._hands[1] = [10, 8]
	e._scores[1] = 18
	e._rpc_lock_requested(1)
	assert_eq(e._locked_scores.get(1, -1), 18)
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_locked":
			found = true
			break
	assert_true(found)
	e.free()

func test_draw_after_lock_rejected():
	var d = _new_card_cannon_at_main()
	var e = d.event
	e._locked_scores[1] = 17
	e._force_next_rank_override = 10
	d.fake.rpc_calls.clear()
	e._rpc_draw_requested(1)
	assert_eq(e._hands.get(1, []), [])
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_card_drawn":
			found = true
			break
	assert_false(found)
	e.free()

func test_draw_after_bust_rejected():
	var d = _new_card_cannon_at_main()
	var e = d.event
	e._busted[1] = true
	e._hands[1] = [10, 10, 5]
	e._scores[1] = 25
	e._force_next_rank_override = 5
	d.fake.rpc_calls.clear()
	e._rpc_draw_requested(1)
	assert_eq(e._hands[1], [10, 10, 5])
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_card_drawn":
			found = true
			break
	assert_false(found)
	e.free()
