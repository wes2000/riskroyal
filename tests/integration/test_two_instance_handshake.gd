extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const SignalingClient = preload("res://scripts/net/signaling_client.gd")
const WebRTCTransport = preload("res://scripts/net/web_rtc_transport.gd")
const NetConfig = preload("res://scripts/net/net_config.gd")

const HANDSHAKE_BUDGET := 15.0  # seconds
const PUMP_INTERVAL_MS := 50

func _signaling_server_reachable() -> bool:
	var ws := WebSocketPeer.new()
	ws.connect_to_url(NetConfig.SIGNALING_URL)
	var deadline := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < deadline:
		ws.poll()
		var state := ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			ws.close()
			return true
		if state == WebSocketPeer.STATE_CLOSED:
			return false
		OS.delay_msec(30)
	ws.close()
	return false

func _build_session() -> Dictionary:
	var sig := SignalingClient.new()
	var tx := WebRTCTransport.new()
	var sess := NetSession.new(tx, sig)
	# Bridge SDP/ICE in-test (autoload would do this in production but
	# autoloads do not run for GUT tests).
	sig.signal_received.connect(tx.feed_remote_signal)
	tx.signal_to_send.connect(sig.send_signal)
	return {"sig": sig, "tx": tx, "sess": sess}

# Forces the underlying WebSocket to STATE_OPEN before any send is attempted.
# put_packet fails if the WS is still STATE_CONNECTING; in production the
# autoload pumps every frame so by the time a UI action calls host_session
# the socket is usually open, but the test fires synchronously.
func _open_ws(sig) -> bool:
	sig._ensure_connected()
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		sig._ws.poll()
		if sig._ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			return true
		OS.delay_msec(20)
	return false

func _pump(instances: Array) -> void:
	for inst in instances:
		inst.sig.pump()
		# In production NetSessionMain assigns _transport.get_multiplayer_peer()
		# to MultiplayerAPI which polls it every frame. In GUT we don't have
		# that wiring, so poll the multiplayer peer and each per-peer
		# WebRTCPeerConnection manually to drive ICE state forward.
		var mp = inst.tx.get_multiplayer_peer()
		if mp != null:
			mp.poll()
		for id in inst.tx._connections.keys():
			var c = inst.tx._connections[id]
			if c != null:
				c.poll()
		inst.tx.pump()

func _wait_until(condition: Callable, instances: Array, budget_sec: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(budget_sec * 1000)
	while Time.get_ticks_msec() < deadline:
		_pump(instances)
		if condition.call():
			return true
		OS.delay_msec(PUMP_INTERVAL_MS)
	return false

func test_two_instance_handshake_completes_via_real_signaling():
	if not _signaling_server_reachable():
		pending("Signaling server not running on %s — start with 'cd server; node index.js' and re-run" % NetConfig.SIGNALING_URL)
		return

	var host = _build_session()
	var joiner = _build_session()

	# Manually wire welcome RPC — autoload would do this in production.
	host.sess.send_welcome_to.connect(func(_target, payload): joiner.sess.rpc_receive_welcome(payload))

	# Pre-open both WebSockets so the first put_packet does not race STATE_CONNECTING.
	assert_true(_open_ws(host.sig), "host WS should reach STATE_OPEN")
	assert_true(_open_ws(joiner.sig), "joiner WS should reach STATE_OPEN")

	# Host starts.
	host.sess.host_session()
	var host_code := [""]
	host.sig.code_issued.connect(func(c): host_code[0] = c)

	var got_code := _wait_until(
		func() -> bool: return host_code[0] != "",
		[host, joiner],
		HANDSHAKE_BUDGET
	)
	assert_true(got_code, "host should receive a code")

	# Joiner joins.
	joiner.sess.join_session(host_code[0])

	# Wait for full handshake: WebRTC connects, welcome flows, both sides have 2 players.
	var ok := _wait_until(
		func() -> bool: return host.sess.players.size() == 2 and joiner.sess.players.size() == 2,
		[host, joiner],
		HANDSHAKE_BUDGET
	)
	assert_true(ok, "both instances should end with 2 player slots")
	assert_eq(joiner.sess.state, 1, "joiner in LOBBY state (NetSessionState.LOBBY=1)")
	assert_eq(joiner.sess.local_peer_id, 2, "joiner has peer_id 2 from signaling")

	host.sess.leave_session()
	joiner.sess.leave_session()
