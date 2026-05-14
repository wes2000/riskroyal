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
const BetLoadoutOverlayScene = preload("res://scenes/ui/bet_loadout_overlay.tscn")
const LoadoutOverlayScene = preload("res://scenes/ui/loadout_overlay.tscn")
const ShopOverlayScene = preload("res://scenes/ui/shop_overlay.tscn")
const BountyPanelScene = preload("res://scenes/ui/bounty_panel.tscn")
const CashOutCardDrawerScene = preload("res://scenes/ui/cash_out_card_drawer.tscn")
const CashOutCardDrawerTargetPickerScene = preload("res://scenes/ui/cash_out_card_drawer_target_picker.tscn")
const HouseTwistOverlayScene = preload("res://scenes/ui/house_twist_overlay.tscn")
const EventPickerOverlayScene = preload("res://scenes/ui/event_picker_overlay.tscn")
const StatusGridScene = preload("res://scenes/ui/status_grid.tscn")
const AnnouncerScene = preload("res://scenes/ui/announcer.tscn")
const PainfulRevealScene = preload("res://scenes/ui/painful_reveal.tscn")
const SpectatorOverlayScene = preload("res://scenes/ui/spectator_overlay.tscn")
const SettingsOverlayScene = preload("res://scenes/ui/settings_overlay.tscn")
const SettingsOverlay = preload("res://scripts/ui/settings_overlay.gd")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")

@onready var _player_panels: HBoxContainer = $VBox/PlayerPanels if has_node("VBox/PlayerPanels") else null
@onready var _phase_indicator: Label = $VBox/PhaseIndicator if has_node("VBox/PhaseIndicator") else null
@onready var _event_slot: Container = $VBox/EventSlot if has_node("VBox/EventSlot") else null
@onready var _resolution_slot: Container = $VBox/ResolutionSlot if has_node("VBox/ResolutionSlot") else null
@onready var _match_end_slot: Container = $VBox/MatchEndSlot if has_node("VBox/MatchEndSlot") else null
@onready var _bet_loadout_slot: Container = $VBox/BetLoadoutSlot if has_node("VBox/BetLoadoutSlot") else null
@onready var _loadout_slot: Container = $VBox/LoadoutSlot if has_node("VBox/LoadoutSlot") else null
@onready var _shop_slot: Container = $VBox/ShopSlot if has_node("VBox/ShopSlot") else null
@onready var _bounty_slot: Container = $VBox/BountyPanelSlot if has_node("VBox/BountyPanelSlot") else null
@onready var _house_twist_slot: Container = $VBox/HouseTwistSlot if has_node("VBox/HouseTwistSlot") else null
@onready var _event_picker_slot: Container = $VBox/EventPickerSlot if has_node("VBox/EventPickerSlot") else null
@onready var _cash_out_slot: Container = $VBox/CashOutSlot if has_node("VBox/CashOutSlot") else null
@onready var _target_picker_slot: Container = $VBox/TargetPickerSlot if has_node("VBox/TargetPickerSlot") else null
@onready var _status_grid_slot: Container = $VBox/StatusGridSlot if has_node("VBox/StatusGridSlot") else null
@onready var _announcer_slot: Container = $VBox/AnnouncerSlot if has_node("VBox/AnnouncerSlot") else null
@onready var _painful_reveal_slot: Container = $VBox/PainfulRevealSlot if has_node("VBox/PainfulRevealSlot") else null
@onready var _spectator_slot: Container = $VBox/SpectatorSlot if has_node("VBox/SpectatorSlot") else null
@onready var _settings_slot: Container = $SettingsSlot if has_node("SettingsSlot") else null
@onready var _settings_button: Button = $SettingsButton if has_node("SettingsButton") else null
@onready var _pause_overlay: PanelContainer = $PauseOverlay if has_node("PauseOverlay") else null

