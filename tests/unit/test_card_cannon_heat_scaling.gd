extends GutTest

const CardCannonEvent = preload("res://scripts/events/card_cannon/card_cannon_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(peer_id: int) -> RefCounted:
	var p = MatchPlayer.new()
	p.peer_id = peer_id
	p.seat_index = peer_id - 1
	p.name = "P%d" % peer_id
	p.is_active_this_event = true
	return p

func _make_context(player_count: int, wagers: Dictionary, modifiers: Dictionary) -> RefCounted:
	var ctx = EventContext.new()
	for i in player_count:
		ctx.players.append(_make_player(i + 1))
	ctx.wagers = wagers
	ctx.event_modifiers = modifiers
	return ctx

# Perfect 21 -> +3 Heat from HeatRules, plus +1 bonus Heat per
# Alpha remediation Phase D D.2 (§9.3): "shooter gets +1 bonus Heat"
# on perfect-21 attack -> +4 total when the perfect 21 fires.
func test_card_cannon_heat_perfect_21():
	var ctx = _make_context(2, {1: 100, 2: 100}, {})
	var hands = {1: [11, 10], 2: [10, 5]}
	var locked = {1: 21, 2: 15}
	var busted = {1: false, 2: false}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	assert_eq(int(result.per_player[1].heat_delta), 4,
		"perfect 21 = +3 base Heat + 1 perfect-attack bonus Heat")

# 19+ -> +2 Heat.
func test_card_cannon_heat_high_lock_19():
	var ctx = _make_context(2, {1: 100, 2: 100}, {})
	var hands = {1: [10, 9], 2: [10, 5]}
	var locked = {1: 19, 2: 15}
	var busted = {1: false, 2: false}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	assert_eq(int(result.per_player[1].heat_delta), 2, "19 locked = +2 Heat")

# Low-score winner (15) -> +1 Heat. Non-winner under 19 -> 0.
func test_card_cannon_heat_low_winner():
	var ctx = _make_context(2, {1: 100, 2: 100}, {})
	var hands = {1: [10, 5], 2: [10, 3]}
	var locked = {1: 15, 2: 13}
	var busted = {1: false, 2: false}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	assert_eq(int(result.per_player[1].heat_delta), 1, "low-score winner = +1 Heat")
	assert_eq(int(result.per_player[2].heat_delta), 0, "non-winner under 19 = 0 Heat")

# Busted player -> 0 Heat.
func test_card_cannon_heat_busted_zero():
	var ctx = _make_context(2, {1: 100, 2: 100}, {})
	var hands = {1: [10, 10, 5], 2: [10, 9]}
	var locked = {2: 19}
	var busted = {1: true, 2: false}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	assert_eq(int(result.per_player[1].heat_delta), 0, "busted player gets 0 Heat")

# Heat Shield halves perfect-21 base Heat (3 -> 1, since
# floor(3*0.5)=1). The +1 bonus Heat from the perfect-21 attack per
# Alpha remediation Phase D D.2 (§9.3) stacks on top of the shielded
# base -> 1 + 1 = 2.
func test_card_cannon_heat_shield_halves_perfect():
	var ctx = _make_context(2, {1: 100, 2: 100}, {1: {"heat_shield": true}})
	var hands = {1: [11, 10], 2: [10, 5]}
	var locked = {1: 21, 2: 15}
	var busted = {1: false, 2: false}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	assert_eq(int(result.per_player[1].heat_delta), 2,
		"Heat Shield halves base 3 -> 1; +1 perfect-attack bonus = 2")
