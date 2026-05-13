# Integration smoke test: real signaling + WebRTC + lowest_chips_picks
# twist drives the async picker flow. Spawns two NetSession instances;
# starts a match; forces the twist; verifies the picker peer's
# EventPickerOverlay shows buttons + the non-picker sees the waiting
# banner; submits a pick from the picker peer; verifies all peers'
# state.current_event_id mirror.
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

func test_lowest_chips_picker_flow_across_peers():
	if not await _signaling_reachable():
		pending("Signaling server not reachable at %s; skipping. Start with `cd ../signaling-server && node server.js`." % SIGNALING_URL)
		return
	# Implementer note: cargo-cult test_three_event_rotation.gd / Plan A's
	# test_house_twist_announce.gd. Force state.house_twist.type to
	# "lowest_chips_picks" via direct mutation before EVENT_SELECTION
	# fires; submit submit_event_pick from the picker peer; assert both
	# peers' state.current_event_id mirror after _rpc_event_picker_resolved.
	pending("Implementer: cargo-cult test_house_twist_announce.gd; assert picker submit propagates state.current_event_id across peers + verify timeout fallback on the host side.")
