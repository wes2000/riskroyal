# Reactive overlay shown during the RESOLUTION phase. Listens to
# MatchController.resolution_step and appends formatted lines as the
# substep pipeline progresses. Cleared at the start of each new event.
extends PanelContainer

@onready var _lines: VBoxContainer = $VBox/Lines if has_node("VBox/Lines") else null

var controller  # MatchController-like

# Alpha remediation Phase F §11.3: queued modifier notes from card plays
# during BET_LOADOUT / MAIN_EVENT, flushed when the painful_reveal step
# fires during RESOLUTION so spectators see "why" each diverging line
# item happened. Cleared at HOUSE_REVEAL like the rest of the overlay.
var _pending_modifier_notes: Array = []

func _ready() -> void:
	if controller == null:
		return
	controller.resolution_step.connect(_on_resolution_step)
	controller.phase_changed.connect(_on_phase_changed)
	# Alpha remediation Phase F §11.3: capture modifier card plays so
	# the visual tag can be appended at painful_reveal time. Guarded by
	# has_signal so test harnesses without the signal don't trip.
	if controller.has_signal("card_effect_applied"):
		controller.card_effect_applied.connect(_on_card_effect_applied)

func _on_phase_changed(phase: int) -> void:
	var MatchPhase = load("res://scripts/match/match_phase.gd")
	if phase == MatchPhase.Phase.HOUSE_REVEAL:
		_clear_lines()
		_pending_modifier_notes.clear()

func _on_card_effect_applied(peer_id: int, card_id: String, effect_result: Dictionary) -> void:
	# Alpha remediation Phase F §11.3: only the 4 modifier cards generate
	# a visual tag at resolution. Build the note payload from controller
	# state + the effect_result Dictionary so the static formatter stays
	# pure (testable without a live overlay).
	if not _is_modifier_note_card(card_id):
		return
	var note_payload = _build_modifier_note_payload(peer_id, card_id, effect_result)
	if should_suppress_modifier_note(card_id, note_payload):
		return
	var note = format_modifier_note(card_id, note_payload)
	if note != "":
		_pending_modifier_notes.append(note)

# Pure dispatch table so the resolution-step path can ask "should I look
# at this card?" without duplicating the match statement in
# format_modifier_note.
func _is_modifier_note_card(card_id: String) -> bool:
	return card_id in ["insurance", "wager_tax", "multiplier_booster", "cash_out_jammer"]

# Resolves names + numeric fields from controller.state + effect_result.
# Caller (_on_card_effect_applied) guarantees card_id is one of the four
# modifier cards.
func _build_modifier_note_payload(peer_id: int, card_id: String,
		effect_result: Dictionary) -> Dictionary:
	var payload: Dictionary = {}
	match card_id:
		"insurance":
			payload["target_name"] = _name_for(peer_id)
			# Refund amount is computed at resolution; absent from effect_result.
			# Live overlay reads it from the chip_changes step where possible
			# (deferred — overlay flushes the note with refund_amount = 0 today,
			# producing "Insurance saved <Name> 0 chips" which is intentionally
			# truthful when no bust occurred).
			payload["refund_amount"] = int(effect_result.get("refund_amount", 0))
		"wager_tax":
			payload["source_name"] = _name_for(int(effect_result.get("source", 0)))
			payload["target_name"] = _name_for(int(effect_result.get("target", 0)))
			payload["tax_amount"] = int(effect_result.get("tax_amount", 0))
		"multiplier_booster":
			payload["target_name"] = _name_for(peer_id)
			payload["multiplier"] = float(effect_result.get("multiplier", 1.0))
		"cash_out_jammer":
			payload["source_name"] = _name_for(int(effect_result.get("source", 0)))
			payload["target_name"] = _name_for(int(effect_result.get("target", 0)))
			payload["delay_ms"] = int(effect_result.get("delay_ms", 0))
	return payload

func _name_for(peer_id: int) -> String:
	if controller == null or controller.state == null:
		return "P%d" % peer_id
	var p = controller.state.find_player(peer_id)
	if p == null:
		return "P%d" % peer_id
	return String(p.name)

