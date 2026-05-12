# Lobby scene. Renders 8 player-slot widgets, hosts the code display,
# wires local-player controls (name/color/ready), and shows the pause
# overlay when state == PAUSED. Host-only Start + Kick buttons added
# in later tasks.
extends Control

const MAX_SLOTS := 8
const NetSessionState = preload("res://scripts/data/net_session_state.gd")

var session  # NetSession-like

@onready var _code_label: Label = $VBoxContainer/CodeLabel if has_node("VBoxContainer/CodeLabel") else null
@onready var _slot_container: HBoxContainer = $VBoxContainer/SlotContainer if has_node("VBoxContainer/SlotContainer") else null
@onready var _name_input: LineEdit = $VBoxContainer/LocalPanel/NameInput if has_node("VBoxContainer/LocalPanel/NameInput") else null
@onready var _color_picker: OptionButton = $VBoxContainer/LocalPanel/ColorPicker if has_node("VBoxContainer/LocalPanel/ColorPicker") else null
@onready var _ready_check: CheckBox = $VBoxContainer/LocalPanel/ReadyCheck if has_node("VBoxContainer/LocalPanel/ReadyCheck") else null
@onready var _start_button: Button = $VBoxContainer/HostControls/StartButton if has_node("VBoxContainer/HostControls/StartButton") else null

func _ready() -> void:
	if session == null:
		if get_tree().root.has_node("NetSessionMain"):
			session = get_tree().root.get_node("NetSessionMain").session
	if session == null:
		push_warning("Lobby has no session")
		return

	session.players_changed.connect(_refresh)
	session.state_changed.connect(_on_state_changed)
	session.match_starting.connect(_on_match_starting)

	_refresh()

	if _name_input != null:
		_name_input.text_submitted.connect(_on_name_submitted)
	if _color_picker != null:
		_color_picker.item_selected.connect(_on_color_picked)
	if _ready_check != null:
		_ready_check.toggled.connect(_on_ready_toggled)
	if _start_button != null:
		_start_button.pressed.connect(_on_start_pressed)

func _refresh() -> void:
	if _code_label != null and session.is_host:
		_code_label.text = "Code: %s" % session.code
		_code_label.visible = true
	elif _code_label != null:
		_code_label.visible = false

	if _slot_container == null:
		return
	# Render exactly MAX_SLOTS labels; fill from session.players, blank rest.
	for i in MAX_SLOTS:
		var label_node: Label = _slot_container.get_node_or_null("Slot%d" % i)
		if label_node == null:
			continue
		var slot = session.players[i] if i < session.players.size() else null
		label_node.text = format_slot_label(slot)

	_refresh_host_controls()

func _refresh_host_controls() -> void:
	if _start_button == null:
		return
	_start_button.visible = should_show_start_button(session)
	_start_button.disabled = not is_start_button_enabled(session)

func _on_state_changed(_new_state: int) -> void:
	pass  # filled in by Task 8 (pause overlay)

func _on_match_starting(_match_start) -> void:
	get_tree().change_scene_to_file("res://scenes/placeholder_match.tscn")

func _on_name_submitted(value: String) -> void:
	session.set_name(value)

func _on_color_picked(index: int) -> void:
	session.set_color(index)

func _on_ready_toggled(pressed: bool) -> void:
	session.set_ready(pressed)

func _on_start_pressed() -> void:
	session.start_match()

func _on_kick_pressed(peer_id: int) -> void:
	session.kick(peer_id)

static func should_show_start_button(session) -> bool:
	return session != null and session.is_host

static func is_start_button_enabled(session) -> bool:
	if session == null:
		return false
	if not session.is_host:
		return false
	if session.players.size() < 2:
		return false
	for p in session.players:
		if not p.ready:
			return false
	return true

static func format_slot_label(slot) -> String:
	if slot == null:
		return "(empty)"
	var parts: Array = []
	parts.append(slot.name if not slot.name.is_empty() else "(unnamed)")
	if slot.is_host:
		parts.append("(host)")
	parts.append("color %d" % slot.color_index)
	if slot.ready:
		parts.append("READY")
	if not slot.connected:
		parts.append("disconnected")
	return " ".join(parts)
