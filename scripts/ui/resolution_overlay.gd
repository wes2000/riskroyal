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
	# Plan C Task 7: crown_awards step with delta >= 2 renders as a
	# structured sequenced animation instead of a static string.
	if step_name == "crown_awards":
		var deltas = payload.get("deltas", [])
		var has_stack: bool = false
		var has_single: bool = false
		for d in deltas:
			if int(d.get("delta", 0)) >= 2:
				has_stack = true
				_append_crown_stack_line(int(d.get("peer_id", 0)), int(d.get("delta", 0)))
			else:
				has_single = true
		if has_stack and not has_single:
			return
		if has_stack and has_single:
			# Mixed payload: append the delta==1 rows alongside the stacks.
			for d in deltas:
				if int(d.get("delta", 0)) < 2:
					_append_line(_format_crown_award_entry(int(d.get("peer_id", 0)), int(d.get("delta", 0))))
			return
	_append_line(format_resolution_step(step_name, payload))

func _append_crown_stack_line(peer_id: int, delta: int) -> void:
	if _lines == null:
		return
	var row = HBoxContainer.new()
	var prefix_lbl = Label.new()
	prefix_lbl.text = "P%d gets " % peer_id
	row.add_child(prefix_lbl)
	var first_crown = Label.new()
	first_crown.text = "👑"
	row.add_child(first_crown)
	var second_crown = Label.new()
	second_crown.text = "👑"
	second_crown.modulate.a = 0.0
	second_crown.position = Vector2(0.0, 20.0)
	row.add_child(second_crown)
	var count_lbl = Label.new()
	count_lbl.text = " %d CROWNS " % delta
	row.add_child(count_lbl)
	var suffix_lbl = Label.new()
	suffix_lbl.text = "(Sudden Death stack!)"
	suffix_lbl.modulate.a = 0.0
	row.add_child(suffix_lbl)
	_lines.add_child(row)
	var t = crown_stack_animation_timeline()
	var tw = create_tween()
	tw.tween_interval(float(t.delay_sec))
	tw.set_parallel(true)
	tw.tween_property(second_crown, "modulate:a", 1.0, float(t.second_crown_slide_sec))
	tw.tween_property(second_crown, "position:y", 0.0, float(t.second_crown_slide_sec))
	tw.set_parallel(false)
	tw.tween_property(suffix_lbl, "modulate:a", 1.0, float(t.suffix_fade_sec))

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
				parts.append(_format_crown_award_entry(int(d.get("peer_id", 0)), int(d.get("delta", 0))))
			return "Crowns: %s" % ", ".join(parts)
		"painful_reveal":
			# Rocket Clash extended payload (also fits future events that follow
			# the cash_outs_summary contract from spec section 11).
			if payload.has("crash_at") and payload.has("cash_outs_summary"):
				return _format_painful_reveal_rocket(payload)
			# Alpha remediation Phase B Change 2: Bomb Pot event-specific reveal.
			if payload.has("bomb_at_sec") and payload.has("pulls_summary"):
				return format_painful_reveal_bomb_pot(payload)
			# Alpha remediation Phase B Change 2: Card Cannon event-specific reveal.
			if payload.has("winner_score") and payload.has("scores_summary"):
				return format_painful_reveal_card_cannon(payload)
			# Existing TestEvent fallback (winner_peer_id + optional winner_name only)
			var winner_name = payload.get("winner_name", "")
			var winner_pid = payload.get("winner_peer_id", 0)
			if winner_name != "":
				return "Painful reveal: %s wins the event." % winner_name
			return "Painful reveal: P%d wins." % winner_pid
		_:
			return "(%s)" % step_name

# Plan C Task 7: crown_delta=2 stack animation timeline.
static func crown_stack_animation_timeline() -> Dictionary:
	return {
		"first_crown_fade_sec": 0.0,
		"delay_sec": 0.3,
		"second_crown_slide_sec": 0.4,
		"suffix_fade_sec": 0.3,
		"total_sec": 0.3 + 0.4 + 0.3,
	}

# Sub-project #7 Plan B Task 5: crown_delta=2 renders prominently.
# Only happens when Sudden Death Jackpot stacks with the regular Crown.
static func _format_crown_award_entry(peer_id: int, delta: int) -> String:
	if delta >= 2:
		return "P%d gets 👑👑 %d CROWNS (Sudden Death stack!)" % [peer_id, delta]
	return "P%d gets %d Crown" % [peer_id, delta]

