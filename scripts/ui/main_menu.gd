# Title screen with Host / Join buttons. The Join button opens an AcceptDialog
# for code entry. Auto-fires Host or Join when CLI flags are present
# (--host-locally / --join-code=CODE).
extends Control

const CliArgs = preload("res://scripts/util/cli_args.gd")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const PracticeSetupOverlayScene = preload("res://scenes/practice_setup.tscn")
const PracticeSession = preload("res://scripts/net/practice_session.gd")

var session  # NetSession-like; defaults to NetSessionMain.session

@onready var _host_button: Button = $VBoxContainer/HostButton if has_node("VBoxContainer/HostButton") else null
@onready var _join_button: Button = $VBoxContainer/JoinButton if has_node("VBoxContainer/JoinButton") else null
@onready var _practice_button: Button = $VBoxContainer/PracticeButton if has_node("VBoxContainer/PracticeButton") else null
@onready var _join_dialog: AcceptDialog = $JoinDialog if has_node("JoinDialog") else null
@onready var _code_input: LineEdit = $JoinDialog/CodeInput if has_node("JoinDialog/CodeInput") else null

func _ready() -> void:
	if session == null:
		if get_tree().root.has_node("NetSessionMain"):
			session = get_tree().root.get_node("NetSessionMain").session
	if session == null:
		push_warning("MainMenu has no session; UI buttons will be inert")
		return

	if _host_button != null:
		_host_button.pressed.connect(_on_host_pressed)
	if _join_button != null:
		_join_button.pressed.connect(_on_join_pressed)
	if _practice_button != null:
		_practice_button.pressed.connect(_on_practice_pressed)
	if _join_dialog != null:
		_join_dialog.confirmed.connect(_on_join_dialog_confirmed)
	session.state_changed.connect(_on_state_changed)

	# CLI flag handling for headless playtest runs.
	var args := CliArgs.from_cmdline()
	if args.host_locally:
		_on_host_pressed()
	elif args.join_code != "":
		_on_join_with_code(args.join_code)
	elif args.practice_locally:
		PracticeSession.start(args.practice_bots, args.practice_seed, get_tree())

func _on_host_pressed() -> void:
	session.host_session()

func _on_join_pressed() -> void:
	if _join_dialog != null:
		_join_dialog.popup_centered()

func _on_join_dialog_confirmed() -> void:
	var code := normalize_code_input(_code_input.text) if _code_input != null else ""
	if code != "":
		_on_join_with_code(code)

func _on_join_with_code(code: String) -> void:
	session.join_session(code)

func _on_practice_pressed() -> void:
	# Instantiate the Practice setup modal as a child of the main menu;
	# the overlay self-frees on Cancel and changes scene on Start.
	var overlay = PracticeSetupOverlayScene.instantiate()
	add_child(overlay)
	if overlay.has_method("popup_centered"):
		overlay.popup_centered()

func _on_state_changed(new_state: int) -> void:
	if new_state == NetSessionState.State.LOBBY:
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")

static func normalize_code_input(text: String) -> String:
	var trimmed := text.strip_edges().to_upper()
	if trimmed.length() != 6:
		return ""
	return trimmed
