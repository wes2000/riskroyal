# HouseTwistOverlay: announces the active twist at HOUSE_TWIST phase
# as a 3-second banner, then shrinks to a corner chip during the
# next event. Hides at the next HOUSE_TWIST.
extends PanelContainer

@onready var _title_label: Label = $VBox/TitleLabel if has_node("VBox/TitleLabel") else null
@onready var _description_label: Label = $VBox/DescriptionLabel if has_node("VBox/DescriptionLabel") else null

var controller  # MatchController-like

func _ready() -> void:
	visible = false
	if controller != null:
		controller.house_twist_announced.connect(_on_house_twist_announced)

func _on_house_twist_announced(twist_dict: Dictionary) -> void:
	visible = true
	_refresh(twist_dict)
	# 3-second banner then shrink to corner. Polish: animate; MVP: stay
	# visible for the whole event, hide when next HOUSE_TWIST replaces
	# it (which will fire _on_house_twist_announced again).
	# If twist_dict is empty (event 1 → no twist), hide.
	if twist_dict.get("type", "") == "":
		visible = false

func _refresh(twist_dict: Dictionary) -> void:
	if _title_label != null:
		_title_label.text = format_twist_title(twist_dict)
	if _description_label != null:
		_description_label.text = format_twist_description(twist_dict)

# Static formatters (testable without scene)

static func format_twist_title(twist_dict: Dictionary) -> String:
	match twist_dict.get("type", ""):
		"double_bounty": return "Double Bounty Round"
		"no_insurance": return "No Insurance"
		"leader_cursed": return "Leader Cursed"
		"power_surge": return "Power Surge"
		"lowest_chips_picks": return "Lowest Chips Picks"
		"sudden_death_jackpot": return "Sudden Death Jackpot"
		_: return ""

static func format_twist_description(twist_dict: Dictionary) -> String:
	match twist_dict.get("type", ""):
		"double_bounty": return "All bounty rewards × 2"
		"no_insurance": return "Insurance cards inert this event"
		"leader_cursed": return "Chip leader earns 25% less this event"
		"power_surge": return "Everyone draws a bonus card"
		"lowest_chips_picks": return "Lowest-chips player picks the next event"
		"sudden_death_jackpot": return "Bonus Crown for taking a specific risk"
		_: return ""
