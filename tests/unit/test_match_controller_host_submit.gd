extends GutTest

# Covers the host_submit_* bot-friendly entry points on MatchController.
# Each method takes an explicit peer_id (bypassing the
# multiplayer.get_unique_id() inference in submit_*) and is gated on
# is_host. Mirrors the same internal _rpc_* receivers, so behavior parity
# is what we exercise here: state mutation on the host path, no-op on
# the client path.

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func _new_host_controller() -> MatchController:
	var c = MatchController.new(true, FakeMultiplayerNode.new())
	c.no_op_phase_delay_ms_override = 0
	return c

func _new_client_controller() -> MatchController:
	var c = MatchController.new(false, FakeMultiplayerNode.new())
	return c

func _seed_player(c: MatchController, peer_id: int, chips: int = 500, hand: Array = []) -> void:
	var p = MatchPlayer.new()
	p.peer_id = peer_id
	p.name = "P%d" % peer_id
	p.chips = chips
	p.hand = hand.duplicate()
	p.is_active_this_event = true
	c.state.players.append(p)

# ----- host_submit_wager -----

func test_host_submit_wager_host_routes_to_pending_wagers():
	var c = _new_host_controller()
	_seed_player(c, 2, 500)
	c.host_submit_wager(2, 250)
	assert_eq(c.state.pending_wagers.get(2, -1), 250,
		"host_submit_wager should populate pending_wagers via _rpc_set_wager")

func test_host_submit_wager_client_noops():
	var c = _new_client_controller()
	_seed_player(c, 2, 500)
	c.host_submit_wager(2, 250)
	assert_false(c.state.pending_wagers.has(2),
		"client host_submit_wager must not mutate state")

# ----- host_submit_loadout -----

func test_host_submit_loadout_host_sets_player_loadout():
	var c = _new_host_controller()
	_seed_player(c, 2, 500, ["heat_shield", "insurance"])
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c.host_submit_loadout(2, ["heat_shield"])
	var p = c.state.find_player(2)
	assert_eq(p.loadout, ["heat_shield"],
		"host_submit_loadout should set the player's loadout via _rpc_loadout_set")

func test_host_submit_loadout_client_noops():
	var c = _new_client_controller()
	_seed_player(c, 2, 500, ["heat_shield"])
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c.host_submit_loadout(2, ["heat_shield"])
	var p = c.state.find_player(2)
	assert_eq(p.loadout, [],
		"client host_submit_loadout must not mutate the player's loadout")

# ----- host_submit_card_play -----

func test_host_submit_card_play_host_routes_to_receiver():
	# Use a card with mismatched timing window so the dispatcher silently
	# drops — we just need to confirm the host code path actually runs
	# (vs. the early `if not is_host: return` guard). The cleanest way is
	# to observe the played_this_event side effect.
	var c = _new_host_controller()
	_seed_player(c, 2, 500, ["heat_shield"])
	var p = c.state.find_player(2)
	p.loadout = ["heat_shield"]
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	# heat_shield has timing "bet_loadout"; _current_timing_window() should
	# match BET_LOADOUT so the play actually applies and gets appended.
	c.host_submit_card_play(2, "heat_shield", 0, null)
	assert_true("heat_shield" in p.played_this_event,
		"host_submit_card_play should reach _rpc_card_play_requested and apply")

func test_host_submit_card_play_client_noops():
	var c = _new_client_controller()
	_seed_player(c, 2, 500, ["heat_shield"])
	var p = c.state.find_player(2)
	p.loadout = ["heat_shield"]
	c.state.phase = MatchPhase.Phase.BET_LOADOUT
	c.host_submit_card_play(2, "heat_shield", 0, null)
	assert_false("heat_shield" in p.played_this_event,
		"client host_submit_card_play must not mutate played_this_event")

# ----- host_submit_event_pick -----

func test_host_submit_event_pick_host_locks_event_id():
	var c = _new_host_controller()
	_seed_player(c, 2, 500)
	c.state.house_twist = {
		"type": "lowest_chips_picks",
		"params": {
			"picker_peer_id": 2,
			"options": ["rocket_clash", "bomb_pot", "card_cannon"],
		},
	}
	c.state.current_event_id = ""
	c.host_submit_event_pick(2, "bomb_pot")
	assert_eq(c.state.current_event_id, "bomb_pot",
		"host_submit_event_pick should set state.current_event_id via _rpc_event_picker_choice")

func test_host_submit_event_pick_client_noops():
	var c = _new_client_controller()
	_seed_player(c, 2, 500)
	c.state.house_twist = {
		"type": "lowest_chips_picks",
		"params": {
			"picker_peer_id": 2,
			"options": ["rocket_clash", "bomb_pot", "card_cannon"],
		},
	}
	c.state.current_event_id = ""
	c.host_submit_event_pick(2, "bomb_pot")
	assert_eq(c.state.current_event_id, "",
		"client host_submit_event_pick must not mutate current_event_id")

# ----- host_submit_shop_buy -----

func test_host_submit_shop_buy_host_deducts_chips_and_appends_hand():
	var c = _new_host_controller()
	_seed_player(c, 2, 500)
	c.state.phase = MatchPhase.Phase.SHOP
	c.state.current_shop_offer = ["heat_shield"]
	c.state.shop_done_peers = []
	c.host_submit_shop_buy(2, "heat_shield")
	var p = c.state.find_player(2)
	assert_eq(p.chips, 450, "host_submit_shop_buy should deduct cost_chips (50)")
	assert_true("heat_shield" in p.hand,
		"host_submit_shop_buy should append the card to hand")

func test_host_submit_shop_buy_client_noops():
	var c = _new_client_controller()
	_seed_player(c, 2, 500)
	c.state.phase = MatchPhase.Phase.SHOP
	c.state.current_shop_offer = ["heat_shield"]
	c.state.shop_done_peers = []
	c.host_submit_shop_buy(2, "heat_shield")
	var p = c.state.find_player(2)
	assert_eq(p.chips, 500, "client host_submit_shop_buy must not deduct chips")
	assert_false("heat_shield" in p.hand,
		"client host_submit_shop_buy must not append to hand")

# ----- host_submit_shop_done -----

func test_host_submit_shop_done_host_appends_to_shop_done_peers():
	var c = _new_host_controller()
	_seed_player(c, 2, 500)
	c.state.phase = MatchPhase.Phase.SHOP
	c.state.shop_done_peers = []
	c.host_submit_shop_done(2)
	assert_true(2 in c.state.shop_done_peers,
		"host_submit_shop_done should append peer to shop_done_peers")

func test_host_submit_shop_done_client_noops():
	var c = _new_client_controller()
	_seed_player(c, 2, 500)
	c.state.phase = MatchPhase.Phase.SHOP
	c.state.shop_done_peers = []
	c.host_submit_shop_done(2)
	assert_false(2 in c.state.shop_done_peers,
		"client host_submit_shop_done must not mutate shop_done_peers")
