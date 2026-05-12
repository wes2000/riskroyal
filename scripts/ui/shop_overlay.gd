# ShopOverlay: shown during SHOP phase. Renders 3 offered cards + Buy
# buttons + a Done button. Subscribes to MatchController.shop_opened /
# shop_closed.
extends PanelContainer

const CardRegistry = preload("res://scripts/cards/card_registry.gd")

@onready var _offer_row: HBoxContainer = $VBox/OfferRow if has_node("VBox/OfferRow") else null
@onready var _done_button: Button = $VBox/DoneButton if has_node("VBox/DoneButton") else null
@onready var _summary_label: Label = $VBox/SummaryLabel if has_node("VBox/SummaryLabel") else null

var controller  # MatchController-like
var local_player

func _ready() -> void:
	visible = false
	if controller != null:
		controller.shop_opened.connect(_on_shop_opened)
		controller.shop_closed.connect(_on_shop_closed)
	if _done_button != null:
		_done_button.pressed.connect(_on_done_pressed)

func _on_shop_opened(offered: Array) -> void:
	visible = true
	if _summary_label != null and local_player != null:
		_summary_label.text = "Shop open: %d offered, you have %d chips" % [offered.size(), local_player.chips]

func _on_shop_closed() -> void:
	visible = false

func _on_done_pressed() -> void:
	if controller != null:
		controller.submit_shop_done()
		if _done_button != null:
			_done_button.disabled = true

# Static formatters

static func format_shop_offer(offered: Array) -> Array:
	var out: Array = []
	for card_id in offered:
		var card = CardRegistry.get_card(card_id)
		out.append({
			"card_id": card_id,
			"name": String(card.get("name", "?")),
			"description": String(card.get("description", "")),
			"cost": int(card.get("cost_chips", 0)),
		})
	return out

static func can_afford(chips: int, cost: int) -> bool:
	return chips >= cost