# Alpha remediation Phase B Change 2: event-specific painful reveal for
# Bomb Pot. Spec §6.3 of the remediation design doc.
static func format_painful_reveal_bomb_pot(payload: Dictionary) -> String:
	var bomb_at_sec = float(payload.get("bomb_at_sec", 0.0))
	var winner_pid = int(payload.get("winner_peer_id", 0))
	var winner_pull_ms = int(payload.get("winner_pull_out_ms", 0))
	var pulls: Array = payload.get("pulls_summary", [])

	var lines: Array = []
	lines.append("BOMB! Pot popped at %.1fs" % bomb_at_sec)

	# Find the winner row + format with "last safe pull" emphasis
	var winner_row: Dictionary = {}
	for row in pulls:
		if int(row.get("peer_id", 0)) == winner_pid:
			winner_row = row
			break
	if not winner_row.is_empty():
		var name = String(winner_row.get("name", "P?"))
		var pull_sec = float(winner_pull_ms) / 1000.0
		var delta = int(winner_row.get("chip_delta", 0))
		lines.append("  %s pulled at %.1fs +%d chips, last safe pull" % [name, pull_sec, delta])

	# Other survivors (pullers who weren't the winner)
	for row in pulls:
		var pid = int(row.get("peer_id", 0))
		if pid == winner_pid:
			continue
		if bool(row.get("busted", false)):
			continue
		var name = String(row.get("name", "P?"))
		var pull_sec = float(int(row.get("pull_out_ms", 0))) / 1000.0
		var delta = int(row.get("chip_delta", 0))
		var sign = "+" if delta >= 0 else ""
		lines.append("  %s pulled at %.1fs %s%d chips" % [name, pull_sec, sign, delta])

	# Busted players
	for row in pulls:
		if not bool(row.get("busted", false)):
			continue
		var name = String(row.get("name", "P?"))
		var delta = int(row.get("chip_delta", 0))
		lines.append("  %s busted, still grabbing when it blew (%d chips)" % [name, delta])

	return "\n".join(lines)

# Alpha remediation Phase B Change 2: event-specific painful reveal for
# Card Cannon. Spec §6.4 of the remediation design doc.
static func format_painful_reveal_card_cannon(payload: Dictionary) -> String:
	var winner_pid = int(payload.get("winner_peer_id", 0))
	var winner_score = int(payload.get("winner_score", 0))
	var scores: Array = payload.get("scores_summary", [])

	var lines: Array = []
	# Headline
	var winner_name = ""
	for row in scores:
		if int(row.get("peer_id", 0)) == winner_pid:
			winner_name = String(row.get("name", ""))
			break
	if winner_name != "" and winner_score > 0:
		lines.append("CANNONS LOCKED! %s wins with %d" % [winner_name, winner_score])
	else:
		lines.append("CANNONS LOCKED! No winner — everyone overloaded")

	# Winner row first with Crown call-out + 21-perfect call-out
	for row in scores:
		var pid = int(row.get("peer_id", 0))
		if pid != winner_pid or bool(row.get("busted", false)):
			continue
		var name = String(row.get("name", "P?"))
		var lscore = int(row.get("locked_score", 0))
		var delta = int(row.get("chip_delta", 0))
		var sign = "+" if delta >= 0 else ""
		var crown_suffix = ", Crown"
		if lscore == 21:
			lines.append("  %s locked %d %s%d chips%s (PERFECT!)" % [name, lscore, sign, delta, crown_suffix])
		else:
			lines.append("  %s locked %d %s%d chips%s" % [name, lscore, sign, delta, crown_suffix])

	# Other survivors (locked but not winner)
	for row in scores:
		var pid = int(row.get("peer_id", 0))
		if pid == winner_pid:
			continue
		if bool(row.get("busted", false)):
			continue
		var name = String(row.get("name", "P?"))
		var lscore = int(row.get("locked_score", 0))
		var delta = int(row.get("chip_delta", 0))
		var sign = "+" if delta >= 0 else ""
		lines.append("  %s locked %d %s%d chips" % [name, lscore, sign, delta])

	# Busted players
	for row in scores:
		if not bool(row.get("busted", false)):
			continue
		var name = String(row.get("name", "P?"))
		var score = int(row.get("score", 0))
		var delta = int(row.get("chip_delta", 0))
		lines.append("  %s overloaded at %d (%d chips)" % [name, score, delta])

	return "\n".join(lines)

static func _format_painful_reveal_rocket(payload: Dictionary) -> String:
	var lines: Array = []
	var crash_at = float(payload.get("crash_at", 1.0))
	lines.append("CRASH! Rocket exploded at %.2fx" % crash_at)
	var winner_pid = int(payload.get("winner_peer_id", 0))
	var summary = payload.get("cash_outs_summary", [])
	for entry in summary:
		var name = String(entry.get("name", ""))
		if entry.get("busted", false):
			var wager = int(entry.get("wager", 0))
			lines.append("  %s busted (left %d chips on the table)" % [name, wager])
		else:
			var cash_out = float(entry.get("cash_out_at", 0.0))
			var chip_delta = int(entry.get("chip_delta", 0))
			var crown = " 👑 Crown" if int(entry.get("peer_id", -1)) == winner_pid else ""
			lines.append("  %s %.2fx +%d chips%s" % [name, cash_out, chip_delta, crown])
	return "\n".join(lines)
