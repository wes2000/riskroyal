# BountyPanel: shown alongside PlayerPanels. Lists active bounties.
# Subscribes to controller.bounty_placed / bounty_claimed / bounty_unclaimed.
extends PanelContainer

const Bounty = preload("res://scripts/match/bounty.gd")
const CardRegistry = preload("res://scripts/cards/card_registry.gd")

@onready var _rows: VBoxContainer = $VBox/Rows if has_node("VBox/Rows") else null

var controller

func _ready() -> void:
	if controller != null:
		controller.bounty_placed.connect(_on_bounty_placed)
		controller.bounty_claimed.connect(_on_bounty_claimed)
		controller.bounty_unclaimed.connect(_on_bounty_unclaimed)

func _on_bounty_placed(_bounty_dict: Dictionary) -> void:
	_refresh()

func _on_bounty_claimed(_claimant_peer_id: int, _bounty_dict: Dictionary, _reward: int) -> void:
	_refresh()

func _on_bounty_unclaimed(_bounty_dict: Dictionary) -> void:
	_refresh()

func _refresh() -> void:
	if _rows == null or controller == null:
		return
	for child in _rows.get_children():
		child.queue_free()
	for bounty in controller.state.bounties:
		var label = Label.new()
		var target = controller.state.find_player(bounty.target)
		label.text = format_bounty_summary(bounty.to_dict(), target)
		_rows.add_child(label)

# Static formatter

static func format_bounty_summary(bounty_dict: Dictionary, target_player) -> String:
	var origin = String(bounty_dict.get("origin", "")).capitalize()
	var target_name = target_player.name if target_player != null else ("P%d" % int(bounty_dict.get("target", 0)))
	var base_reward = int(bounty_dict.get("reward_chips", 0))
	var heat = int(bounty_dict.get("placed_at_target_heat", 0))
	var scaled = int(base_reward * CardRegistry.heat_multiplier(heat))
	return "%s Bounty: %s — %d chips for bust" % [origin, target_name, scaled]
