# LoadoutOverlay: card hand + loadout slot UI shown during BET_LOADOUT.
# Lives in MatchScene's LoadoutSlot. Subscribes to MatchController signals.
extends PanelContainer

const CardRegistry = preload("res://scripts/cards/card_registry.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")

@onready var _hand_row: HBoxContainer = $VBox/HandRow if has_node("VBox/HandRow") else null
@onready var _loadout_row: HBoxContainer = $VBox/LoadoutRow if has_node("VBox/LoadoutRow") else null
@onready var _hint_label: Label = $VBox/HintLabel if has_node("VBox/HintLabel") else null

var controller  # MatchController-like (set by MatchScene before _ready)
var local_player  # MatchPlayer-like

func _ready() -> void:
	visible = false
	if controller != null:
		controller.bet_loadout_started.connect(_on_bet_loadout_started)
		controller.bet_loadout_finished.connect(_on_bet_loadout_finished)
		controller.loadout_acknowledged.connect(_on_loadout_acknowledged)
		controller.card_effect_applied.connect(_on_card_effect_applied)
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
	# Scene-tree-dependent rendering — exercised by integration tests + playtest.
	# MVP: a placeholder hint label updates with hand size.
	if _hint_label != null and local_player != null:
		_hint_label.text = "Hand: %d / Loadout: %d" % [local_player.hand.size(), local_player.loadout.size()]

# Static formatters (testable without scene)

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
