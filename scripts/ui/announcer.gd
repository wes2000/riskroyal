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
var _active_tween: Tween = null

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
	# Alpha remediation Phase F §12.3: resolve the target's display name
	# from state so the callout reads e.g. "HOUSE TWIST: Leader Cursed —
	# Maya's next reward is cut." Untargeted twists pass "" through.
	var params = twist_dict.get("params", {})
	var target_pid = int(params.get("target_peer_id", 0))
	var target_name = "" if target_pid == 0 else _name_for(target_pid)
	var msg = format_twist_text(twist_dict, target_name)
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

# Plan C Task 11: compact mode shrinks the banner to the left 60%
# so the spectator leaderboard on the right 40% isn't occluded.
func set_compact(compact: bool) -> void:
	if compact:
		anchor_right = 0.6
	else:
		anchor_right = 1.0

func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		visible = false
		return
	_showing = true
	var msg: String = _queue.pop_front()
	if _message_label != null:
		_message_label.text = msg
	# Plan C Task 4: sequenced slide-in + bounce + slide-out.
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	visible = true
	modulate.a = 1.0
	position.y = -100.0
	var t = animation_timeline()
	_active_tween = create_tween()
	_active_tween.tween_property(self, "position:y", 0.0, float(t.slide_in_sec)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_tween.tween_interval(float(t.hold_sec))
	_active_tween.set_parallel(true)
	_active_tween.tween_property(self, "position:y", -100.0, float(t.slide_out_sec))
	_active_tween.tween_property(self, "modulate:a", 0.0, float(t.slide_out_sec))
	_active_tween.set_parallel(false)
	_active_tween.tween_callback(_show_next)

# Static formatters (testable without scene)

static func format_twist_text(twist_dict: Dictionary, target_name: String = "") -> String:
	var title = HouseTwistOverlay.format_twist_title(twist_dict)
	if title == "":
		return ""
	# Alpha remediation Phase F §12.3: targeted twists get a "— <Name>'s …"
	# suffix derived from the subtitle's second sentence. Untargeted twists
	# keep the legacy "HOUSE TWIST: <Title>!" form.
	var subtitle = HouseTwistOverlay.format_twist_subtitle(twist_dict, target_name)
	var second_sentence = _second_sentence(subtitle)
	if target_name != "" and second_sentence != "":
		return "HOUSE TWIST: %s — %s" % [title, second_sentence]
	return "HOUSE TWIST: %s!" % title

# Returns everything after the first sentence-ending period, trimmed.
# "Leader Cursed. Maya's next reward is cut." → "Maya's next reward is cut."
# "Leader Cursed." (title-only fallback) → "".
static func _second_sentence(subtitle: String) -> String:
	var idx = subtitle.find(". ")
	if idx < 0:
		return ""
	return subtitle.substr(idx + 2).strip_edges()

static func format_bust_text(peer_name: String, chip_loss: int) -> String:
	return "✗ %s EJECTED! -%d chips" % [peer_name, chip_loss]

static func format_crown_text(peer_name: String, crown_count: int) -> String:
	if crown_count >= 2:
		return "👑 %s WINS %d CROWNS!" % [peer_name, crown_count]
	return "👑 %s WINS THE CROWN!" % peer_name

static func format_match_outcome_text(_winner_peer_id: int, winner_name: String) -> String:
	return "%s WINS THE MATCH!" % winner_name

# Plan C Task 4: animation timeline durations exposed as a Dictionary
# so unit tests can assert the stage lengths without running a real Tween.
static func animation_timeline() -> Dictionary:
	return {
		"slide_in_sec": 0.3,
		"hold_sec": 2.5,
		"slide_out_sec": 0.3,
		"total_sec": 0.3 + 2.5 + 0.3,
	}
