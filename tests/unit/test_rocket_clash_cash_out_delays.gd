extends GutTest

const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")

func test_pending_cash_out_delays_defaults_empty():
	var e = Node.new()
	e.set_script(RocketClashEvent)
	assert_eq(e._pending_cash_out_delays, {})
	e.free()

func test_set_cash_out_delay_for_peer():
	var e = Node.new()
	e.set_script(RocketClashEvent)
	e.set_cash_out_delay(5, 750)
	assert_eq(e._pending_cash_out_delays.get(5, 0), 750)
	e.free()
