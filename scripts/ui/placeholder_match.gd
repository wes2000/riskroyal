# Placeholder scene shown after the host clicks Start. Displays the MatchStart
# payload for diagnostic purposes. Sub-project #2 will replace this with the
# real match loop scene.
extends Control

@onready var _info_label: Label = $VBoxContainer/MatchInfoLabel if has_node("VBoxContainer/MatchInfoLabel") else null

func _ready() -> void:
	var ms = _read_match_start_from_autoload()
	if _info_label == null:
		return
	if ms == null:
		_info_label.text = "(no MatchStart available)"
		return
	_info_label.text = format_match_start(ms)

func _read_match_start_from_autoload():
	# Lobby caused NetSessionMain to cache the MatchStart before
	# transitioning to this scene. See net_session_main.gd.
	if not get_tree().root.has_node("NetSessionMain"):
		return null
	var nsm = get_tree().root.get_node("NetSessionMain")
	if not nsm.has_method("get_last_match_start"):
		return null
	return nsm.get_last_match_start()

static func format_match_start(ms) -> String:
	var lines: Array = []
	lines.append("Match starting!")
	lines.append("Mode: %s" % ms.mode)
	lines.append("Host peer_id: %d" % ms.host_peer_id)
	lines.append("RNG seed: 0x%X" % ms.rng_seed)
	lines.append("%d players:" % ms.seats.size())
	for s in ms.seats:
		var host_tag = " (host)" if s.is_host else ""
		lines.append("  seat %d: %s [color %d] peer_id=%d%s" % [s.seat_index, s.name, s.color_index, s.peer_id, host_tag])
	return "\n".join(lines)
