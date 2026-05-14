# Announcer: top-of-screen banner for 4 key game moments:
# HOUSE TWIST, player ejection, Crown award, and match end.
# Queues messages so simultaneous triggers don't collide.
# Auto-dismiss after 3 seconds via Tween fade.
extends PanelContainer

const HouseTwistOverlay = preload("res://scripts/ui/house_twist_overlay.gd")
const CardRegistry = preload("res://scripts/cards/card_registry.gd")

const DISPLAY_DURATION_SEC: float = 3.0

@onready var _message_label: Label = $VBox/MessageLabel if has_node("VBox/MessageLabel") else null

var controller  # MatchController-like

var _queue: Array = []
var _showing: bool = false
var _active_tween: Tween = null

func _ready() -> void:
	visible = false
	if controller != null:
		controller.house_twist_announced.connect(_on_house_twist_announced)
		if controller.has_signal("player_busted"):
			controller.player_busted.connect(_on_player_busted)
		if controller.has_signal("crown_awarded"):
			controller.crown_awarded.connect(_on_crown_awarded)
		controller.match_ended.connect(_on_match_ended)
		# Alpha remediation Phase F §11.3: public callouts when a card is
		# played. Subscribe via has_signal so headless / minimal test
		# harnesses don't trip on missing signal.
		if controller.has_signal("card_effect_applied"):
			controller.card_effect_applied.connect(_on_card_effect_applied)
		# Alpha remediation Phase G S1: rivalry banner when a player-placed
		# bounty pays out. Auto-placed (Leader / Heat) bounties skip the
		# banner — handler filters on bounty.origin == "placed".
		if controller.has_signal("bounty_claimed"):
			controller.bounty_claimed.connect(_on_bounty_claimed)

func _on_house_twist_announced(twist_dict: Dictionary) -> void:
	# Alpha remediation Phase F §12.3: resolve the target's display name
	# from state so the callout reads e.g. "HOUSE TWIST: Leader Cursed —
	# Maya's next reward is cut." Untargeted twists pass "" through.
	var params = twist_dict.get("params", {})
	var target_pid = int(params.get("target_peer_id", 0))
	var target_name = "" if target_pid == 0 else _name_for(target_pid)
	var msg = format_twist_text(twist_dict, target_name)
	if msg == "":
		return
	_enqueue(msg)

func _on_player_busted(peer_id: int, chip_loss: int) -> void:
	var peer_name = _name_for(peer_id)
	_enqueue(format_bust_text(peer_name, chip_loss))

func _on_crown_awarded(peer_id: int, count: int) -> void:
	var peer_name = _name_for(peer_id)
	_enqueue(format_crown_text(peer_name, count))

func _on_card_effect_applied(peer_id: int, card_id: String, effect_result: Dictionary) -> void:
	# Alpha remediation Phase F §11.3: public banner per card play.
	# Resolves the actor's display name via _name_for + the target's via
	# the effect_result.target field (only present for target-required
	# cards; the static formatter ignores it for self-target / no-target
	# cards). Display name comes from CardRegistry so the generic
	# fallback "<Player> played <CardName>." picks up future cards
	# automatically.
	var peer_name = _name_for(peer_id)
	var target_pid = int(effect_result.get("target", 0))
	var target_name = "" if target_pid == 0 else _name_for(target_pid)
	var card = CardRegistry.get_card(card_id)
	var card_display_name = String(card.get("name", card_id))
	var msg = format_card_callout(card_id, peer_name, target_name, card_display_name)
	if msg == "":
		return
	_enqueue(msg)

func _on_bounty_claimed(claimant_peer_id: int, bounty_dict: Dictionary, _reward_chips: int) -> void:
	# Alpha remediation Phase G S1 (Pillar #5): public callout when a
	# player-placed bounty pays out. Auto-placed Leader / Heat bounties
	# (origin == "leader" / "heat") are skipped to avoid announcer churn
	# every event — only the personal "I called you out" beat surfaces.
	if String(bounty_dict.get("origin", "")) != "placed":
		return
	var claimant_name = _name_for(claimant_peer_id)
	var target_name = _name_for(int(bounty_dict.get("target", 0)))
	_enqueue(format_bounty_claimed_text(claimant_name, target_name))

func _on_match_ended(rankings: Array) -> void:
	# Sub-project #7 Plan B C3 fixup: rankings[0] is a MatchPlayer Object
	# (see MatchController._process_match_end + _rpc_match_ended), not a
	# Dictionary nor an int. The previous code did `int(rankings[0])`
	# which silently produced 0 — the banner would always say "P0 WINS
	# THE MATCH!". Read peer_id + name directly off the Object, with a
	# defensive Dictionary fallback in case a test or future code path
	# serializes the rankings before re-emit.
	if rankings.is_empty():
		return
	var top = rankings[0]
	if top == null:
		return
	var winner_pid: int = 0
	var winner_name: String = ""
	if top is Dictionary:
		winner_pid = int(top.get("peer_id", 0))
		winner_name = String(top.get("name", _name_for(winner_pid)))
	else:
		winner_pid = int(top.peer_id)
		winner_name = String(top.name)
	_enqueue(format_match_outcome_text(winner_pid, winner_name))

