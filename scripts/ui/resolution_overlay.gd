# Reactive overlay shown during the RESOLUTION phase. Listens to
# MatchController.resolution_step and appends formatted lines as the
# substep pipeline progresses. Cleared at the start of each new event.
extends PanelContainer

@onready var _lines: VBoxContainer = $VBox/Lines if has_node("VBox/Lines") else null

var controller  # MatchController-like

func _ready() -> void:
	if controller == null:
		return
	controller.resolution_step.connect(_on_resolution_step)
	controller.phase_changed.connect(_on_phase_changed)

func _on_phase_changed(phase: int) -> void:
	var MatchPhase = load("res://scripts/match/match_phase.gd")
	if phase == MatchPhase.Phase.HOUSE_REVEAL:
		_clear_lines()

func _on_resolution_step(step_name: String, payload: Dictionary) -> void:
	_append_line(format_resolution_step(step_name, payload))

func _clear_lines() -> void:
	if _lines == null:
		return
	for child in _lines.get_children():
		child.queue_free()

func _append_line(text: String) -> void:
	if _lines == null:
		return
	var label = Label.new()
	label.text = text
	_lines.add_child(label)

# Static formatter (testable)

static func format_resolution_step(step_name: String, payload: Dictionary) -> String:
	match step_name:
		"busts":
			var ids = payload.get("bust_peer_ids", [])
			if ids.is_empty():
				return "No busts this event."
			var ids_str = ", ".join(ids.map(func(id): return "P%d" % id))
			return "Busts: %s" % ids_str
		"cash_outs":
			var co = payload.get("cash_outs", {})
			var parts: Array = []
			for pid in co.keys():
				parts.append("P%d cashed at %.2fx" % [pid, co[pid]])
			if parts.is_empty():
				return "Cash-outs: none."
			return "Cash-outs: %s" % ", ".join(parts)
		"chip_changes":
			var deltas = payload.get("deltas", [])
			var parts: Array = []
			for d in deltas:
				var sign = "+" if int(d.get("delta", 0)) > 0 else ""
				parts.append("P%d %s%d" % [int(d.get("peer_id", 0)), sign, int(d.get("delta", 0))])
			if parts.is_empty():
				return "Chips: no change."
			return "Chips: %s" % ", ".join(parts)
		"crown_awards":
			var deltas = payload.get("deltas", [])
			if deltas.is_empty():
				return "No Crown awarded."
			var parts: Array = []
			for d in deltas:
				parts.append("P%d gets %d Crown" % [int(d.get("peer_id", 0)), int(d.get("delta", 0))])
			return "Crowns: %s" % ", ".join(parts)
		"painful_reveal":
			var name = payload.get("winner_name", "")
			var pid = payload.get("winner_peer_id", 0)
			if name != "":
				return "Painful reveal: %s wins the event." % name
			return "Painful reveal: P%d wins." % pid
		_:
			return "(%s)" % step_name
