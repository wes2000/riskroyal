# CashOutCardDrawerTargetPicker: modal overlay shown when a cash_out-timing
# card requires a target peer. Presents active opponents as clickable buttons.
# MatchScene instantiates this into TargetPickerSlot and wires signals.
extends CenterContainer

signal target_chosen(target_peer_id)
signal cancelled

var controller  # MatchController-like
var local_peer_id: int = 0
var _pending_card_id: String = ""

@onready var _row: VBoxContainer = $Panel/VBox/Row if has_node("Panel/VBox/Row") else null
@onready var _cancel_button: Button = $Panel/VBox/CancelButton if has_node("Panel/VBox/CancelButton") else null

func _ready() -> void:
	visible = false
	if _cancel_button != null:
		_cancel_button.pressed.connect(_on_cancel)

func open_for_card(card_id: String, players: Array) -> void:
	_pending_card_id = card_id
	if _row != null:
		for child in _row.get_children():
			child.queue_free()
		var eligible = filter_eligible_targets(local_peer_id, players)
		for p in eligible:
			var btn := Button.new()
			btn.text = format_peer_button_label(str(p.get("name", p.peer_id)), int(p.get("chips", 0)))
			btn.pressed.connect(_on_peer_pressed.bind(int(p.peer_id)))
			_row.add_child(btn)
	visible = true

func _on_peer_pressed(peer_id: int) -> void:
	target_chosen.emit(peer_id)
	if controller != null:
		controller.submit_card_play(_pending_card_id, peer_id, null)
	visible = false

func _on_cancel() -> void:
	cancelled.emit()
	visible = false

# Static helpers (testable without scene)

static func format_peer_button_label(peer_name: String, chips: int) -> String:
	return "%s (%d chips)" % [peer_name, chips]

static func filter_eligible_targets(local_peer_id_: int, players: Array) -> Array:
	var out: Array = []
	for p in players:
		if not p.get("is_active_this_event", false):
			continue
		if int(p.peer_id) == local_peer_id_:
			continue
		out.append(p)
	return out
