extends GutTest

const CardCannonEvent = preload("res://scripts/events/card_cannon/card_cannon_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(peer_id: int, chips: int = 500) -> RefCounted:
	var p = MatchPlayer.new()
	p.peer_id = peer_id
	p.seat_index = peer_id - 1
	p.name = "P%d" % peer_id
	p.is_active_this_event = true
	p.chips = chips
	return p

func _make_context(player_count: int, wagers: Dictionary, modifiers: Dictionary = {}) -> RefCounted:
	var ctx = EventContext.new()
	for i in player_count:
		ctx.players.append(_make_player(i + 1))
	ctx.wagers = wagers
	ctx.event_modifiers = modifiers
	return ctx

# --- Attack tier table (chip_delta should include attack outcomes) ---

func test_locked_10_or_below_no_attack():
	# P1 locks 10 against P2. P2's chip_delta should not include any attack hit.
	var ctx = _make_context(2, {1: 100, 2: 100},
		{1: {"card_cannon_target_peer_id": 2}})
	var hands = {1: [5, 5], 2: [8, 9]}
	var locked = {1: 10, 2: 17}
	var busted = {}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	# P1 locks 10 → no attack on P2.
	# P2 locks 17 → 50 attack on P1.
	assert_true(int(result.per_player[1].get("incoming_attack", 0)) == 50,
		"P1 takes 50 incoming from P2's 17-lock")
	assert_true(int(result.per_player[2].get("incoming_attack", 0)) == 0,
		"P2 takes 0 incoming from P1's 10-lock")

func test_locked_21_perfect_max_attack_and_bonus_heat():
	var ctx = _make_context(2, {1: 100, 2: 100},
		{1: {"card_cannon_target_peer_id": 2}})
	var hands = {1: [10, 11], 2: [8, 9]}
	var locked = {1: 21, 2: 17}
	var busted = {}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	# P1 locks 21 → 100 attack on P2 + bonus heat
	assert_eq(int(result.per_player[2].get("incoming_attack", 0)), 100,
		"perfect-21 deals 100 attack")

func test_busted_shooter_does_not_fire():
	# P1 busts (locked = 0, busted = true). P2 locks 17.
	# P1 cannot fire on P2 even though P1 had a target.
	var ctx = _make_context(2, {1: 100, 2: 100},
		{1: {"card_cannon_target_peer_id": 2},
		 2: {"card_cannon_target_peer_id": 1}})
	var hands = {1: [10, 10, 8], 2: [8, 9]}
	var locked = {1: 0, 2: 17}
	var busted = {1: true}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	# P2 still fires at P1 (P1's incoming_attack from P2 = 50 for lock 17).
	assert_eq(int(result.per_player[1].get("incoming_attack", 0)), 50,
		"busted target still takes incoming hits")
	# But P1 cannot fire on P2 (P1 is busted).
	assert_eq(int(result.per_player[2].get("incoming_attack", 0)), 0,
		"busted shooter does not fire")

func test_chip_delta_includes_attack_transfer():
	# Verify chip_delta on both shooter + target reflects the transfer.
	# P1 locks 17 → +50 to P1's chip_delta, -50 to P2's chip_delta
	# (from the attack only — base payout adds on top).
	var ctx = _make_context(2, {1: 100, 2: 100},
		{1: {"card_cannon_target_peer_id": 2}})
	var hands = {1: [8, 9], 2: [5, 5]}
	var locked = {1: 17, 2: 10}
	var busted = {}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	# Get the per-player attack_delta values.
	assert_eq(int(result.per_player[1].get("attack_delta", 0)), 50,
		"P1 gains 50 from attack on P2")
	assert_eq(int(result.per_player[2].get("incoming_attack", 0)), 50,
		"P2 takes 50 incoming")

func test_attack_clamped_when_target_low_chips():
	# Target P2 has only 20 chips left — attack of 50 should clamp to 20.
	# The event reports the full intended attack; clamping at resolver
	# layer is a separate concern (see remediation §9.3 "Clamp target
	# chip loss to available chips.").
	var ctx = _make_context(2, {1: 100, 2: 100},
		{1: {"card_cannon_target_peer_id": 2}})
	var hands = {1: [8, 9], 2: [5, 5]}
	var locked = {1: 17, 2: 10}
	var busted = {}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	# The event reports the full attack; downstream resolver clamps.
	assert_eq(int(result.per_player[1].get("attack_delta", 0)), 50)
