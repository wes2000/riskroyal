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

var controller  # MatchController-like (set by MatchScene)
var local_player  # MatchPlayer-like

func _ready() -> void:
	visible = false
	if controller != null:
		controller.bet_loadout_started.connect(_on_started)
		controller.bet_loadout_finished.connect(_on_finished)
	if _ready_button != null:
		_ready_button.pressed.connect(_on_ready_pressed)
	if _wager_slider != null and _wager_spin != null:
		_wager_slider.value_changed.connect(_on_slider_changed)
		_wager_spin.value_changed.connect(_on_spin_changed)

func _on_started(_active_peer_ids: Array, max_per_player: int) -> void:
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

# Static formatters (testable)
static func format_wager_summary(chips: int, wager: int) -> String:
	return "Wager: %d (Chips: %d)" % [wager, chips]

static func clamp_wager(amount: int, chips: int, max_factor: float) -> int:
	var cap = int(chips * max_factor)
	return clamp(amount, 0, cap)
