extends GutTest

const CardCannonEvent = preload("res://scripts/events/card_cannon/card_cannon_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(peer_id: int, crowns: int = 0, heat: int = 0) -> RefCounted:
	var p = MatchPlayer.new()
	p.peer_id = peer_id
	p.seat_index = peer_id - 1
	p.name = "P%d" % peer_id
	p.is_active_this_event = true
	p.crowns = crowns
	p.heat = heat
	return p

func _make_context(players: Array, modifiers: Dictionary = {}) -> RefCounted:
	var ctx = EventContext.new()
	for p in players:
		ctx.players.append(p)
	ctx.event_modifiers = modifiers
	return ctx

# --- Explicit target ---

func test_resolve_target_uses_explicit_modifier():
	# P1 sets target=3 via event_modifiers — should use exactly 3 even
	# if P2 has more crowns.
	var ctx = _make_context(
		[_make_player(1), _make_player(2, 3, 0), _make_player(3, 0, 0)],
		{1: {"card_cannon_target_peer_id": 3}})
	assert_eq(CardCannonEvent.resolve_target_peer_id(ctx, 1), 3)

func test_resolve_target_zero_or_missing_falls_back_to_auto():
	# No target set — auto-pick highest crowns opponent (P2 has 3 crowns).
	var ctx = _make_context(
		[_make_player(1), _make_player(2, 3, 0), _make_player(3, 0, 0)],
		{})
	assert_eq(CardCannonEvent.resolve_target_peer_id(ctx, 1), 2,
		"auto-target picks highest-crown opponent")

# --- Auto-default fallback ---

func test_auto_default_prefers_highest_crowns():
	# P2: 3 crowns, P3: 1 crown — P1's auto-target is P2.
	var ctx = _make_context(
		[_make_player(1), _make_player(2, 3, 0), _make_player(3, 1, 5)],
		{})
	assert_eq(CardCannonEvent.resolve_target_peer_id(ctx, 1), 2)

func test_auto_default_ties_break_by_heat():
	# P2 and P3 both have 1 crown; P3 has more heat — P3 wins.
	var ctx = _make_context(
		[_make_player(1), _make_player(2, 1, 2), _make_player(3, 1, 5)],
		{})
	assert_eq(CardCannonEvent.resolve_target_peer_id(ctx, 1), 3,
		"crown tie broken by higher heat")

func test_auto_default_full_tie_breaks_by_lowest_seat_index():
	# P2 and P3 fully tied (1 crown each, 0 heat) — lowest seat_index
	# wins (P2 has seat_index 1, P3 has seat_index 2).
	var ctx = _make_context(
		[_make_player(1), _make_player(2, 1, 0), _make_player(3, 1, 0)],
		{})
	assert_eq(CardCannonEvent.resolve_target_peer_id(ctx, 1), 2,
		"full tie broken by lowest seat_index")

func test_auto_default_skips_self():
	# Even if self has the highest crowns, never auto-target self.
	var ctx = _make_context(
		[_make_player(1, 5, 0), _make_player(2, 1, 0)],
		{})
	assert_eq(CardCannonEvent.resolve_target_peer_id(ctx, 1), 2,
		"self never auto-targets self")

func test_auto_default_skips_inactive_opponents():
	# P2 is inactive (busted/skipped) — auto-target should fall to P3.
	var p2 = _make_player(2, 3, 0)
	p2.is_active_this_event = false
	var ctx = _make_context(
		[_make_player(1), p2, _make_player(3, 1, 0)],
		{})
	assert_eq(CardCannonEvent.resolve_target_peer_id(ctx, 1), 3,
		"inactive opponents skipped in auto-target")

func test_resolve_target_returns_zero_if_no_eligible():
	# Only player is self.
	var ctx = _make_context([_make_player(1)], {})
	assert_eq(CardCannonEvent.resolve_target_peer_id(ctx, 1), 0,
		"no eligible opponents returns 0")