var session  # NetSession-like
var controller: MatchController = null
var _current_event_scene: Node = null
var _bet_loadout_overlay: Node = null
var _loadout_overlay: Node = null
var _shop_overlay: Node = null
var _bounty_panel: Node = null
var _cash_out_drawer: Node = null
var _house_twist_overlay: Node = null
var _event_picker_overlay: Node = null
var _target_picker: Node = null
var _status_grid: Node = null
var _announcer: Node = null
var _painful_reveal: Node = null
var _spectator_overlay: Node = null
var _settings_overlay: Node = null

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
	controller = MatchController.new(session.is_host, null)
	add_child(controller)
	controller.phase_changed.connect(_on_phase_changed)
	controller.event_starting.connect(_on_event_starting)
	controller.match_ended.connect(_on_match_ended)
	controller.request_return_to_lobby.connect(_on_request_return_to_lobby)
	controller.bet_loadout_started.connect(_on_bet_loadout_started)
	controller.bet_loadout_finished.connect(_on_bet_loadout_finished)
	session.state_changed.connect(_on_session_state_changed)
	_build_player_panels(match_start)
	_build_overlays()
	_build_loadout_overlay()
	_build_shop_overlay()
	_build_bounty_panel()
	_build_cash_out_drawer()
	_build_target_picker()
	_build_house_twist_overlay()
	_build_event_picker_overlay()
	# Sub-project #7 Plan B C2 fixup: previously these three Plan B widgets
	# had no MatchScene wiring — they were orphaned (compiled but never
	# appeared in production). Slots were added in match_scene.tscn and
	# builders mirror the existing overlay-builder pattern.
	_build_status_grid()
	_build_announcer()
	_build_painful_reveal()
	_build_spectator_overlay()
	# Plan C Task 16: settings overlay + apply persisted text scale.
	_build_settings_overlay()
	var initial_scale = read_initial_text_scale()
	SettingsOverlay.apply_text_scale(initial_scale, get_tree().root)
	# Plan C Task 10: gate the play widgets when local peer becomes spectator.
	controller.local_player_spectator_mode_entered.connect(_on_local_spectator_mode_entered)
	# Plan C Task 3: hook SoundManager (autoload) to the controller's
	# 4 audible-trigger signals. Idempotent — scene reload re-binds.
	if get_tree().root.has_node("SoundManager"):
		get_tree().root.get_node("SoundManager").bind_controller(controller)
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

func _on_bet_loadout_started(_active_peer_ids: Array, _max_per_player: int) -> void:
	if _bet_loadout_slot == null or _bet_loadout_overlay != null:
		return
	_bet_loadout_overlay = BetLoadoutOverlayScene.instantiate()
	_bet_loadout_overlay.controller = controller
	_bet_loadout_overlay.local_player = _find_local_player()
	_bet_loadout_slot.add_child(_bet_loadout_overlay)

func _on_bet_loadout_finished() -> void:
	if _bet_loadout_overlay != null:
		_bet_loadout_overlay.queue_free()
		_bet_loadout_overlay = null

func _find_local_player():
	if controller == null or controller.state == null:
		return null
	var my_id = multiplayer.get_unique_id() if multiplayer != null else 1
	return controller.state.find_player(my_id)

func _build_loadout_overlay() -> void:
	if _loadout_slot == null:
		return
	_loadout_overlay = LoadoutOverlayScene.instantiate()
	_loadout_overlay.controller = controller
	_loadout_overlay.local_player = _find_local_player()
	_loadout_slot.add_child(_loadout_overlay)
	_loadout_overlay.loadout_changed.connect(_on_loadout_changed)

func _on_loadout_changed(slot_index: int, card_id: String) -> void:
	var local = _find_local_player()
	if local == null or controller == null:
		return
	var new_loadout = compute_loadout_from_drop(local.loadout, slot_index, card_id)
	controller.submit_loadout_change(new_loadout)

static func compute_loadout_from_drop(current_loadout: Array, slot_index: int, card_id: String) -> Array:
	var out: Array = current_loadout.duplicate()
	while out.size() <= slot_index:
		out.append("")
	out[slot_index] = card_id
	return out

func _build_shop_overlay() -> void:
	if _shop_slot == null:
		return
	_shop_overlay = ShopOverlayScene.instantiate()
	_shop_overlay.controller = controller
	_shop_overlay.local_player = _find_local_player()
	_shop_slot.add_child(_shop_overlay)

func _build_bounty_panel() -> void:
	if _bounty_slot == null:
		return
	_bounty_panel = BountyPanelScene.instantiate()
	_bounty_panel.controller = controller
	_bounty_slot.add_child(_bounty_panel)

func _build_cash_out_drawer() -> void:
	if _cash_out_slot == null:
		return
	_cash_out_drawer = CashOutCardDrawerScene.instantiate()
	_cash_out_drawer.controller = controller
	_cash_out_drawer.local_player = _find_local_player()
	_cash_out_slot.add_child(_cash_out_drawer)
	_cash_out_drawer.target_required_card_pressed.connect(_on_target_required_card_pressed)

func _build_target_picker() -> void:
	if _target_picker_slot == null:
		return
	_target_picker = CashOutCardDrawerTargetPickerScene.instantiate()
	_target_picker.controller = controller
	var local = _find_local_player()
	if local != null:
		_target_picker.local_peer_id = local.peer_id
	_target_picker_slot.add_child(_target_picker)

func _on_target_required_card_pressed(card_id: String) -> void:
	if _target_picker == null or controller == null:
		return
	var players: Array = []
	if controller.state != null:
		players = controller.state.players
	_target_picker.open_for_card(card_id, players)

func _build_house_twist_overlay() -> void:
	if _house_twist_slot == null:
		return
	_house_twist_overlay = HouseTwistOverlayScene.instantiate()
	_house_twist_overlay.controller = controller
	_house_twist_slot.add_child(_house_twist_overlay)

