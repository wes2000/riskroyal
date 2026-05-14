# Wager-input widget shown during BET_LOADOUT phase. Listens to
# MatchController.bet_loadout_started / bet_loadout_finished. Renders
# the local player's chips, a slider 0..max, a Ready button, and a
# countdown. On Ready, calls controller.submit_wager(amount).
extends PanelContainer

const MatchConfig = preload("res://scripts/match/match_config.gd")

@onready var _title_label: Label = $VBox/TitleLabel if has_node("VBox/TitleLabel") else null
@onready var _wager_slider: HSlider = $VBox/WagerSlider if has_node("VBox/WagerSlider") else null
@onready var _wager_spin: SpinBox = $VBox/WagerSpin if has_node("VBox/WagerSpin") else null
@onready var _ready_button: Button = $VBox/ReadyButton if has_node("VBox/ReadyButton") else null
@onready var _summary_label: Label = $VBox/SummaryLabel if has_node("VBox/SummaryLabel") else null
@onready var _countdown_label: Label = $VBox/CountdownLabel if has_node("VBox/CountdownLabel") else null
@onready var _readied_row: HBoxContainer = $VBox/ReadiedRow if has_node("VBox/ReadiedRow") else null

var controller  # MatchController-like (set by MatchScene)
var local_player  # MatchPlayer-like

var _readied: Array = []

func _ready() -> void:
	visible = false
	if controller != null:
		controller.bet_loadout_started.connect(_on_started)
		controller.bet_loadout_finished.connect(_on_finished)
		if controller.has_signal("bet_loadout_timer_tick"):
			controller.bet_loadout_timer_tick.connect(_on_timer_tick)
		if controller.has_signal("wager_acknowledged"):
			controller.wager_acknowledged.connect(_on_wager_acknowledged)
	if _ready_button != null:
		_ready_button.pressed.connect(_on_ready_pressed)
	if _wager_slider != null and _wager_spin != null:
		_wager_slider.value_changed.connect(_on_slider_changed)
		_wager_spin.value_changed.connect(_on_spin_changed)

func _on_started(_active_peer_ids: Array, max_per_player: int) -> void:
	_readied = []
	visible = true
	if local_player != null:
		if _wager_slider != null:
			_wager_slider.min_value = 0
			_wager_slider.max_value = max_per_player
			_wager_slider.value = 0
		if _wager_spin != null:
			_wager_spin.min_value = 0
			_wager_spin.max_value = max_per_player
			_wager_spin.value = 0
		_refresh_summary()

func _on_finished() -> void:
	visible = false

func _on_slider_changed(value: float) -> void:
	if _wager_spin != null and _wager_spin.value != value:
		_wager_spin.value = value
	_refresh_summary()

func _on_spin_changed(value: float) -> void:
	if _wager_slider != null and _wager_slider.value != value:
		_wager_slider.value = value
	_refresh_summary()

func _on_ready_pressed() -> void:
	if controller == null:
		return
	var amount = int(_wager_slider.value) if _wager_slider != null else 0
	controller.submit_wager(amount)
	if _ready_button != null:
		_ready_button.disabled = true

func _refresh_summary() -> void:
	if _summary_label == null or local_player == null:
		return
	var amount = int(_wager_slider.value) if _wager_slider != null else 0
	_summary_label.text = format_wager_summary(local_player.chips, amount)

func _on_timer_tick(seconds_remaining: int) -> void:
	if _countdown_label != null:
		_countdown_label.text = format_countdown(seconds_remaining)

func _on_wager_acknowledged(peer_id: int, _amount: int) -> void:
	if not (peer_id in _readied):
		_readied.append(peer_id)
	_rebuild_readied_row()

func _rebuild_readied_row() -> void:
	if _readied_row == null:
		return
	for child in _readied_row.get_children():
		child.queue_free()
	if controller == null or controller.state == null:
		return
	for p in controller.state.players:
		var lbl = Label.new()
		lbl.text = format_readied_chip(p.peer_id, _readied)
		_readied_row.add_child(lbl)

# Static formatters (testable)
static func format_wager_summary(chips: int, wager: int) -> String:
	return "Wager: %d (Chips: %d)" % [wager, chips]

static func clamp_wager(amount: int, chips: int, max_factor: float) -> int:
	var cap = int(chips * max_factor)
	return clamp(amount, 0, cap)

static func format_countdown(seconds_remaining: int) -> String:
	if seconds_remaining <= 0:
		return ""
	return "[%ds]" % seconds_remaining

static func format_readied_chip(peer_id: int, readied_peer_ids: Array) -> String:
	if peer_id in readied_peer_ids:
		return "✓ P%d" % peer_id
	return "P%d" % peer_id
