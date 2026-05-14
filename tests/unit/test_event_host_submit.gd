extends GutTest

# Covers the host_submit_* bot-friendly entry points on the three event
# nodes (Rocket Clash, Bomb Pot, Card Cannon). Each takes an explicit
# peer_id and routes to the same _rpc_* receiver that remote peers use.
# Host-only — non-host call should warn and no-op.

const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")
const BombPotEvent = preload("res://scripts/events/bomb_pot/bomb_pot_event.gd")
const CardCannonEvent = preload("res://scripts/events/card_cannon/card_cannon_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

# ----- Rocket Clash -----

func _new_host_rocket_clash() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var e = Node.new()
	e.set_script(RocketClashEvent)
	e._is_host = true
	e._multiplayer_node = fake
	e._start_time_ms = Time.get_ticks_msec()
	e._active_peers = [1, 2]
	e._force_current_mult_for_testing = 2.0
	# _emit_status_changed walks _stashed_context.players; give it a stub.
	var ctx = EventContext.new()
	ctx.rng_seed = 1
	e._stashed_context = ctx
	return {"event": e, "fake": fake}

func _new_client_rocket_clash() -> Dictionary:
	var d = _new_host_rocket_clash()
	d.event._is_host = false
	return d

func test_rocket_clash_host_submit_cash_out_records_on_host():
	var d = _new_host_rocket_clash()
	var e = d.event
	e.host_submit_cash_out(2, 2.0)
	assert_true(e._cash_outs.has(2),
		"host_submit_cash_out should record peer in _cash_outs via _rpc_cash_out_requested")
	assert_almost_eq(float(e._cash_outs[2]), 2.0, 0.001)
	e.free()

func test_rocket_clash_host_submit_cash_out_client_noops():
	var d = _new_client_rocket_clash()
	var e = d.event
	e.host_submit_cash_out(2, 2.0)
	assert_false(e._cash_outs.has(2),
		"client host_submit_cash_out must not mutate _cash_outs")
	e.free()

# ----- Bomb Pot -----

func _new_host_bomb_pot() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var e = Node.new()
	e.set_script(BombPotEvent)
	e._is_host = true
	e._multiplayer_node = fake
	e._start_time_ms = Time.get_ticks_msec()
	e._active_peers = [1, 2]
	e._shares_accumulator = {1: 50.0, 2: 75.0}
	var ctx = EventContext.new()
	ctx.rng_seed = 1
	e._stashed_context = ctx
	return {"event": e, "fake": fake}

func _new_client_bomb_pot() -> Dictionary:
	var d = _new_host_bomb_pot()
	d.event._is_host = false
	return d

func test_bomb_pot_host_submit_pull_out_records_on_host():
	var d = _new_host_bomb_pot()
	var e = d.event
	e.host_submit_pull_out(2)
	assert_true(2 in e._pulled_out_peers,
		"host_submit_pull_out should append peer to _pulled_out_peers via _rpc_pull_out_requested")
	assert_eq(e._locked_shares.get(2, 0), 75,
		"host_submit_pull_out should lock the share at pull time")
	e.free()

func test_bomb_pot_host_submit_pull_out_client_noops():
	var d = _new_client_bomb_pot()
	var e = d.event
	e.host_submit_pull_out(2)
	assert_false(2 in e._pulled_out_peers,
		"client host_submit_pull_out must not mutate _pulled_out_peers")
	e.free()

# ----- Card Cannon -----

func _new_host_card_cannon() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var e = Node.new()
	e.set_script(CardCannonEvent)
	e._is_host = true
	e._multiplayer_node = fake
	e._active_peers = [1, 2]
	e._hands = {1: [], 2: []}
	e._scores = {1: 0, 2: 0}
	e._busted = {1: false, 2: false}
	var ctx = EventContext.new()
	ctx.rng_seed = 1
	e._stashed_context = ctx
	return {"event": e, "fake": fake}

func _new_client_card_cannon() -> Dictionary:
	var d = _new_host_card_cannon()
	d.event._is_host = false
	return d

func test_card_cannon_host_submit_draw_appends_to_hand_on_host():
	var d = _new_host_card_cannon()
	var e = d.event
	e._force_next_rank_override = 7
	e.host_submit_draw(2)
	assert_eq(e._hands[2], [7],
		"host_submit_draw should append a rank to the player's hand via _rpc_draw_requested")
	assert_eq(e._scores[2], 7)
	e.free()

func test_card_cannon_host_submit_draw_client_noops():
	var d = _new_client_card_cannon()
	var e = d.event
	e._force_next_rank_override = 7
	e.host_submit_draw(2)
	assert_eq(e._hands[2], [],
		"client host_submit_draw must not mutate _hands")
	e.free()

func test_card_cannon_host_submit_lock_locks_score_on_host():
	var d = _new_host_card_cannon()
	var e = d.event
	e._scores[2] = 15
	e.host_submit_lock(2)
	assert_eq(e._locked_scores.get(2, -1), 15,
		"host_submit_lock should lock the current score via _rpc_lock_requested")
	e.free()

func test_card_cannon_host_submit_lock_client_noops():
	var d = _new_client_card_cannon()
	var e = d.event
	e._scores[2] = 15
	e.host_submit_lock(2)
	assert_false(e._locked_scores.has(2),
		"client host_submit_lock must not mutate _locked_scores")
	e.free()
