# CashOutCardDrawer: shown inside MatchScene during the rocket (MAIN_EVENT).
# Filters local loadout to cash_out-timing cards not yet played.
# Subscribes to MatchController.card_effect_applied (hide a card after play)
# and phase_changed (visibility toggle).
extends PanelContainer

const CardRegistry = preload("res://scripts/cards/card_registry.gd")

@onready var _row: HBoxContainer = $VBox/CardRow if has_node("VBox/CardRow") else null

var controller  # MatchController-like
var local_player

func _ready() -> void:
	visible = false
	if controller != null:
		controller.event_starting.connect(_on_event_starting)
		controller.card_effect_applied.connect(_on_card_effect_applied)
		controller.phase_changed.connect(_on_phase_changed)

func _on_event_starting(_event_id: String, _event_index: int) -> void:
	visible = true
	_refresh()

func _on_phase_changed(phase: int) -> void:
	# Hide when leaving MAIN_EVENT
	var MatchPhase = load("res://scripts/match/match_phase.gd")
	visible = (phase == MatchPhase.Phase.MAIN_EVENT)

func _on_card_effect_applied(peer_id: int, _card_id: String, _effect: Dictionary) -> void:
	if local_player != null and peer_id == local_player.peer_id:
		_refresh()

func _refresh() -> void:
	if _row == null or local_player == null:
		return
	for child in _row.get_children():
		child.queue_free()
	var playable = filter_loadout(local_player.loadout, local_player.played_this_event)
	for card_id in playable:
		var btn = Button.new()
		var card = CardRegistry.get_card(card_id)
		btn.text = String(card.get("name", card_id))
		btn.pressed.connect(_on_card_pressed.bind(card_id))
		_row.add_child(btn)

func _on_card_pressed(card_id: String) -> void:
	if controller == null:
		return
	# MVP: target_peer_id = 0 means UI defers to host's target_required reject.
	# Full target picker UI is a polish-pass item.
	controller.submit_card_play(card_id, 0, null)

# Static formatter (testable). Returns cash_out-timing cards from loadout
# that aren't in played_this_event. Unknown cards (not in registry) excluded.
static func filter_loadout(loadout: Array, played_this_event: Array) -> Array:
	var out: Array = []
	for card_id in loadout:
		if card_id in played_this_event:
			continue
		var card = CardRegistry.get_card(card_id)
		if card.is_empty():
			continue
		if card.get("timing", "") == "cash_out":
			out.append(card_id)
	return out
