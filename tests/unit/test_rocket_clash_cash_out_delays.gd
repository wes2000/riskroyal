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
	# Phase C Change 4: entries are Dictionaries carrying source attribution.
	var entry = e._pending_cash_out_delays.get(5, {})
	assert_eq(int(entry.get("delay_ms", 0)), 750)
	assert_eq(int(entry.get("source", -1)), 0, "source defaults to 0 when omitted")
	e.free()

func test_set_cash_out_delay_records_source():
	var e = Node.new()
	e.set_script(RocketClashEvent)
	e.set_cash_out_delay(5, 750, 2)
	var entry = e._pending_cash_out_delays.get(5, {})
	assert_eq(int(entry.get("delay_ms", 0)), 750)
	assert_eq(int(entry.get("source", 0)), 2, "source recorded for attribution")
	e.free()
