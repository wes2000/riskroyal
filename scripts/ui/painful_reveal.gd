# PainfulReveal: animated text overlay for bust and crown moments.
# Bust shows in RED for 2 seconds; Crown shows in GOLD for 1.5 seconds.
# Uses Godot's Tween for modulate.a fade — no SFX (Plan C handles audio).
extends Control

const BUST_COLOR: Color = Color(1.0, 0.2, 0.2, 1.0)
const CROWN_COLOR: Color = Color(1.0, 0.85, 0.0, 1.0)

const BUST_DURATION: float = 2.0
const CROWN_DURATION: float = 1.5

@onready var _message_label: Label = $MessageLabel if has_node("MessageLabel") else null

var controller  # MatchController-like

func _ready() -> void:
	visible = false
	if controller != null:
		controller.player_busted.connect(_on_player_busted)
		controller.crown_awarded.connect(_on_crown_awarded)

func _on_player_busted(peer_id: int, chip_loss: int) -> void:
	var peer_name = _name_for(peer_id)
	_show(format_bust_reveal(peer_name, chip_loss), BUST_COLOR, BUST_DURATION)

func _on_crown_awarded(peer_id: int, count: int) -> void:
	var peer_name = _name_for(peer_id)
	_show(format_crown_reveal(peer_name, count), CROWN_COLOR, CROWN_DURATION)

func _name_for(peer_id: int) -> String:
	if controller == null:
		return "P%d" % peer_id
	if controller.state == null:
		return "P%d" % peer_id
	var p = controller.state.find_player(peer_id)
	if p == null:
		return "P%d" % peer_id
	return p.name

func _show(message: String, color: Color, duration: float) -> void:
	if _message_label != null:
		_message_label.text = message
		_message_label.modulate = color
	visible = true
	modulate.a = 0.0
	var fade_in = duration * 0.25
	var hold = duration * 0.5
	var fade_out = duration * 0.25
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, fade_in)
	tween.tween_interval(hold)
	tween.tween_property(self, "modulate:a", 0.0, fade_out)
	tween.tween_callback(func(): visible = false)

# Static formatters (testable without scene)

static func format_bust_reveal(peer_name: String, chip_loss: int) -> String:
	return "%s LOST $%d" % [peer_name, chip_loss]

static func format_crown_reveal(peer_name: String, count: int) -> String:
	return "%s +%d CROWN" % [peer_name, count]
