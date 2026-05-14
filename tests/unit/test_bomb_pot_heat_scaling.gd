extends GutTest

const BombPotEvent = preload("res://scripts/events/bomb_pot/bomb_pot_event.gd")
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

# bomb_at = 10s, P1 pulls at 9500ms (95% ratio) -> 4 Heat (legendary).
func test_bomb_pot_heat_95_percent_ratio_legendary():
	var ctx = _make_context(2, {1: 100, 2: 100}, {})
	var locked = {1: 200, 2: 50}
	var pulled = [1, 2]
	var timestamps = {1: 9500, 2: 3000}
	var result = BombPotEvent.compute_event_result(ctx, 10.0, locked, pulled, timestamps)
	assert_eq(int(result.per_player[1].heat_delta), 4, "95% pull-out ratio = +4 Heat")

# bomb_at = 10s, P1 pulls at 8000ms (80% ratio) -> 3 Heat.
func test_bomb_pot_heat_80_percent_ratio_late_pull():
	var ctx = _make_context(2, {1: 100, 2: 100}, {})
	var locked = {1: 200, 2: 50}
	var pulled = [1, 2]
	var timestamps = {1: 8000, 2: 3000}
	var result = BombPotEvent.compute_event_result(ctx, 10.0, locked, pulled, timestamps)
	assert_eq(int(result.per_player[1].heat_delta), 3, "80% pull-out ratio = +3 Heat")

# bomb_at = 10s, P1 (winner) pulls at 5000ms (50% ratio) with locked share>0
# -> won_crown tier: 2 Heat. P2 pulls earlier with share -> 1 Heat.
func test_bomb_pot_heat_winner_low_ratio():
	var ctx = _make_context(2, {1: 100, 2: 100}, {})
	var locked = {1: 200, 2: 100}
	var pulled = [1, 2]
	var timestamps = {1: 5000, 2: 3000}  # P1 last puller
	var result = BombPotEvent.compute_event_result(ctx, 10.0, locked, pulled, timestamps)
	assert_eq(int(result.per_player[1].heat_delta), 2, "winner with sub-80% ratio = +2 Heat")
	assert_eq(int(result.per_player[2].heat_delta), 1, "non-winner with share = +1 Heat")

# Busted player (didn't pull) -> 0 Heat regardless.
func test_bomb_pot_heat_busted_zero():
	var ctx = _make_context(2, {1: 100, 2: 100}, {})
	var locked = {1: 200}
	var pulled = [1]  # P2 didn't pull, busted
	var timestamps = {1: 8000}
	var result = BombPotEvent.compute_event_result(ctx, 10.0, locked, pulled, timestamps)
	assert_eq(int(result.per_player[2].heat_delta), 0, "busted player gets 0 Heat")

# Heat Shield halves the legendary pull (4 -> 2).
func test_bomb_pot_heat_shield_halves_legendary():
	var ctx = _make_context(2, {1: 100, 2: 100}, {1: {"heat_shield": true}})
	var locked = {1: 200, 2: 50}
	var pulled = [1, 2]
	var timestamps = {1: 9500, 2: 3000}
	var result = BombPotEvent.compute_event_result(ctx, 10.0, locked, pulled, timestamps)
	assert_eq(int(result.per_player[1].heat_delta), 2, "Heat Shield halves 4 -> 2")
