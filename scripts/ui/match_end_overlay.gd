# Shown when MatchController.match_ended fires. Displays ranked players
# plus a Back-to-Lobby button (host-only) and a Quit button (everyone).
extends PanelContainer

@onready var _rankings_label: Label = $VBox/RankingsLabel if has_node("VBox/RankingsLabel") else null
@onready var _back_button: Button = $VBox/Buttons/BackToLobbyButton if has_node("VBox/Buttons/BackToLobbyButton") else null
@onready var _quit_button: Button = $VBox/Buttons/QuitButton if has_node("VBox/Buttons/QuitButton") else null

var controller  # MatchController-like
var is_host: bool = false

signal back_to_lobby_pressed
signal quit_pressed

func _ready() -> void:
	visible = false
	if controller != null:
		controller.match_ended.connect(_on_match_ended)
	if _back_button != null:
		_back_button.visible = is_host
		_back_button.pressed.connect(func(): back_to_lobby_pressed.emit())
	if _quit_button != null:
		_quit_button.pressed.connect(func(): quit_pressed.emit())

func _on_match_ended(rankings: Array) -> void:
	visible = true
	if _rankings_label != null:
		_rankings_label.text = format_match_end_rankings(rankings)

# Static formatter (testable)

static func format_match_end_rankings(rankings: Array) -> String:
	if rankings.is_empty():
		return "No rankings."
	var lines: Array = []
	for i in rankings.size():
		var p = rankings[i]
		var rank_label = "Winner: " if i == 0 else "%d. " % (i + 1)
		lines.append("%s%s — %d Crowns, %d chips, Heat %d" % [rank_label, p.name, p.crowns, p.chips, p.heat])
	return "\n".join(lines)