func _flush_modifier_notes() -> void:
	for note in _pending_modifier_notes:
		_append_line(note)
	_pending_modifier_notes.clear()

func _on_resolution_step(step_name: String, payload: Dictionary) -> void:
	# Alpha remediation Phase F §11.3: flush the modifier notes captured
	# during BET_LOADOUT / MAIN_EVENT at the painful reveal so spectators
	# read the "why" alongside the cash-out / chip outcome.
	if step_name == "painful_reveal":
		_flush_modifier_notes()
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

# Insurance/Wager Tax compute their actual amount at resolution time, not at
# card-play time. When the effect didn't observably fire (player didn't bust
# → no refund; target had no positive delta → no tax), suppress the note
# rather than show "saved 0 chips". The card is silently inert.
static func should_suppress_modifier_note(card_id: String, payload: Dictionary) -> bool:
	if card_id == "insurance":
		return int(payload.get("refund_amount", 0)) == 0
	if card_id == "wager_tax":
		return int(payload.get("tax_amount", 0)) == 0
	return false

# Alpha remediation Phase F §11.3: composes the visual tag for one of the
# four modifier cards. Returns "" for any other card_id so the overlay
# can short-circuit. Spec doesn't pin literal copy; these strings are
# pinned by test_resolution_overlay_card_modifier_notes.gd so future
# edits land deliberately.
static func format_modifier_note(card_id: String, payload: Dictionary) -> String:
	match card_id:
		"insurance":
			return "Insurance saved %s %d chips" % [
				String(payload.get("target_name", "")),
				int(payload.get("refund_amount", 0)),
			]
		"wager_tax":
			return "Wager Tax: %s lost %d chips to %s" % [
				String(payload.get("target_name", "")),
				int(payload.get("tax_amount", 0)),
				String(payload.get("source_name", "")),
			]
		"multiplier_booster":
			var pct = int(round((float(payload.get("multiplier", 1.0)) - 1.0) * 100.0))
			return "%s's multiplier boosted (+%d%%)" % [
				String(payload.get("target_name", "")),
				pct,
			]
		"cash_out_jammer":
			return "Cash-out delayed: %s held %s for %dms" % [
				String(payload.get("source_name", "")),
				String(payload.get("target_name", "")),
				int(payload.get("delay_ms", 0)),
			]
		_:
			return ""

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
	# Build peer_id -> name map for combat-clause target lookup (Alpha
	# remediation Phase D D.3 §9.6).
	var name_by_pid: Dictionary = {}
	for row in scores:
		name_by_pid[int(row.get("peer_id", 0))] = String(row.get("name", "P?"))

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
		var combat_clause = _format_card_cannon_combat_clause(row, name_by_pid)
		if lscore == 21:
			lines.append("  %s locked %d%s %s%d chips%s (PERFECT!)" % [name, lscore, combat_clause, sign, delta, crown_suffix])
		else:
			lines.append("  %s locked %d%s %s%d chips%s" % [name, lscore, combat_clause, sign, delta, crown_suffix])

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
		var combat_clause = _format_card_cannon_combat_clause(row, name_by_pid)
		lines.append("  %s locked %d%s %s%d chips" % [name, lscore, combat_clause, sign, delta])

	# Busted players
	for row in scores:
		if not bool(row.get("busted", false)):
			continue
		var name = String(row.get("name", "P?"))
		var score = int(row.get("score", 0))
		var delta = int(row.get("chip_delta", 0))
		lines.append("  %s overloaded at %d (%d chips)" % [name, score, delta])

	return "\n".join(lines)

# Alpha remediation Phase D D.3 (§9.6): build the "hit <target> for <n>"
# clause for a Card Cannon scores_summary row. Returns "" if no attack
# fired (locked <= 10 or no eligible target).
static func _format_card_cannon_combat_clause(row: Dictionary, name_by_pid: Dictionary) -> String:
	var target_pid = int(row.get("target_peer_id", 0))
	var atk = int(row.get("attack_delta", 0))
	if target_pid == 0 or atk <= 0:
		return ""
	var target_name = String(name_by_pid.get(target_pid, "P%d" % target_pid))
	return ", hit %s for %d" % [target_name, atk]

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
