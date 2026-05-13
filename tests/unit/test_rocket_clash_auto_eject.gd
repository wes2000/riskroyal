extends GutTest

const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")

func _make_event_with_ctx(modifiers: Dictionary) -> Node:
	var e = Node.new()
	e.set_script(RocketClashEvent)
	e._is_host = true
	e._stashed_context = _make_ctx(modifiers)
	return e

func _make_ctx(modifiers: Dictionary):
	var EventContext = load("res://scripts/events/event_context.gd")
	var MatchPlayer = load("res://scripts/match/match_player.gd")
	var ctx = EventContext.new()
	for pid in [1, 2]:
		var p = MatchPlayer.new()
		p.peer_id = pid
		p.is_active_this_event = true
		ctx.players.append(p)
	ctx.event_modifiers = modifiers
	return ctx

func test_auto_eject_triggers_when_loaded_player_passes_threshold():
	var e = _make_event_with_ctx({1: {"auto_eject_loaded": true, "auto_eject_threshold": 3.0}})
	e._crash_at = 5.0
	e._active_peers = [1, 2]
	e._cash_outs = {}
	var triggered = e._check_auto_ejects(3.5)
	assert_true(1 in e._cash_outs, "P1 auto-ejected at 3.5")
	assert_almost_eq(float(e._cash_outs[1]), 3.5, 0.001)
	assert_eq(triggered.size(), 1)
	e.free()

func test_auto_eject_no_op_when_not_loaded():
	var e = _make_event_with_ctx({})
	e._crash_at = 5.0
	e._active_peers = [1, 2]
	e._cash_outs = {}
	var triggered = e._check_auto_ejects(3.5)
	assert_eq(e._cash_outs, {})
	assert_eq(triggered.size(), 0)
	e.free()

func test_auto_eject_no_op_when_already_cashed():
	var e = _make_event_with_ctx({1: {"auto_eject_loaded": true, "auto_eject_threshold": 3.0}})
	e._crash_at = 5.0
	e._active_peers = [1, 2]
	e._cash_outs = {1: 2.5}  # already cashed out lower
	var triggered = e._check_auto_ejects(3.5)
	assert_eq(triggered.size(), 0, "no re-ejection")
	assert_almost_eq(float(e._cash_outs[1]), 2.5, 0.001)
	e.free()

func test_auto_eject_no_op_when_above_crash():
	# Defensive: if process runs after crash, eject shouldn't fire.
	var e = _make_event_with_ctx({1: {"auto_eject_loaded": true, "auto_eject_threshold": 3.0}})
	e._crash_at = 4.0
	e._active_peers = [1, 2]
	e._cash_outs = {}
	var triggered = e._check_auto_ejects(4.5)  # past crash
	assert_eq(triggered.size(), 0)
	e.free()
