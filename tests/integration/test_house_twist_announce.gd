# Integration smoke test: real signaling + WebRTC + HOUSE_TWIST phase
# announces a twist to both peers. Spawns two NetSession instances;
# runs a 3-event match; verifies state.house_twist is mirrored across
# peers after each HOUSE_TWIST phase.
#
# Skips if signaling server is not reachable on ws://localhost:8080.
extends GutTest

const SIGNALING_URL := "ws://localhost:8080"

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

func test_house_twist_mirrored_across_peers():
	if not await _signaling_reachable():
		pending("Signaling server not reachable at %s; skipping. Start with `cd ../signaling-server && node server.js`." % SIGNALING_URL)
		return
	# Implementer note: cargo-cult test_three_event_rotation.gd; run
	# a 3-event match; after each HOUSE_TWIST phase fires, assert
	# both peers' state.house_twist.type matches.
	pending("Implementer: cargo-cult test_three_event_rotation.gd; assert state.house_twist mirror across peers.")
