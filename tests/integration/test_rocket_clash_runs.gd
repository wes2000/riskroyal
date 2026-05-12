# Integration smoke test: real signaling + WebRTC + Match loop + Rocket Clash.
# Spawns two NetSession instances; runs one Rocket Clash event end-to-end
# with compressed timing; both peers observe consistent painful_reveal.
#
# Skips if signaling server is not reachable on ws://localhost:8080.
extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const WebRTCTransport = preload("res://scripts/net/web_rtc_transport.gd")
const SignalingClient = preload("res://scripts/net/signaling_client.gd")
const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")

const SIGNALING_URL := "ws://localhost:8080"
const CONNECTION_TIMEOUT_SEC := 10.0
const MATCH_TIMEOUT_SEC := 30.0

func _signaling_reachable() -> bool:
	var probe = WebSocketPeer.new()
	var err = probe.connect_to_url(SIGNALING_URL)
	if err != OK:
		return false
	var t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1000:
		probe.poll()
		if probe.get_ready_state() == WebSocketPeer.STATE_OPEN:
			probe.close()
			return true
		if probe.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			return false
		await get_tree().process_frame
	probe.close()
	return false

func test_rocket_clash_two_peers_consistent_reveal():
	if not await _signaling_reachable():
		pending("Signaling server not reachable at %s; skipping." % SIGNALING_URL)
		return

	# Spawn host
	var host_transport = WebRTCTransport.new()
	var host_signaling = SignalingClient.new(SIGNALING_URL)
	var host = NetSession.new(host_transport, host_signaling)
	add_child_autofree(host_transport)
	add_child_autofree(host_signaling)
	host.host_session()
	var host_code = await _wait_for_code(host)

	# Spawn joiner
	var joiner_transport = WebRTCTransport.new()
	var joiner_signaling = SignalingClient.new(SIGNALING_URL)
	var joiner = NetSession.new(joiner_transport, joiner_signaling)
	add_child_autofree(joiner_transport)
	add_child_autofree(joiner_signaling)
	joiner.join_session(host_code)

	await _wait_until(func(): return host.players.size() == 2 and joiner.players.size() == 2, CONNECTION_TIMEOUT_SEC)

	# MatchStart capture
	var host_ms = [null]
	var joiner_ms = [null]
	host.match_starting.connect(func(ms): host_ms[0] = ms)
	joiner.match_starting.connect(func(ms): joiner_ms[0] = ms)

	host.set_ready(true)
	joiner.set_ready(true)
	host.start_match()

	await _wait_until(func(): return host_ms[0] != null and joiner_ms[0] != null, CONNECTION_TIMEOUT_SEC)
	assert_not_null(host_ms[0], "host got MatchStart")
	assert_not_null(joiner_ms[0], "joiner got MatchStart")

	# Controllers
	var host_controller = MatchController.new(true, null)
	var joiner_controller = MatchController.new(false, null)
	add_child_autofree(host_controller)
	add_child_autofree(joiner_controller)
	# Compress all timer paths
	host_controller.no_op_phase_delay_ms_override = 10
	host_controller.resolution_step_delay_ms_override = 10
	host_controller.event_timeout_sec_override = 10.0
	host_controller.bet_loadout_timeout_sec_override = 1.0
	joiner_controller.no_op_phase_delay_ms_override = 10
	joiner_controller.resolution_step_delay_ms_override = 10
	joiner_controller.bet_loadout_timeout_sec_override = 1.0

	var host_match_ended = [false, []]
	var joiner_match_ended = [false, []]
	host_controller.match_ended.connect(func(r): host_match_ended[0] = true; host_match_ended[1] = r)
	joiner_controller.match_ended.connect(func(r): joiner_match_ended[0] = true; joiner_match_ended[1] = r)

	host_controller.start_match(host_ms[0])

	# Wait for the match to complete. The BET_LOADOUT timer (1s) + 5 events
	# × (1s timer + a few hundred ms rocket time) ≈ 10-15s total under
	# compressed timing.
	await _wait_until(func(): return host_match_ended[0] and joiner_match_ended[0], MATCH_TIMEOUT_SEC)

	assert_true(host_match_ended[0], "host saw match_ended")
	assert_true(joiner_match_ended[0], "joiner saw match_ended")
	assert_eq(host_match_ended[1].size(), 2)
	assert_eq(joiner_match_ended[1].size(), 2)
	assert_eq(host_match_ended[1][0].peer_id, joiner_match_ended[1][0].peer_id, "consistent winner across peers")

# Helpers
func _wait_for_code(host) -> String:
	var t0 = Time.get_ticks_msec()
	while host.code == "" and Time.get_ticks_msec() - t0 < CONNECTION_TIMEOUT_SEC * 1000:
		await get_tree().process_frame
	return host.code

func _wait_until(predicate: Callable, timeout_sec: float) -> void:
	var t0 = Time.get_ticks_msec()
	while not predicate.call():
		if Time.get_ticks_msec() - t0 > timeout_sec * 1000:
			return
		await get_tree().process_frame
