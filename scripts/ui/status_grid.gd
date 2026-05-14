# StatusGrid: per-peer status chips shown during MAIN_EVENT. Subscribes to
# MatchController.status_changed(peer_id, status_string) and updates the
# matching peer's chip in place. Static format_status() is event-id aware
# and returns the vocabulary string (IN/CASHED/BUSTED/PULLED/DRAWING/LOCKED).
# Pattern reference: scripts/ui/house_twist_overlay.gd (sub-project #6 Plan A).
extends PanelContainer

@onready var _row: HBoxContainer = $VBox/Row if has_node("VBox/Row") else null

var controller  # MatchController-like (set by MatchScene before _ready)
var _chips: Dictionary = {}  # peer_id -> Label node

func _ready() -> void:
	visible = false
	if controller != null:
		controller.event_starting.connect(_on_event_starting)
		controller.phase_changed.connect(_on_phase_changed)
		if controller.has_signal("status_changed"):
			controller.status_changed.connect(_on_status_changed)

func _on_event_starting(_event_id: String, _event_index: int) -> void:
	visible = true
	_rebuild()

func _on_phase_changed(phase: int) -> void:
	var MatchPhase = load("res://scripts/match/match_phase.gd")
	# Hide outside MAIN_EVENT (and SHOP / HOUSE_TWIST follow-on phases)
	visible = (phase == MatchPhase.Phase.MAIN_EVENT)

func _on_status_changed(peer_id: int, status_string: String) -> void:
	var lbl = _chips.get(peer_id, null)
	if lbl == null:
		return
	lbl.text = "P%d: %s" % [peer_id, status_string]

func _rebuild() -> void:
	if _row == null or controller == null or controller.state == null:
		return
	for child in _row.get_children():
		child.queue_free()
	_chips.clear()
	for p in controller.state.players:
		var lbl = Label.new()
		lbl.text = "P%d: IN" % p.peer_id
		_row.add_child(lbl)
		_chips[p.peer_id] = lbl

# Plan C Task 11: compact mode shrinks the widget for spectator-side
# rendering. The leaderboard takes the right 40% so the play widgets
# move to a narrow column at the top-left.
func set_compact(compact: bool) -> void:
	if compact:
		anchor_right = 0.6
		size_flags_horizontal = SIZE_SHRINK_BEGIN
	else:
		anchor_right = 1.0
		size_flags_horizontal = SIZE_EXPAND_FILL

# Static formatter (testable without scene)

static func format_status(event_id: String, peer_state: Dictionary) -> String:
	if event_id == "rocket_clash":
		if peer_state.get("busted", false):
			return "BUSTED"
		if peer_state.get("cashed_out", false):
			return "CASHED"
		return "IN"
	if event_id == "bomb_pot":
		if peer_state.get("busted", false):
			return "BUSTED"
		if peer_state.get("pulled_out", false):
			return "PULLED"
		return "IN"
	if event_id == "card_cannon":
		if peer_state.get("busted", false):
			return "BUSTED"
		if peer_state.get("locked", false):
			return "LOCKED"
		return "DRAWING"
	return ""
