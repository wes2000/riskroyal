# SettingsOverlay: modal panel for text-scale accessibility toggle.
# Three options: 1.0x (default), 1.25x, 1.5x.
# Selected scale applies via add_theme_font_size_override on the scene
# tree's root Control and persists to user://settings.cfg under
# [display]/text_scale via ConfigFile.
extends CenterContainer

const DEFAULT_CFG_PATH := "user://settings.cfg"
const CFG_SECTION := "display"
const CFG_KEY := "text_scale"
const BASE_FONT_SIZE := 16

@onready var _scale_1_0_button: Button = $PanelContainer/VBox/ScaleButtons/Scale1_0Button if has_node("PanelContainer/VBox/ScaleButtons/Scale1_0Button") else null
@onready var _scale_1_25_button: Button = $PanelContainer/VBox/ScaleButtons/Scale1_25Button if has_node("PanelContainer/VBox/ScaleButtons/Scale1_25Button") else null
@onready var _scale_1_5_button: Button = $PanelContainer/VBox/ScaleButtons/Scale1_5Button if has_node("PanelContainer/VBox/ScaleButtons/Scale1_5Button") else null
@onready var _close_button: Button = $PanelContainer/VBox/CloseButton if has_node("PanelContainer/VBox/CloseButton") else null

func _ready() -> void:
	visible = false
	if _scale_1_0_button != null:
		_scale_1_0_button.pressed.connect(_on_scale_chosen.bind(1.0))
	if _scale_1_25_button != null:
		_scale_1_25_button.pressed.connect(_on_scale_chosen.bind(1.25))
	if _scale_1_5_button != null:
		_scale_1_5_button.pressed.connect(_on_scale_chosen.bind(1.5))
	if _close_button != null:
		_close_button.pressed.connect(_on_close_pressed)

func open() -> void:
	visible = true

func _on_scale_chosen(scale: float) -> void:
	if get_tree() != null:
		apply_text_scale(scale, get_tree().root)
	persist_scale(scale)
	visible = false

func _on_close_pressed() -> void:
	visible = false

# Static helpers — entry points for unit tests without scene instantiation.

static func valid_scales() -> Array:
	return [1.0, 1.25, 1.5]

static func apply_text_scale(scale: float, root: Node) -> void:
	if root == null:
		return
	var size = int(round(BASE_FONT_SIZE * scale))
	for child in root.get_children():
		if child is Control:
			child.add_theme_font_size_override("font_size", size)

static func load_persisted_scale(path: String = DEFAULT_CFG_PATH) -> float:
	var cfg = ConfigFile.new()
	var err = cfg.load(path)
	if err != OK:
		return 1.0
	return float(cfg.get_value(CFG_SECTION, CFG_KEY, 1.0))

static func persist_scale(scale: float, path: String = DEFAULT_CFG_PATH) -> void:
	var cfg = ConfigFile.new()
	cfg.load(path)  # ignore err — creates fresh if missing
	cfg.set_value(CFG_SECTION, CFG_KEY, scale)
	cfg.save(path)
