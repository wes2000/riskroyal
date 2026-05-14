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
	# Sub-project #7 Plan B C4 fixup: in production, `players` is
	# Array[MatchPlayer] (Objects), not Array[Dictionary]. The previous
	# code called `p.get("name", p.peer_id)` / `p.get("chips", 0)` which
	# crashes on Object — Object.get(prop) is single-arg only. Switch to
	# the dual-mode helpers (_peer_*) that branch on Dictionary vs Object.
	_pending_card_id = card_id
	if _row != null:
		for child in _row.get_children():
			child.queue_free()
		var eligible = filter_eligible_targets(local_peer_id, players)
		for p in eligible:
			var btn := Button.new()
			btn.text = format_peer_button_label(_peer_name(p), _peer_chips(p))
			btn.pressed.connect(_on_peer_pressed.bind(_peer_id(p)))
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

# Sub-project #7 Plan B C4 fixup: dual-mode payload accessors. Tests pass
# Dictionary payloads; production passes MatchPlayer Objects. Both branches
# return native-typed primitives for callers.
static func _peer_id(p) -> int:
	if p is Dictionary:
		return int(p.get("peer_id", 0))
	return int(p.peer_id)

static func _peer_name(p) -> String:
	if p is Dictionary:
		return String(p.get("name", "P?"))
	return String(p.name)

static func _peer_chips(p) -> int:
	if p is Dictionary:
		return int(p.get("chips", 0))
	return int(p.chips)

static func _peer_active(p) -> bool:
	if p is Dictionary:
		return bool(p.get("is_active_this_event", false))
	return bool(p.is_active_this_event)

static func filter_eligible_targets(local_peer_id_: int, players: Array) -> Array:
	var out: Array = []
	for p in players:
		if not _peer_active(p):
			continue
		if _peer_id(p) == local_peer_id_:
			continue
		out.append(p)
	return out
