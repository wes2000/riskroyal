# LoadoutOverlay: card hand + loadout slot UI shown during BET_LOADOUT.
# Lives in MatchScene's LoadoutSlot. Subscribes to MatchController signals.
# Supports drag-to-loadout: hand row cards are draggable; LoadoutSlot0 and
# LoadoutSlot1 accept drops via set_drag_forwarding.
extends PanelContainer

signal loadout_changed(slot_index, card_id)

const CardRegistry = preload("res://scripts/cards/card_registry.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")

@onready var _hand_row: HBoxContainer = $VBox/HandRow if has_node("VBox/HandRow") else null
@onready var _loadout_row: HBoxContainer = $VBox/LoadoutRow if has_node("VBox/LoadoutRow") else null
@onready var _slot_0: PanelContainer = $VBox/LoadoutRow/LoadoutSlot0 if has_node("VBox/LoadoutRow/LoadoutSlot0") else null
@onready var _slot_1: PanelContainer = $VBox/LoadoutRow/LoadoutSlot1 if has_node("VBox/LoadoutRow/LoadoutSlot1") else null
@onready var _hint_label: Label = $VBox/HintLabel if has_node("VBox/HintLabel") else null

var controller  # MatchController-like (set by MatchScene before _ready)
var local_player  # MatchPlayer-like

func _ready() -> void:
	visible = false
	if _slot_0 != null:
		_slot_0.set_drag_forwarding(
			Callable(),
			_can_drop_data_slot.bind(0),
			_drop_data_slot.bind(0)
		)
	if _slot_1 != null:
		_slot_1.set_drag_forwarding(
			Callable(),
			_can_drop_data_slot.bind(1),
			_drop_data_slot.bind(1)
		)
	if controller != null:
		if controller.has_signal("bet_loadout_started"):
			controller.bet_loadout_started.connect(_on_bet_loadout_started)
		if controller.has_signal("bet_loadout_finished"):
			controller.bet_loadout_finished.connect(_on_bet_loadout_finished)
		if controller.has_signal("loadout_acknowledged"):
			controller.loadout_acknowledged.connect(_on_loadout_acknowledged)
		if controller.has_signal("card_effect_applied"):
			controller.card_effect_applied.connect(_on_card_effect_applied)
		if controller.has_signal("card_play_rejected"):
			controller.card_play_rejected.connect(_on_card_play_rejected)

func _on_bet_loadout_started(_active_peer_ids: Array, _max_per_player: int) -> void:
	visible = true
	_refresh()

func _on_bet_loadout_finished() -> void:
	visible = false

func _on_loadout_acknowledged(peer_id: int, _loadout: Array) -> void:
	if local_player != null and peer_id == local_player.peer_id:
		_refresh()

func _on_card_effect_applied(peer_id: int, _card_id: String, _effect: Dictionary) -> void:
	if local_player != null and peer_id == local_player.peer_id:
		_refresh()

func _on_card_play_rejected(_card_id: String, _reason: String) -> void:
	_refresh()

func _refresh() -> void:
	if _hand_row != null and local_player != null:
		for child in _hand_row.get_children():
			child.queue_free()
		for card_id in local_player.hand:
			var btn := Button.new()
			var card = CardRegistry.get_card(card_id)
			btn.text = String(card.get("name", card_id))
			btn.set_meta("card_id", card_id)
			btn.set_drag_forwarding(
				_get_drag_data_card.bind(btn),
				Callable(),
				Callable()
			)
			_hand_row.add_child(btn)
	if _hint_label != null and local_player != null:
		_hint_label.text = "Hand: %d / Loadout: %d" % [local_player.hand.size(), local_player.loadout.size()]

func _get_drag_data_card(_at_position: Vector2, btn: Button) -> Variant:
	return String(btn.get_meta("card_id", ""))

func _can_drop_data_slot(_at_position: Vector2, data: Variant, slot_index: int) -> bool:
	if local_player == null:
		return false
	return can_drop_card(str(data), local_player.hand)

func _drop_data_slot(_at_position: Vector2, data: Variant, slot_index: int) -> void:
	if local_player == null:
		return
	var card_id := str(data)
	var new_loadout = apply_drop(local_player.loadout, slot_index, card_id)
	loadout_changed.emit(slot_index, card_id)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var full: Color = Color(1.2, 1.2, 1.2, 1.0)
		if _slot_0 != null:
			_slot_0.modulate = full
		if _slot_1 != null:
			_slot_1.modulate = full
	elif what == NOTIFICATION_DRAG_END:
		var normal: Color = Color(1.0, 1.0, 1.0, 1.0)
		if _slot_0 != null:
			_slot_0.modulate = normal
		if _slot_1 != null:
			_slot_1.modulate = normal

# Static helpers (testable without scene)

static func can_drop_card(payload: String, valid_hand_ids: Array) -> bool:
	if payload == "":
		return false
	return payload in valid_hand_ids

static func apply_drop(loadout: Array, slot_index: int, card_id: String) -> Array:
	var out: Array = loadout.duplicate()
	while out.size() <= slot_index:
		out.append("")
	out[slot_index] = card_id
	return out

static func format_card_label(card_id: String) -> String:
	var card = CardRegistry.get_card(card_id)
	return String(card.get("name", "?"))

static func is_card_playable(card_id: String, phase: int, played_this_event: Array) -> bool:
	if card_id in played_this_event:
		return false
	var card = CardRegistry.get_card(card_id)
	var timing = card.get("timing", "")
	if timing == "bet_loadout" and phase == MatchPhase.Phase.BET_LOADOUT:
		return true
	if timing == "cash_out" and phase == MatchPhase.Phase.MAIN_EVENT:
		return true
	return false

static func available_targets(local_peer_id: int, players: Array, card_meta: Dictionary) -> Array:
	if not card_meta.get("target_required", false):
		return []
	var out: Array = []
	for p in players:
		if not p.is_active_this_event:
			continue
		if p.peer_id == local_peer_id:
			continue  # MVP: no self-target
		out.append(p.peer_id)
	return out
