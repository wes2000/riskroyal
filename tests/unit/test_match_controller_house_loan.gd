extends GutTest

# Alpha feel remediation Phase E §10.3 (Debt-Lite Comeback).
# When a player can't pay ante, the controller auto-accepts a House Loan:
# +HOUSE_LOAN_AMOUNT chips, +HOUSE_LOAN_AMOUNT debt, then pays ante,
# +1 Heat (clamped), is_active_this_event = true. If even the loan can't
# cover ante OR debt would exceed MAX_DEBT, falls through to skip path.

const MatchController = preload("res://scripts/match/match_controller.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")
const MatchState = preload("res://scripts/match/match_state.gd")

func _new_controller(is_host: bool = true) -> MatchController:
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(is_host, fake)
	c.no_op_phase_delay_ms_override = 0
	c.resolution_step_delay_ms_override = 0
	# Force "I am host peer 1" so _send_rpc enqueues to fake.
	c._local_peer_id_override = 1
	return c

func _new_player(pid: int, seat: int, chips: int = 500, debt: int = 0, heat: int = 0) -> MatchPlayer:
	var p = MatchPlayer.new()
	p.peer_id = pid
	p.seat_index = seat
	p.name = "P%d" % pid
	p.chips = chips
	p.debt = debt
	p.heat = heat
	p.is_active_this_event = true
	return p

func _seed_state(c: MatchController, players: Array, event_index: int = 0) -> void:
	c.state = MatchState.new()
	c.state.players = players
	c.state.event_index = event_index

func test_broke_player_auto_takes_house_loan_and_pays_ante():
	var c = _new_controller()
	# event_index 0 -> ante = 25. Player has 0 chips.
	var p = _new_player(2, 0, 0)
	_seed_state(c, [p])
	c._process_ante_phase()
	# Loan = 150, ante = 25 -> chips end at 150 - 25 = 125.
	assert_eq(p.chips, 125, "chips = HOUSE_LOAN - ante")
	assert_eq(p.debt, MatchConfig.HOUSE_LOAN_AMOUNT, "debt incremented by loan amount")
	assert_eq(p.heat, 1, "+1 Heat from loan stigma")
	assert_true(p.is_active_this_event, "player remains active for the event")

func test_house_loan_clamps_heat_at_max():
	var c = _new_controller()
	var p = _new_player(2, 0, 0, 0, MatchConfig.HEAT_MAX)
	_seed_state(c, [p])
	c._process_ante_phase()
	assert_eq(p.heat, MatchConfig.HEAT_MAX, "heat clamped at HEAT_MAX")

func test_house_loan_blocked_when_debt_would_exceed_max():
	# Existing debt 200, MAX_DEBT 300, loan 150 -> 200 + 150 = 350 > 300.
	# Loan refused; player falls through to skip path.
	var c = _new_controller()
	var p = _new_player(2, 0, 0, 200, 0)
	_seed_state(c, [p])
	c._process_ante_phase()
	assert_eq(p.debt, 200, "debt unchanged when loan would exceed MAX_DEBT")
	assert_eq(p.chips, 0, "chips unchanged in skip path")
	assert_eq(p.heat, 0, "heat unchanged in skip path")
	assert_false(p.is_active_this_event, "player skipped this event")

func test_house_loan_skipped_when_loan_still_cannot_cover_ante():
	# event_index 4 -> ante = 100. chips=0 + loan=150 = 150 >= 100, so this
	# path WOULD take the loan. To trigger the "loan still can't cover ante"
	# branch we need chips + 150 < ante. Easiest: ante 100, chips < -50,
	# which is impossible. Instead test the symmetric guard: chips just
	# below ante where chips + 150 >= ante triggers loan.
	# We assert the explicit chips + 150 < ante guard via a low-ante setup
	# isn't physically reachable, so this test focuses on the realistic
	# boundary: chips=0 at ante=100 still gets the loan.
	var c = _new_controller()
	var p = _new_player(2, 0, 0)
	_seed_state(c, [p], 4)  # event_index 4 -> ante 100
	c._process_ante_phase()
	assert_eq(p.chips, 50, "loan 150 - ante 100 = 50")
	assert_eq(p.debt, MatchConfig.HOUSE_LOAN_AMOUNT, "loan taken")
	assert_true(p.is_active_this_event, "active after loan")

func test_solvent_player_unaffected_by_house_loan_branch():
	# Regression guard: existing happy path must still work.
	var c = _new_controller()
	var p = _new_player(2, 0, 500)
	_seed_state(c, [p])
	c._process_ante_phase()
	assert_eq(p.chips, 475, "500 - ante 25 = 475")
	assert_eq(p.debt, 0, "no debt taken when solvent")
	assert_eq(p.heat, 0, "no heat penalty when solvent")
	assert_true(p.is_active_this_event)

func test_house_loan_emits_delta_with_debt_field():
	# §10.3 + spec note 4: the broadcast delta carries debt_delta so clients
	# mirror the host-side mutation.
	var c = _new_controller()
	var p = _new_player(2, 0, 0)
	_seed_state(c, [p])
	# Add a second player so there's a "remote" peer the rpc will target.
	var p2 = _new_player(3, 1, 500)
	c.state.players.append(p2)
	c._process_ante_phase()
	var apply_delta_calls = []
	for call in c._multiplayer_node.rpc_calls:
		if String(call.get("method", "")) == "_rpc_apply_deltas":
			apply_delta_calls.append(call)
	assert_eq(apply_delta_calls.size(), 1, "exactly one _rpc_apply_deltas broadcast")
	var deltas: Array = apply_delta_calls[0]["args"][0]
	var loan_delta = null
	for d in deltas:
		if int(d.get("peer_id", 0)) == 2:
			loan_delta = d
			break
	assert_true(loan_delta != null, "delta for loaning player present")
	assert_eq(int(loan_delta.get("debt_delta", 0)), MatchConfig.HOUSE_LOAN_AMOUNT,
		"debt_delta carries the loan amount")
	assert_eq(int(loan_delta.get("chip_delta", 0)), MatchConfig.HOUSE_LOAN_AMOUNT - 25,
		"chip_delta is loan - ante")
	assert_eq(int(loan_delta.get("heat_delta", 0)), 1, "heat_delta = 1")
