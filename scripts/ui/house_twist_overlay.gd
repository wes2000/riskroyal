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
	# Empty twist (event 1 baseline or post-cleanup) → hide and skip refresh.
	if twist_dict.get("type", "") == "":
		visible = false
		return
	_refresh(twist_dict)
	visible = true
	# Polish (sub-project #7): 3-second banner then shrink to corner.

func _refresh(twist_dict: Dictionary) -> void:
	if _title_label != null:
		_title_label.text = format_twist_title(twist_dict)
	if _description_label != null:
		# Alpha remediation Phase F §12.3: prefer the richer subtitle copy
		# (with target <Name> for leader_cursed / lowest_chips_picks) when
		# we can resolve the target name; otherwise fall back to the older
		# short description (kept for back-compat with the existing test
		# suite + legacy callers).
		var target_name = _resolve_target_name(twist_dict)
		var subtitle = format_twist_subtitle(twist_dict, target_name)
		if subtitle != "":
			_description_label.text = subtitle
		else:
			_description_label.text = format_twist_description(twist_dict)

# Resolves <Name> for the active twist's target_peer_id via controller.state.
# Returns "" when controller or state isn't wired (unit tests can drive
# format_twist_subtitle directly with an explicit name).
func _resolve_target_name(twist_dict: Dictionary) -> String:
	if controller == null or controller.state == null:
		return ""
	var params = twist_dict.get("params", {})
	var target_pid = int(params.get("target_peer_id", 0))
	if target_pid == 0:
		return ""
	var p = controller.state.find_player(target_pid)
	if p == null:
		return ""
	return String(p.name)

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

# Alpha remediation Phase F §12.3: richer subtitle copy answering
# "what changed, who is in trouble, what should I do differently?"
# Spec pins these strings as literal output.
#
# Pure static: caller resolves <Name> from state.find_player(target_peer_id)
# and passes it in. Empty target_name on a name-required twist falls back
# to a title-only sentence (e.g. "Leader Cursed.").
static func format_twist_subtitle(twist_dict: Dictionary, target_name: String) -> String:
	match twist_dict.get("type", ""):
		"double_bounty":
			return "Bounties doubled. Make it personal."
		"no_insurance":
			return "No Insurance. Greed has no helmet."
		"leader_cursed":
			if target_name == "":
				return "Leader Cursed."
			return "Leader Cursed. %s's next reward is cut." % target_name
		"power_surge":
			return "Power Surge. Everyone gets a fresh trick."
		"lowest_chips_picks":
			if target_name == "":
				return "Underdog's Choice."
			return "Underdog's Choice. %s picks the next table." % target_name
		"sudden_death_jackpot":
			return "Bonus Crown live. Take the dangerous route."
		_:
			return ""
