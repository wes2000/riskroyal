extends GutTest

const EventNode = preload("res://scripts/events/event_node.gd")

func test_base_class_declares_signals():
	var n = EventNode.new()
	assert_true(n.has_signal("event_complete"))
	assert_true(n.has_signal("event_progress"))

func test_base_class_has_virtual_methods():
	var n = EventNode.new()
	assert_true(n.has_method("_run"))
	assert_true(n.has_method("get_event_id"))

func test_base_get_event_id_returns_base():
	var n = EventNode.new()
	assert_eq(n.get_event_id(), "base")
