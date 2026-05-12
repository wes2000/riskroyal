# Per-player HUD widget. Composed in MatchScene's PlayerPanels HBox.
# Subscribes to MatchController.player_resources_changed(peer_id) and
# refreshes from controller.state.find_player(peer_id) when peer_id matches.
extends PanelContainer

@onready var _name_label: Label = $VBox/NameLabel if has_node("VBox/NameLabel") else null
@onready var _color_swatch: ColorRect = $VBox/ColorSwatch if has_node("VBox/ColorSwatch") else null
@onready var _chips_label: Label = $VBox/ChipsLabel if has_node("VBox/ChipsLabel") else null
@onready var _crowns_label: Label = $VBox/CrownsLabel if has_node("VBox/CrownsLabel") else null
@onready var _heat_label: Label = $VBox/HeatLabel if has_node("VBox/HeatLabel") else null

const SEAT_COLORS: Array = [
	Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW,
	Color.PURPLE, Color.CYAN, Color.ORANGE, Color.MAGENTA,
]

var controller  # MatchController-like
var peer_id: int = 0

func _ready() -> void:
	if controller == null:
		return
	controller.player_resources_changed.connect(_on_player_resources_changed)
	_refresh()

func set_peer(p_peer_id: int) -> void:
	peer_id = p_peer_id
	_refresh()

func _on_player_resources_changed(changed_peer_id: int) -> void:
	if changed_peer_id == peer_id:
		_refresh()

func _refresh() -> void:
	if controller == null or controller.state == null:
		return
	var p = controller.state.find_player(peer_id)
	if p == null:
		visible = false
		return
	visible = true
	if _name_label != null:
		_name_label.text = p.name
	if _color_swatch != null and p.color_index >= 0 and p.color_index < SEAT_COLORS.size():
		_color_swatch.color = SEAT_COLORS[p.color_index]
	if _chips_label != null:
		_chips_label.text = format_chip_text(p.chips)
	if _crowns_label != null:
		_crowns_label.text = format_crown_text(p.crowns)
	if _heat_label != null:
		_heat_label.text = "Heat: %d (%s)" % [p.heat, heat_band(p.heat)]

# Static formatters (testable without scene instantiation)

static func format_chip_text(chips: int) -> String:
	return "%d chips" % chips

static func format_crown_text(crowns: int) -> String:
	if crowns == 1:
		return "1 Crown"
	return "%d Crowns" % crowns

static func heat_band(heat: int) -> String:
	# Per design §5.3
	if heat <= 2:
		return "Quiet"
	if heat <= 5:
		return "Noticed"
	if heat <= 8:
		return "Hot Seat"
	return "Public Enemy"
