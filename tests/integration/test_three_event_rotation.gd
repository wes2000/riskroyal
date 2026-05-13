# Integration smoke test: real signaling + WebRTC + 3-event rotation.
# Spawns two NetSession instances; runs a Quick Clash; verifies multiple
# event_id values appear across the painful_reveal stream.
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

func test_three_event_rotation():
	if not await _signaling_reachable():
		pending("Signaling server not reachable at %s; skipping. Start with `cd ../signaling-server && node server.js`." % SIGNALING_URL)
		return
	# Implementer note: full implementation should cargo-cult the host/
	# joiner NetSession setup from test_rocket_clash_runs.gd. Drive a
	# 5-event Quick Clash; collect event_ids from each painful_reveal;
	# assert at least 2 distinct event_ids appear (probabilistically all 3
	# but realistically 2+).
	#
	# Manual verification (running the game) is the primary surface for
	# the 3-event rotation behavior, per sub-project #3 precedent.
	pending("Implementer: cargo-cult test_rocket_clash_runs.gd; drive 5-event match; assert 2+ distinct event_ids.")
