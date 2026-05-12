# The match scene. Replaces sub-project #1's placeholder_match.tscn in the
# Lobby → Match transition. Builds and owns a MatchController, populates
# 8 PlayerPanel widgets, drives the PhaseIndicator, loads the current
# event into EventSlot, and shows ResolutionOverlay / MatchEndOverlay /
# PauseOverlay reactively.
extends Control

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")
const PlayerPanelScene = preload("res://scenes/ui/player_panel.tscn")
const ResolutionOverlayScene = preload("res://scenes/ui/resolution_overlay.tscn")
const MatchEndOverlayScene = preload("res://scenes/ui/match_end_overlay.tscn")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")

@onready var _player_panels: HBoxContainer = $VBox/PlayerPanels if has_node("VBox/PlayerPanels") else null
@onready var _phase_indicator: Label = $VBox/PhaseIndicator if has_node("VBox/PhaseIndicator") else null
@onready var _event_slot: Container = $VBox/EventSlot if has_node("VBox/EventSlot") else null
@onready var _resolution_slot: Container = $VBox/ResolutionSlot if has_node("VBox/ResolutionSlot") else null
@onready var _match_end_slot: Container = $VBox/MatchEndSlot if has_node("VBox/MatchEndSlot") else null
@onready var _pause_overlay: PanelContainer = $PauseOverlay if has_node("PauseOverlay") else null

var session  # NetSession-like
var controller: MatchController = null
var _current_event_scene: Node = null

func _ready() -> void:
	if session == null and get_tree().root.has_node("NetSessionMain"):
		session = get_tree().root.get_node("NetSessionMain").session
	if session == null:
		push_warning("MatchScene has no session")
		return
	var match_start = _read_match_start()
	if match_start == null:
		push_error("MatchScene: no MatchStart available; cannot run match")
		return
	controller = MatchController.new(session.is_host, self)
	add_child(controller)
	controller.phase_changed.connect(_on_phase_changed)
	controller.event_starting.connect(_on_event_starting)
	controller.match_ended.connect(_on_match_ended)
	controller.request_return_to_lobby.connect(_on_request_return_to_lobby)
	session.state_changed.connect(_on_session_state_changed)
	_build_player_panels(match_start)
	_build_overlays()
	if session.is_host:
		controller.start_match(match_start)

func _read_match_start():
	if not get_tree().root.has_node("NetSessionMain"):
		return null
	var nsm = get_tree().root.get_node("NetSessionMain")
	if not nsm.has_method("get_last_match_start"):
		return null
	return nsm.get_last_match_start()

func _build_player_panels(match_start) -> void:
	if _player_panels == null:
		return
	for seat in match_start.seats:
		var panel = PlayerPanelScene.instantiate()
		panel.controller = controller
		_player_panels.add_child(panel)
		panel.set_peer(seat.peer_id)

func _build_overlays() -> void:
	if _resolution_slot != null:
		var ro = ResolutionOverlayScene.instantiate()
		ro.controller = controller
		_resolution_slot.add_child(ro)
	if _match_end_slot != null:
		var meo = MatchEndOverlayScene.instantiate()
		meo.controller = controller
		meo.is_host = session.is_host
		meo.back_to_lobby_pressed.connect(_on_back_to_lobby_pressed)
		meo.quit_pressed.connect(_on_quit_pressed)
		_match_end_slot.add_child(meo)

func _on_phase_changed(phase: int) -> void:
	if _phase_indicator != null:
		_phase_indicator.text = format_phase_indicator(controller.state.event_index, MatchConfig.QUICK_CLASH_EVENT_COUNT, phase)

func _on_event_starting(event_id: String, _event_index: int) -> void:
	_unload_current_event()
	if _event_slot == null:
		return
	var ps = load(event_id)
	if ps == null:
		push_warning("Failed to load event: %s" % event_id)
		return
	_current_event_scene = ps.instantiate()
	_event_slot.add_child(_current_event_scene)

func _unload_current_event() -> void:
	if _current_event_scene == null:
		return
	_current_event_scene.queue_free()
	_current_event_scene = null

func _on_match_ended(_rankings) -> void:
	_unload_current_event()

func _on_session_state_changed(state: int) -> void:
	if _pause_overlay != null:
		_pause_overlay.visible = (state == NetSessionState.State.PAUSED)
	if controller != null:
		if state == NetSessionState.State.PAUSED:
			controller.pause()
		else:
			controller.resume()

func _on_back_to_lobby_pressed() -> void:
	if session.is_host:
		session.return_to_lobby()       # NetSession state transition
		controller.return_to_lobby()    # broadcasts _rpc_return_to_lobby to remote peers
		# _rpc_return_to_lobby is "call_remote" so the host itself doesn't
		# receive it. Fire the local handler directly so the host's scene
		# also swaps back to Lobby.
		_on_request_return_to_lobby()

func _on_request_return_to_lobby() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_quit_pressed() -> void:
	session.leave_session()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# Static formatter (testable). Takes total_events as a parameter so the
# caller chooses the count (production passes MatchConfig.QUICK_CLASH_EVENT_COUNT).
static func format_phase_indicator(event_index: int, total_events: int, phase: int) -> String:
	if phase == MatchPhase.Phase.MATCH_END:
		return "Match End"
	var phase_name = MatchPhase.name_for(phase)
	return "Event %d/%d: %s" % [event_index + 1, total_events, phase_name]
