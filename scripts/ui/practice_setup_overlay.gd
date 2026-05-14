# PracticeSetupOverlay: small modal for choosing bot count + optional
# seed before starting a Practice match. Wired by main_menu.gd which
# instantiates practice_setup.tscn and pops it centered. Start button
# delegates to PracticeSession.start() which handles the scene change.
extends Window

const PracticeSession = preload("res://scripts/net/practice_session.gd")

@onready var _bot_count_spin: SpinBox = $VBox/BotCountSpin if has_node("VBox/BotCountSpin") else null
@onready var _seed_input: LineEdit = $VBox/SeedInput if has_node("VBox/SeedInput") else null
@onready var _start_button: Button = $VBox/Buttons/StartButton if has_node("VBox/Buttons/StartButton") else null
@onready var _cancel_button: Button = $VBox/Buttons/CancelButton if has_node("VBox/Buttons/CancelButton") else null


func _ready() -> void:
	if _bot_count_spin != null:
		_bot_count_spin.min_value = 1
		_bot_count_spin.max_value = 7
		_bot_count_spin.value = 3
		_bot_count_spin.step = 1
	if _start_button != null:
		_start_button.pressed.connect(_on_start_pressed)
	if _cancel_button != null:
		_cancel_button.pressed.connect(_on_cancel_pressed)
	close_requested.connect(_on_cancel_pressed)


func _on_start_pressed() -> void:
	var bot_count: int = int(_bot_count_spin.value) if _bot_count_spin != null else 3
	var seed_text: String = _seed_input.text.strip_edges() if _seed_input != null else ""
	var seed: int = 0
	if seed_text != "":
		# int() returns 0 for non-numeric input, which falls back to the
		# time-based seed inside PracticeSession.build_match_start.
		seed = int(seed_text)
	PracticeSession.start(bot_count, seed, get_tree())


func _on_cancel_pressed() -> void:
	queue_free()
