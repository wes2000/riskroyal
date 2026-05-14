# EventPickerOverlay: shown during EVENT_SELECTION when the active twist
# is lowest_chips_picks. Picker peer sees 3 buttons + countdown; non-picker
# peers see a passive waiting banner. Hides on event_picker_resolved.
extends PanelContainer

const MatchConfig = preload("res://scripts/match/match_config.gd")

@onready var _picker_row: HBoxContainer = $VBox/PickerRow if has_node("VBox/PickerRow") else null
@onready var _waiting_label: Label = $VBox/WaitingLabel if has_node("VBox/WaitingLabel") else null
@onready var _countdown_label: Label = $VBox/CountdownLabel if has_node("VBox/CountdownLabel") else null

var controller  # MatchController-like
var local_player  # MatchPlayer-like (has peer_id)
var _is_picker: bool = false
var _options: Array = []
var _picker_peer_id: int = 0

var _deadline_ms: int = 0
var _active: bool = false

func _ready() -> void:
	visible = false
	if controller != null:
		controller.event_picker_started.connect(_on_event_picker_started)
		controller.event_picker_resolved.connect(_on_event_picker_resolved)

func _on_event_picker_started(picker_peer_id: int, options: Array) -> void:
	_picker_peer_id = picker_peer_id
	_options = options
	var local_peer_id = local_player.peer_id if local_player != null else 0
	_is_picker = (local_peer_id == picker_peer_id)
	_rebuild_buttons()
	_refresh_waiting_label()
	visible = true
	# Sub-project #7 Plan B Task 4: start countdown.
	_deadline_ms = Time.get_ticks_msec() + int(MatchConfig.EVENT_PICKER_TIMEOUT_SEC) * 1000
	_active = true
	set_process(true)

func _on_event_picker_resolved(_chosen_path: String, _reason: String) -> void:
	visible = false
	_options = []
	_active = false
	set_process(false)
	if _countdown_label != null:
		_countdown_label.text = ""

func _process(_delta: float) -> void:
	if not _active or _countdown_label == null:
		return
	var remaining_ms = max(0, _deadline_ms - Time.get_ticks_msec())
	var remaining_sec = int(ceil(remaining_ms / 1000.0))
	_countdown_label.text = format_countdown(remaining_sec)

func _rebuild_buttons() -> void:
	if _picker_row == null:
		return
	for child in _picker_row.get_children():
		child.queue_free()
	if not _is_picker:
		_picker_row.visible = false
		return
	_picker_row.visible = true
	for event_id in _options:
		var btn = Button.new()
		btn.text = format_event_button_label(event_id)
		btn.pressed.connect(func(): _on_pick_pressed(event_id))
		_picker_row.add_child(btn)

func _on_pick_pressed(chosen_path: String) -> void:
	if controller != null:
		controller.submit_event_pick(chosen_path)
	# Optimistically disable further presses; controller broadcast
	# event_picker_resolved will hide the overlay.
	if _picker_row != null:
		for child in _picker_row.get_children():
			if child is Button:
				child.disabled = true

func _refresh_waiting_label() -> void:
	if _waiting_label == null:
		return
	if _is_picker:
		_waiting_label.text = ""
		_waiting_label.visible = false
	else:
		_waiting_label.visible = true
		var picker_name = _picker_name_from_controller()
		_waiting_label.text = format_waiting_banner(picker_name)

func _picker_name_from_controller() -> String:
	if controller == null or controller.state == null:
		return ""
	var p = controller.state.find_player(_picker_peer_id)
	return p.name if p != null else ""

# Static formatters (testable without scene)

static func format_event_button_label(event_id: String) -> String:
	if event_id.ends_with("rocket_clash_event.tscn"):
		return "Rocket Clash"
	if event_id.ends_with("bomb_pot_event.tscn"):
		return "Bomb Pot"
	if event_id.ends_with("card_cannon_event.tscn"):
		return "Card Cannon"
	return ""

static func format_waiting_banner(picker_name: String) -> String:
	if picker_name.is_empty():
		return "Waiting for the picker to choose..."
	return "Waiting for %s to pick the next event..." % picker_name

static func format_countdown(seconds_remaining: int) -> String:
	if seconds_remaining <= 0:
		return ""
	return "[%ds]" % seconds_remaining
