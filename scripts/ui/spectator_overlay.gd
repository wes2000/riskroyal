# SpectatorOverlay: shown when the local player is in spectator mode
# (busted mid-match or dropped). Full-screen Control anchored to the
# right 40% of the viewport. Displays a sorted leaderboard, a per-event
# status panel (Task 12), and a match-progress label.
# Plan C Phase 3 Task 8: scene + script + leaderboard formatter.
# Task 12 adds the per-event status formatter; Task 13 polishes layout.
extends Control

@onready var _leaderboard_box: VBoxContainer = $Margin/VBox/LeaderboardBox if has_node("Margin/VBox/LeaderboardBox") else null
@onready var _event_status_label: Label = $Margin/VBox/EventStatusLabel if has_node("Margin/VBox/EventStatusLabel") else null
@onready var _progress_label: Label = $Margin/VBox/ProgressLabel if has_node("Margin/VBox/ProgressLabel") else null

var controller  # MatchController-like (set by MatchScene before _ready)

# Plan C Task 12: peer to watch for event-status polling.
var _watch_peer_id: int = 0

func _ready() -> void:
	visible = false
	if controller != null:
		controller.player_resources_changed.connect(_on_player_resources_changed)
		controller.crown_awarded.connect(_on_crown_awarded)
		controller.phase_changed.connect(_on_phase_changed)
	# Plan C Task 13: chat-friendly layout — larger fonts on leaderboard
	# rows so spectators can read the standings at a glance. Countdown
	# widgets are deliberately omitted from the spectator view (those are
	# play-context only).
	add_theme_font_size_override("font_size", 18)
	if _leaderboard_box != null:
		_leaderboard_box.add_theme_constant_override("separation", 8)

func _on_player_resources_changed(_peer_id: int) -> void:
	_refresh_leaderboard()

func _on_crown_awarded(_peer_id: int, _count: int) -> void:
	_refresh_leaderboard()

func _on_phase_changed(_phase: int) -> void:
	_refresh_progress()
	set_process(visible)

func _refresh_leaderboard() -> void:
	if _leaderboard_box == null or controller == null or controller.state == null:
		return
	for child in _leaderboard_box.get_children():
		child.queue_free()
	var rows = format_leaderboard(_players_as_dicts(controller.state.players))
	for row in rows:
		var lbl = Label.new()
		lbl.text = "#%d  %s  👑 %d  $%d" % [int(row.rank), String(row.display_name), int(row.crowns), int(row.chips)]
		# Plan C Task 13: larger leaderboard rows (theme polish).
		lbl.add_theme_font_size_override("font_size", 20)
		_leaderboard_box.add_child(lbl)

func _refresh_progress() -> void:
	if _progress_label == null or controller == null or controller.state == null:
		return
	_progress_label.text = "Event %d" % (int(controller.state.event_index) + 1)

func _players_as_dicts(players: Array) -> Array:
	var out: Array = []
	for p in players:
		if p is Dictionary:
			out.append(p)
		else:
			out.append({"peer_id": int(p.peer_id), "name": String(p.name), "crowns": int(p.crowns), "chips": int(p.chips)})
	return out

# Plan C Task 12: poll the active event's state each frame and update
# the EventStatusLabel. Only runs while visible (set_process tracks visibility).
func _process(_delta: float) -> void:
	if not visible or _event_status_label == null:
		return
	if controller == null or controller.state == null:
		return
	# Pick the first still-active peer to watch (deterministic seat order).
	var watched_name = "P?"
	for p in controller.state.players:
		if p.is_active_this_event:
			watched_name = p.name
			_watch_peer_id = int(p.peer_id)
			break
	# current_event_id is a String field on MatchState (not a method).
	# Plan-document-reviewer caught the stale has_method form; this
	# direct field access is the correct shape.
	var event_id = String(controller.state.current_event_id) if controller.state != null else ""
	var ctx_data = {"name": watched_name}
	if controller.has_method("get_spectator_ctx_data"):
		ctx_data = controller.get_spectator_ctx_data(_watch_peer_id)
	_event_status_label.text = format_event_status(event_id, ctx_data)

# Static formatter (testable without scene). Sorts by crowns desc, then
# chips desc. Returns rows with peer_id, display_name, crowns, chips, rank.
static func format_leaderboard(players: Array) -> Array:
	var rows: Array = []
	for p in players:
		var pid: int = int(p.get("peer_id", 0)) if p is Dictionary else int(p.peer_id)
		var pname: String = String(p.get("name", "P?")) if p is Dictionary else String(p.name)
		var crowns: int = int(p.get("crowns", 0)) if p is Dictionary else int(p.crowns)
		var chips: int = int(p.get("chips", 0)) if p is Dictionary else int(p.chips)
		rows.append({"peer_id": pid, "display_name": pname, "crowns": crowns, "chips": chips})
	rows.sort_custom(func(a, b):
		if int(a.crowns) != int(b.crowns):
			return int(a.crowns) > int(b.crowns)
		return int(a.chips) > int(b.chips))
	for i in range(rows.size()):
		rows[i]["rank"] = i + 1
	return rows

# Plan C Task 12: per-event spectator live status formatter.
# ctx_data shape is event-specific:
#   rocket_clash: { name: String, multiplier: float }
#   bomb_pot:     { name: String, bomb_remaining_sec: int }
#   card_cannon:  { name: String, locked_score: int, target_score: int }
# Unknown event_id returns empty.
static func format_event_status(event_id: String, ctx_data: Dictionary) -> String:
	if event_id == "rocket_clash":
		return "%s riding @ %.1fx" % [String(ctx_data.get("name", "P?")), float(ctx_data.get("multiplier", 0.0))]
	if event_id == "bomb_pot":
		return "%s in, %ds to bomb" % [String(ctx_data.get("name", "P?")), int(ctx_data.get("bomb_remaining_sec", 0))]
	if event_id == "card_cannon":
		return "%s score: %d/%d" % [String(ctx_data.get("name", "P?")), int(ctx_data.get("locked_score", 0)), int(ctx_data.get("target_score", 21))]
	return ""