func _build_event_picker_overlay() -> void:
	if _event_picker_slot == null:
		return
	_event_picker_overlay = EventPickerOverlayScene.instantiate()
	# CRITICAL: set controller + local_player BEFORE add_child so the
	# overlay's _ready() sees non-null controller for signal connection.
	# Mirrors _build_house_twist_overlay + Plan A Task 16's pattern.
	_event_picker_overlay.controller = controller
	_event_picker_overlay.local_player = _find_local_player()
	_event_picker_slot.add_child(_event_picker_overlay)

func _build_status_grid() -> void:
	if _status_grid_slot == null:
		return
	_status_grid = StatusGridScene.instantiate()
	_status_grid.controller = controller
	_status_grid_slot.add_child(_status_grid)

func _build_announcer() -> void:
	if _announcer_slot == null:
		return
	_announcer = AnnouncerScene.instantiate()
	_announcer.controller = controller
	_announcer_slot.add_child(_announcer)

func _build_painful_reveal() -> void:
	if _painful_reveal_slot == null:
		return
	_painful_reveal = PainfulRevealScene.instantiate()
	_painful_reveal.controller = controller
	_painful_reveal_slot.add_child(_painful_reveal)

func _build_spectator_overlay() -> void:
	if _spectator_slot == null:
		return
	_spectator_overlay = SpectatorOverlayScene.instantiate()
	_spectator_overlay.controller = controller
	_spectator_slot.add_child(_spectator_overlay)

func _build_settings_overlay() -> void:
	if _settings_slot == null:
		return
	_settings_overlay = SettingsOverlayScene.instantiate()
	_settings_slot.add_child(_settings_overlay)
	if _settings_button != null:
		_settings_button.pressed.connect(_on_settings_button_pressed)

func _on_settings_button_pressed() -> void:
	if _settings_overlay != null and _settings_overlay.has_method("open"):
		_settings_overlay.open()

func _on_local_spectator_mode_entered(_reason: String) -> void:
	# Plan C Task 10: hide play widgets, show SpectatorOverlay.
	# Reversal is NOT supported in MVP — once a peer goes spectator
	# they stay for the rest of the match.
	var widgets = {
		"BetLoadoutOverlay": _bet_loadout_overlay,
		"LoadoutOverlay": _loadout_overlay,
		"EventPickerOverlay": _event_picker_overlay,
		"CashOutCardDrawer": _cash_out_drawer,
		"CashOutCardDrawerTargetPicker": _target_picker,
		"SpectatorOverlay": _spectator_overlay,
	}
	apply_spectator_visibility(widgets, true)
	# Plan C Task 11: shift always-visible widgets to the left 60%
	# so the SpectatorOverlay (right 40%) renders cleanly.
	if _status_grid != null and _status_grid.has_method("set_compact"):
		_status_grid.set_compact(true)
	if _announcer != null and _announcer.has_method("set_compact"):
		_announcer.set_compact(true)
	if _painful_reveal != null and _painful_reveal.has_method("set_compact"):
		_painful_reveal.set_compact(true)

# Plan C Task 10: the 5 play widgets to hide when entering spectator mode.
static func widgets_to_hide_on_spectator() -> Array[String]:
	return ["BetLoadoutOverlay", "LoadoutOverlay", "EventPickerOverlay", "CashOutCardDrawer", "CashOutCardDrawerTargetPicker"]

# Static helper: flip visibility based on the spectator flag. Accepts a
# Dictionary of widget references (any with a .visible property) so the
# unit test can pass plain Dictionaries without instantiating real Nodes.
static func apply_spectator_visibility(widgets: Dictionary, spectator_mode: bool) -> void:
	for name in widgets_to_hide_on_spectator():
		var w = widgets.get(name, null)
		if w != null:
			w.visible = not spectator_mode
	var spec = widgets.get("SpectatorOverlay", null)
	if spec != null:
		spec.visible = spectator_mode

# Static formatter (testable). Takes total_events as a parameter so the
# caller chooses the count (production passes MatchConfig.QUICK_CLASH_EVENT_COUNT).
static func format_phase_indicator(event_index: int, total_events: int, phase: int) -> String:
	if phase == MatchPhase.Phase.MATCH_END:
		return "Match End"
	var phase_name = MatchPhase.name_for(phase)
	return "Event %d/%d: %s" % [event_index + 1, total_events, phase_name]

# Plan C Task 16: wraps SettingsOverlay.load_persisted_scale with an
# optional path argument so unit tests use test-specific cfg files
# without polluting real user:// data.
static func read_initial_text_scale(path: String = SettingsOverlay.DEFAULT_CFG_PATH) -> float:
	return SettingsOverlay.load_persisted_scale(path)
