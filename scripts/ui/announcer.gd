# Announcer: top-of-screen banner for 4 key game moments:
# HOUSE TWIST, player ejection, Crown award, and match end.
# Queues messages so simultaneous triggers don't collide.
# Auto-dismiss after 3 seconds via Tween fade.
extends PanelContainer

const HouseTwistOverlay = preload("res://scripts/ui/house_twist_overlay.gd")

const DISPLAY_DURATION_SEC: float = 3.0

@onready var _message_label: Label = $VBox/MessageLabel if has_node("VBox/MessageLabel") else null

var controller  # MatchController-like

var _queue: Array = []
var _showing: bool = false

func _ready() -> void:
	visible = false
	if controller != null:
		controller.house_twist_announced.connect(_on_house_twist_announced)
		if controller.has_signal("player_busted"):
			controller.player_busted.connect(_on_player_busted)
		if controller.has_signal("crown_awarded"):
			controller.crown_awarded.connect(_on_crown_awarded)
		controller.match_ended.connect(_on_match_ended)

func _on_house_twist_announced(twist_dict: Dictionary) -> void:
	var msg = format_twist_text(twist_dict)
	if msg == "":
		return
	_enqueue(msg)

func _on_player_busted(peer_id: int, chip_loss: int) -> void:
	var peer_name = _name_for(peer_id)
	_enqueue(format_bust_text(peer_name, chip_loss))

func _on_crown_awarded(peer_id: int, count: int) -> void:
	var peer_name = _name_for(peer_id)
	_enqueue(format_crown_text(peer_name, count))

func _on_match_ended(rankings: Array) -> void:
	# Sub-project #7 Plan B C3 fixup: rankings[0] is a MatchPlayer Object
	# (see MatchController._process_match_end + _rpc_match_ended), not a
	# Dictionary nor an int. The previous code did `int(rankings[0])`
	# which silently produced 0 — the banner would always say "P0 WINS
	# THE MATCH!". Read peer_id + name directly off the Object, with a
	# defensive Dictionary fallback in case a test or future code path
	# serializes the rankings before re-emit.
	if rankings.is_empty():
		return
	var top = rankings[0]
	if top == null:
		return
	var winner_pid: int = 0
	var winner_name: String = ""
	if top is Dictionary:
		winner_pid = int(top.get("peer_id", 0))
		winner_name = String(top.get("name", _name_for(winner_pid)))
	else:
		winner_pid = int(top.peer_id)
		winner_name = String(top.name)
	_enqueue(format_match_outcome_text(winner_pid, winner_name))

func _name_for(peer_id: int) -> String:
	if controller == null:
		return "P%d" % peer_id
	if controller.state == null:
		return "P%d" % peer_id
	var p = controller.state.find_player(peer_id)
	if p == null:
		return "P%d" % peer_id
	return p.name

func _enqueue(message: String) -> void:
	_queue.append(message)
	if not _showing:
		_show_next()

func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		visible = false
		return
	_showing = true
	var msg: String = _queue.pop_front()
	if _message_label != null:
		_message_label.text = msg
	visible = true
	modulate.a = 1.0
	var tween = create_tween()
	tween.tween_interval(DISPLAY_DURATION_SEC * 0.75)
	tween.tween_property(self, "modulate:a", 0.0, DISPLAY_DURATION_SEC * 0.25)
	tween.tween_callback(_show_next)

# Static formatters (testable without scene)

static func format_twist_text(twist_dict: Dictionary) -> String:
	var title = HouseTwistOverlay.format_twist_title(twist_dict)
	if title == "":
		return ""
	return "HOUSE TWIST: %s!" % title

static func format_bust_text(peer_name: String, chip_loss: int) -> String:
	return "%s EJECTED! -%d chips" % [peer_name, chip_loss]

static func format_crown_text(peer_name: String, crown_count: int) -> String:
	if crown_count >= 2:
		return "%s WINS %d CROWNS!" % [peer_name, crown_count]
	return "%s WINS THE CROWN!" % peer_name

static func format_match_outcome_text(_winner_peer_id: int, winner_name: String) -> String:
	return "%s WINS THE MATCH!" % winner_name
