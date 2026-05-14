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
var _active_tween: Tween = null

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

func _show(message: String, color: Color, _legacy_duration: float) -> void:
	if _message_label != null:
		_message_label.text = message
		_message_label.modulate = color
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	visible = true
	modulate.a = 1.0
	if color == BUST_COLOR:
		_run_bust_animation()
	else:
		_run_crown_animation()

func _run_bust_animation() -> void:
	var t = bust_animation_timeline()
	var start_pos = position
	scale = Vector2(0.0, 0.0)
	_active_tween = create_tween()
	_active_tween.tween_property(self, "scale", Vector2(1.2, 1.2), float(t.snap_in_sec)).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(self, "scale", Vector2(1.0, 1.0), float(t.settle_sec)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_active_tween.set_parallel(true)
	_active_tween.tween_property(self, "position:x", start_pos.x + 5.0, float(t.shake_sec) / 6.0).set_trans(Tween.TRANS_SINE)
	_active_tween.tween_property(self, "position:x", start_pos.x - 5.0, float(t.shake_sec) / 6.0).set_trans(Tween.TRANS_SINE).set_delay(float(t.shake_sec) / 6.0)
	_active_tween.tween_property(self, "position:x", start_pos.x + 5.0, float(t.shake_sec) / 6.0).set_trans(Tween.TRANS_SINE).set_delay(float(t.shake_sec) * 2.0 / 6.0)
	_active_tween.tween_property(self, "position:x", start_pos.x, float(t.shake_sec) / 6.0).set_trans(Tween.TRANS_SINE).set_delay(float(t.shake_sec) * 3.0 / 6.0)
	_active_tween.set_parallel(false)
	_active_tween.tween_interval(float(t.hold_sec) - float(t.shake_sec))
	_active_tween.tween_property(self, "modulate:a", 0.0, float(t.fade_sec))
	_active_tween.tween_callback(func(): visible = false)

func _run_crown_animation() -> void:
	var t = crown_animation_timeline()
	scale = Vector2(0.0, 0.0)
	rotation = deg_to_rad(-15.0)
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	_active_tween.tween_property(self, "scale", Vector2(1.0, 1.0), float(t.sparkle_sec)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(self, "rotation", deg_to_rad(15.0), float(t.sparkle_sec)).set_trans(Tween.TRANS_SINE)
	_active_tween.set_parallel(false)
	_active_tween.tween_property(self, "rotation", 0.0, 0.05)
	var leg = float(t.pulse_sec) / 4.0
	_active_tween.tween_property(self, "scale", Vector2(1.15, 1.15), leg)
	_active_tween.tween_property(self, "scale", Vector2(1.0, 1.0), leg)
	_active_tween.tween_property(self, "scale", Vector2(1.15, 1.15), leg)
	_active_tween.tween_property(self, "scale", Vector2(1.0, 1.0), leg)
	_active_tween.tween_property(self, "modulate:a", 0.0, float(t.fade_sec))
	_active_tween.tween_callback(func(): visible = false)

# Static formatters (testable without scene)

static func format_bust_reveal(peer_name: String, chip_loss: int) -> String:
	return "%s LOST $%d" % [peer_name, chip_loss]

static func format_crown_reveal(peer_name: String, count: int) -> String:
	return "%s +%d CROWN" % [peer_name, count]

static func crown_animation_timeline() -> Dictionary:
	return {
		"sparkle_sec": 0.2,
		"pulse_sec": 0.6,
		"fade_sec": 0.3,
		"total_sec": 0.2 + 0.6 + 0.3,
	}

# Plan C Task 5: bust animation timeline.
static func bust_animation_timeline() -> Dictionary:
	return {
		"snap_in_sec": 0.15,
		"settle_sec": 0.1,
		"shake_sec": 0.2,
		"hold_sec": 1.2,
		"fade_sec": 0.3,
		"total_sec": 0.15 + 0.1 + 1.2 + 0.3,
	}
