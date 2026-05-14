# Integration smoke test: real signaling + WebRTC + Announcer fires on
# all 4 trigger types (house_twist_announced, player_busted,
# crown_awarded, match_ended) across a 2-peer simulated match.
# Also verifies StatusGrid populates correctly per event and that
# PainfulReveal shows on bust and crown moments only.
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

func test_announcer_fires_across_phases():
	if not await _signaling_reachable():
		pending("Signaling server not reachable at %s; skipping. Start with `cd ../signaling-server && node server.js`." % SIGNALING_URL)
		return
	# Implementer note: cargo-cult test_three_event_rotation.gd; run
	# a 2-peer 3-event match; subscribe to controller signals on each
	# peer; assert: (a) house_twist_announced fires at HOUSE_TWIST end;
	# (b) player_busted fires for at least one peer across the match;
	# (c) crown_awarded fires for the event winner; (d) match_ended
	# fires once at the end with the winner in rankings[0].
	pending("Implementer: cargo-cult test_three_event_rotation.gd; subscribe to MatchController signals on both peers; assert Announcer-trigger signals fire on the host and mirror to the joiner.")