func _name_for(peer_id: int) -> String:
	if controller == null:
		return "P%d" % peer_id
	if controller.state == null:
		return "P%d" % peer_id
	var p = controller.state.find_player(peer_id)
	if p == null:
		return "P%d" % peer_id
	return p.name

func _enqueue(message: String) -> void:
	_queue.append(message)
	if not _showing:
		_show_next()

# Plan C Task 11: compact mode shrinks the banner to the left 60%
# so the spectator leaderboard on the right 40% isn't occluded.
func set_compact(compact: bool) -> void:
	if compact:
		anchor_right = 0.6
	else:
		anchor_right = 1.0

func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		visible = false
		return
	_showing = true
	var msg: String = _queue.pop_front()
	if _message_label != null:
		_message_label.text = msg
	# Plan C Task 4: sequenced slide-in + bounce + slide-out.
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	visible = true
	modulate.a = 1.0
	position.y = -100.0
	var t = animation_timeline()
	_active_tween = create_tween()
	_active_tween.tween_property(self, "position:y", 0.0, float(t.slide_in_sec)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_tween.tween_interval(float(t.hold_sec))
	_active_tween.set_parallel(true)
	_active_tween.tween_property(self, "position:y", -100.0, float(t.slide_out_sec))
	_active_tween.tween_property(self, "modulate:a", 0.0, float(t.slide_out_sec))
	_active_tween.set_parallel(false)
	_active_tween.tween_callback(_show_next)

# Static formatters (testable without scene)

static func format_twist_text(twist_dict: Dictionary, target_name: String = "") -> String:
	var title = HouseTwistOverlay.format_twist_title(twist_dict)
	if title == "":
		return ""
	# Alpha remediation Phase F §12.3: targeted twists get a "— <Name>'s …"
	# suffix derived from the subtitle's second sentence. Untargeted twists
	# keep the legacy "HOUSE TWIST: <Title>!" form.
	var subtitle = HouseTwistOverlay.format_twist_subtitle(twist_dict, target_name)
	var second_sentence = _second_sentence(subtitle)
	if target_name != "" and second_sentence != "":
		return "HOUSE TWIST: %s — %s" % [title, second_sentence]
	return "HOUSE TWIST: %s!" % title

# Returns everything after the first sentence-ending period, trimmed.
# "Leader Cursed. Maya's next reward is cut." → "Maya's next reward is cut."
# "Leader Cursed." (title-only fallback) → "".
static func _second_sentence(subtitle: String) -> String:
	var idx = subtitle.find(". ")
	if idx < 0:
		return ""
	return subtitle.substr(idx + 2).strip_edges()

static func format_bust_text(peer_name: String, chip_loss: int) -> String:
	return "✗ %s EJECTED! -%d chips" % [peer_name, chip_loss]

static func format_crown_text(peer_name: String, crown_count: int) -> String:
	if crown_count >= 2:
		return "👑 %s WINS %d CROWNS!" % [peer_name, crown_count]
	return "👑 %s WINS THE CROWN!" % peer_name

static func format_match_outcome_text(_winner_peer_id: int, winner_name: String) -> String:
	return "%s WINS THE MATCH!" % winner_name

# Alpha remediation Phase F §11.3: public banner copy for card plays.
# The four "flavor" cards have spec-pinned literal strings; every other
# card uses the generic "<Player> played <CardName>." form. card_display_name
# falls back to card_id at the call site if CardRegistry has no entry.
static func format_card_callout(card_id: String, peer_name: String,
		target_name: String, card_display_name: String) -> String:
	match card_id:
		"cash_out_jammer":
			return "%s jammed %s's cash-out." % [peer_name, target_name]
		"insurance":
			return "%s bought Insurance. Cowardly? Effective." % peer_name
		"copycat_bet":
			return "%s copied %s's wager." % [peer_name, target_name]
		"heat_spike":
			return "%s spiked %s's Heat." % [peer_name, target_name]
		"place_bounty":
			# Alpha remediation Phase G S1: Pillar #5 rivalry callout. The
			# generic fallback dropped target_name even though place_bounty
			# is target_required=true, which masked the "permission to attack
			# friends" beat.
			return "%s put a bounty on %s." % [peer_name, target_name]
		_:
			var name = card_display_name if card_display_name != "" else card_id
			return "%s played %s." % [peer_name, name]

# Alpha remediation Phase G S1: rivalry callout when a player-placed bounty
# pays out. Spec §8.7 of the remediation design doc. Auto-placed (Leader /
# Heat) bounties skip this callout — see _on_bounty_claimed.
static func format_bounty_claimed_text(claimant_name: String, target_name: String) -> String:
	return "%s claimed their bounty on %s." % [claimant_name, target_name]

# Plan C Task 4: animation timeline durations exposed as a Dictionary
# so unit tests can assert the stage lengths without running a real Tween.
static func animation_timeline() -> Dictionary:
	return {
		"slide_in_sec": 0.3,
		"hold_sec": 2.5,
		"slide_out_sec": 0.3,
		"total_sec": 0.3 + 2.5 + 0.3,
	}
