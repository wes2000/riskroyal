# Integration smoke test: real signaling + WebRTC + SoundManager fires
# the 4 cued SFX on the right MatchController signals across a 2-peer
# simulated match. Also verifies the dispatcher wiring survives a full
# event lifecycle (HOUSE_REVEAL -> BET_LOADOUT -> MAIN_EVENT -> RESOLUTION).
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

func test_sound_dispatcher_fires_across_events():
	if not await _signaling_reachable():
		pending("Signaling server not reachable at %s; skipping. Start with `cd ../signaling-server && node server.js`." % SIGNALING_URL)
		return
	# Implementer note: cargo-cult test_announcer_fires_across_phases.gd
	# from Plan B; subscribe to SoundManager-bound signals on both peers;
	# assert the 4 cue methods fired in the expected order (twist_stinger
	# at HOUSE_TWIST, bust during MAIN_EVENT, crown_win at RESOLUTION,
	# match_end at MATCH_END).
	pending("Implementer: cargo-cult Plan B's integration stubs; subscribe to MatchController signals on both peers; assert SoundManager plays the right cue at each event-lifecycle step.")
