extends GutTest

const WebRTCTransport = preload("res://scripts/net/web_rtc_transport.gd")

func test_instantiates_without_error():
	var t = WebRTCTransport.new()
	assert_not_null(t)

func test_required_signals_declared():
	var t = WebRTCTransport.new()
	assert_true(t.has_signal("peer_joined"))
	assert_true(t.has_signal("peer_left"))
	assert_true(t.has_signal("transport_failed"))
	assert_true(t.has_signal("signal_to_send"))

func test_has_required_methods():
	var t = WebRTCTransport.new()
	assert_true(t.has_method("start_host"))
	assert_true(t.has_method("start_client"))
	assert_true(t.has_method("add_peer"))
	assert_true(t.has_method("close"))
	assert_true(t.has_method("feed_remote_signal"))
	assert_true(t.has_method("pump"))
	assert_true(t.has_method("get_multiplayer_peer"))

func test_feed_remote_signal_with_malformed_payload_does_not_crash():
	var t = WebRTCTransport.new()
	t.start_host()
	# No sdp_type, no ice_candidate — should silently ignore.
	t.feed_remote_signal(2, {"junk": "stuff"})
	assert_true(true)  # No crash = pass.
