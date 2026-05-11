extends GutTest

const SignalingClient = preload("res://scripts/net/signaling_client.gd")
const FakeWebSocketPeer = preload("res://tests/fakes/fake_web_socket_peer.gd")

var ws
var client

func before_each():
	ws = FakeWebSocketPeer.new()
	client = SignalingClient.new(ws)

func _sent_messages() -> Array:
	var out: Array = []
	for s in ws.sent_packets:
		out.append(JSON.parse_string(s))
	return out

func test_signals_declared():
	assert_true(client.has_signal("code_issued"))
	assert_true(client.has_signal("peer_arriving"))
	assert_true(client.has_signal("peer_id_assigned"))
	assert_true(client.has_signal("match_started_ack"))
	assert_true(client.has_signal("host_left"))
	assert_true(client.has_signal("joiner_left"))
	assert_true(client.has_signal("signaling_error"))
	assert_true(client.has_signal("signal_received"))

func test_request_code_opens_connection_and_sends_host():
	client.request_code()
	assert_eq(ws.connect_to_url_calls.size(), 1)
	var sent = _sent_messages()
	assert_eq(sent.size(), 1)
	assert_eq(sent[0].type, "host")

func test_connect_to_code_sends_join():
	client.connect_to_code("ABC234")
	var sent = _sent_messages()
	assert_eq(sent[0].type, "join")
	assert_eq(sent[0].code, "ABC234")
	assert_false(sent[0].has("reconnect_token"))

func test_connect_to_code_with_token_includes_token():
	client.connect_to_code("ABC234", "tok123")
	var sent = _sent_messages()
	assert_eq(sent[0].reconnect_token, "tok123")

func test_send_signal_serializes_payload():
	client.connect_to_code("ABC234")
	ws.sent_packets.clear()
	client.send_signal(1, {"sdp": "OFFER"})
	var sent = _sent_messages()
	assert_eq(sent[0].type, "signal")
	assert_eq(sent[0].to, 1)
	assert_eq(sent[0].payload, {"sdp": "OFFER"})

func test_notify_connected_with_no_peer_id():
	client.connect_to_code("ABC234")
	ws.sent_packets.clear()
	client.notify_connected()
	var sent = _sent_messages()
	assert_eq(sent[0].type, "connected")
	assert_false(sent[0].has("peerId"))

func test_notify_connected_with_peer_id():
	client.request_code()
	ws.sent_packets.clear()
	client.notify_connected(2)
	var sent = _sent_messages()
	assert_eq(sent[0].peerId, 2)

func test_send_start_match():
	client.request_code()
	ws.sent_packets.clear()
	client.send_start_match()
	var sent = _sent_messages()
	assert_eq(sent[0].type, "start_match")

func test_close_calls_underlying_close():
	client.request_code()
	client.close()
	assert_eq(ws.close_calls, 1)
