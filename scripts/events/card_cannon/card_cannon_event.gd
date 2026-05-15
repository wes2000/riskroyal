# Card Cannon event. Async blackjack-to-21. Per-player independent
# draws from a number-cards + Ace deck (infinite-deck distribution).
# Lock at any time; bust at score > 21. Score-band payout tiers.
#
# Extends EventNode. compute_next_rank, compute_score, and
# compute_event_result are testable without scene instantiation.
extends "res://scripts/events/event_node.gd"

const MatchConfig = preload("res://scripts/match/match_config.gd")
const EventResult = preload("res://scripts/events/event_result.gd")
const EventHelpers = preload("res://scripts/match/event_helpers.gd")
const HeatRules = preload("res://scripts/match/heat_rules.gd")

# Per-round state
var _hands: Dictionary = {}             # peer_id -> Array[int] ranks drawn
var _scores: Dictionary = {}            # peer_id -> int running score
var _locked_scores: Dictionary = {}     # peer_id -> int score at lock
var _busted: Dictionary = {}            # peer_id -> bool
var _active_peers: Array = []
var _is_host: bool = false
var _finished: bool = false
var _stashed_context = null
var _rng: RandomNumberGenerator = null  # seeded from context.rng_seed in _run

# Test seams
var _force_next_rank_override: int = -1   # negative = use RNG

# Scene-tree refs
@onready var _score_label: Label = $VBox/ScoreLabel if has_node("VBox/ScoreLabel") else null
@onready var _hand_row: HBoxContainer = $VBox/HandRow if has_node("VBox/HandRow") else null
@onready var _draw_button: Button = $VBox/ButtonRow/DrawButton if has_node("VBox/ButtonRow/DrawButton") else null
@onready var _lock_button: Button = $VBox/ButtonRow/LockButton if has_node("VBox/ButtonRow/LockButton") else null

func get_event_id() -> String:
	return "card_cannon"

func _ready() -> void:
	if _draw_button != null:
		_draw_button.pressed.connect(_on_draw_button_pressed)
	if _lock_button != null:
		_lock_button.pressed.connect(_on_lock_button_pressed)

func _on_draw_button_pressed() -> void:
	if _finished:
		return
	submit_draw()

func _on_lock_button_pressed() -> void:
	if _finished:
		return
	submit_lock()

func submit_draw() -> void:
	var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
	# Practice / offline mode: no MultiplayerPeer attached. Route directly
	# through the host-side method (we ARE the host in practice mode).
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		host_submit_draw(my_peer_id)
		return
	var host_peer_id = _stashed_context.host_peer_id if _stashed_context != null else 1
	_send_rpc_to_host(host_peer_id, "_rpc_draw_requested", [my_peer_id])

func submit_lock() -> void:
	var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		host_submit_lock(my_peer_id)
		return
	var host_peer_id = _stashed_context.host_peer_id if _stashed_context != null else 1
	_send_rpc_to_host(host_peer_id, "_rpc_lock_requested", [my_peer_id])

func _run(context) -> void:
	super._run(context)  # base self-wires _multiplayer_node
	context.tuning["target_score"] = MatchConfig.CARD_CANNON_TARGET_SCORE
	context.tuning["payout_bands"] = {
		"low": MatchConfig.CARD_CANNON_PAYOUT_BAND_LOW,
		"medium": MatchConfig.CARD_CANNON_PAYOUT_BAND_MEDIUM,
		"strong": MatchConfig.CARD_CANNON_PAYOUT_BAND_STRONG,
		"heavy": MatchConfig.CARD_CANNON_PAYOUT_BAND_HEAVY,
		"perfect": MatchConfig.CARD_CANNON_PAYOUT_BAND_PERFECT,
	}
	_stashed_context = context
	_is_host = context.is_host
	# Derive a per-event RNG from context.rng_seed (EventContext exposes
	# rng_seed, not rng). Storing as an instance field so successive draws
	# advance the same sequence — same pattern as RocketClashEvent.
	_rng = RandomNumberGenerator.new()
	_rng.seed = context.rng_seed
	_active_peers = []
	for p in context.players:
		if p.is_active_this_event:
			_active_peers.append(p.peer_id)
			_hands[p.peer_id] = []
			_scores[p.peer_id] = 0
			_busted[p.peer_id] = false
	if _is_host:
		_send_rpc("_rpc_card_cannon_started", [])

@rpc("authority", "call_remote", "reliable")
func _rpc_card_cannon_started() -> void:
	pass  # clients render the scene; no time sync needed

# Bot-friendly entry points: take an explicit peer_id instead of inferring
# from multiplayer.get_unique_id(). Host-only; route through the same
# receivers remote peers use. Required for Practice mode bots which share
# the local peer.
func host_submit_draw(peer_id: int) -> void:
	if not _is_host:
		push_warning("host_submit_draw called on non-host")
		return
	_rpc_draw_requested(peer_id)

func host_submit_lock(peer_id: int) -> void:
	if not _is_host:
		push_warning("host_submit_lock called on non-host")
		return
	_rpc_lock_requested(peer_id)

@rpc("any_peer", "call_local", "reliable")
func _rpc_draw_requested(peer_id: int) -> void:
	if not _is_host:
		return
	if _finished:
		return
	if peer_id in _locked_scores:
		return  # already locked
	if _busted.get(peer_id, false):
		return  # already busted
	if not (peer_id in _active_peers):
		return  # peer not active
	var rank = _draw_next_rank()
	if not _hands.has(peer_id):
		_hands[peer_id] = []
	_hands[peer_id].append(rank)
	var new_score = compute_score(_hands[peer_id])
	_scores[peer_id] = new_score
	var is_busted = new_score > 21
	if is_busted:
		_busted[peer_id] = true
		_emit_status_changed(_stashed_context, peer_id, "BUSTED")
	_send_rpc("_rpc_card_drawn", [peer_id, rank, new_score, is_busted])
	if _all_active_settled():
		_finish()

@rpc("authority", "call_remote", "reliable")
func _rpc_card_drawn(peer_id: int, rank: int, new_score: int, is_busted: bool) -> void:
	if not _hands.has(peer_id):
		_hands[peer_id] = []
	_hands[peer_id].append(rank)
	_scores[peer_id] = new_score
	_busted[peer_id] = is_busted

@rpc("any_peer", "call_local", "reliable")
func _rpc_lock_requested(peer_id: int) -> void:
	if not _is_host:
		return
	if _finished:
		return
	if peer_id in _locked_scores:
		return
	if _busted.get(peer_id, false):
		return
	if not (peer_id in _active_peers):
		return
	_locked_scores[peer_id] = _scores.get(peer_id, 0)
	_emit_status_changed(_stashed_context, peer_id, "LOCKED")
	_send_rpc("_rpc_locked", [peer_id, _locked_scores[peer_id]])
	if _all_active_settled():
		_finish()

@rpc("authority", "call_remote", "reliable")
func _rpc_locked(peer_id: int, locked_score: int) -> void:
	_locked_scores[peer_id] = locked_score

func _draw_next_rank() -> int:
	if _force_next_rank_override >= 0:
		return _force_next_rank_override
	# _rng is set by _run from context.rng_seed; defensive fallback for tests
	# that bypass _run (they set _force_next_rank_override instead).
	if _rng == null:
		_rng = RandomNumberGenerator.new()
	return compute_next_rank(_rng)

func _all_active_settled() -> bool:
	for pid in _active_peers:
		if (pid in _locked_scores) or _busted.get(pid, false):
			continue
		return false
	return true

func _finish() -> void:
	if _finished:
		return
	_finished = true
	var result = compute_event_result(_stashed_context, _hands, _locked_scores, _busted)
	event_complete.emit(result)

# ----- Static helpers -----

# Returns a single card rank in [2, 11]. 11 is the Ace (high value; the
# score computation will demote to 1 if needed to avoid bust). Uniform
# distribution; infinite-deck simplification.
static func compute_next_rank(rng: RandomNumberGenerator) -> int:
	return 2 + int(rng.randf() * 10)

# Computes the score from a hand. Aces (rank 11) auto-demote to 1 if
# the total exceeds 21 and an Ace can still be demoted.
static func compute_score(hand: Array) -> int:
	var total = 0
	var aces = 0
	for rank in hand:
		if rank == 11:
			aces += 1
		total += rank
	while total > 21 and aces > 0:
		total -= 10  # demote one Ace from 11 to 1
		aces -= 1
	return total

# Alpha remediation Phase D Change 5 (§9.3): Card Cannon target selection.
# Players may set their target via state.event_modifiers[pid][
# "card_cannon_target_peer_id"] during BET_LOADOUT (typically via a card
# or future picker UI). If no target is set or the explicit target is
# invalid, auto-default to highest-Crown opponent, ties broken by Heat,
# full ties broken by lowest seat_index. Self never auto-targets self;
# inactive opponents are skipped.
static func resolve_target_peer_id(context, shooter_peer_id: int) -> int:
	if context == null:
		return 0
	# Explicit target from event_modifiers takes precedence.
	var p_mods = context.event_modifiers.get(shooter_peer_id, {})
	var explicit = int(p_mods.get("card_cannon_target_peer_id", 0))
	if explicit != 0 and explicit != shooter_peer_id:
		# Verify the explicit target is a real, active opponent.
		for player in context.players:
			if int(player.peer_id) == explicit and player.is_active_this_event:
				return explicit
		# Explicit target invalid — fall through to auto-default.
	# Auto-default: highest crowns among active opponents, tie-break by
	# heat, then by lowest seat_index.
	var best_peer_id: int = 0
	var best_crowns: int = -1
	var best_heat: int = -1
	var best_seat: int = 999999
	for player in context.players:
		if int(player.peer_id) == shooter_peer_id:
			continue
		if not player.is_active_this_event:
			continue
		var crowns = int(player.crowns)
		var heat = int(player.heat)
		var seat = int(player.seat_index)
		if crowns > best_crowns or (crowns == best_crowns and heat > best_heat) or (crowns == best_crowns and heat == best_heat and seat < best_seat):
			best_peer_id = int(player.peer_id)
			best_crowns = crowns
			best_heat = heat
			best_seat = seat
	return best_peer_id

static func compute_event_result(context, hands: Dictionary, locked_scores: Dictionary, busted: Dictionary) -> RefCounted:
	var result = EventResult.new()
	result.event_id = "card_cannon"
	var summary: Array = []
	var winner_peer_id = 0
	var winner_score = 0
	var winner_seat = INF
	var modifiers = {}
	if context != null:
		modifiers = context.event_modifiers
	for player in context.players:
		var pid = player.peer_id
		var wager = int(context.wagers.get(pid, 0))
		var p_mods = modifiers.get(pid, {})
		if busted.get(pid, false):
			var bust_loss = wager
			if p_mods.get("insurance_pre", false):
				bust_loss = int(wager / 2)
			result.per_player[pid] = {
				"chip_delta": -bust_loss, "crown_delta": 0, "heat_delta": 0,
				"bust": true, "cash_out_at": 0.0,
			}
			summary.append({
				"peer_id": pid, "name": player.name,
				"score": compute_score(hands.get(pid, [])),
				"locked_score": 0, "chip_delta": -bust_loss, "busted": true, "wager": wager,
			})
		else:
			var locked = int(locked_scores.get(pid, 0))
			var band_mult = _band_multiplier(locked)
			var chip_delta = int(wager * band_mult)
			var wm = float(p_mods.get("wager_multiplier", 1.0))
			if wm != 1.0:
				chip_delta = int(chip_delta * wm)
			var um = float(p_mods.get("underdog_multiplier", 1.0))
			if um != 1.0:
				chip_delta = int(chip_delta * um)
			# Sub-project #7 Plan A Task 4: Leader Cursed via EventHelpers
			chip_delta = EventHelpers.apply_leader_cursed(context, pid, chip_delta)
			result.per_player[pid] = {
				"chip_delta": chip_delta, "crown_delta": 0, "heat_delta": 0,
				"bust": false, "cash_out_at": 0.0,
			}
			summary.append({
				"peer_id": pid, "name": player.name,
				"score": locked, "locked_score": locked,
				"chip_delta": chip_delta, "busted": false, "wager": wager,
			})
			# Track winner (seat_index tie-break)
			if locked > winner_score or (locked == winner_score and player.seat_index < winner_seat):
				winner_score = locked
				winner_peer_id = pid
				winner_seat = player.seat_index
	# Crown to highest locked_score; per-survivor Heat scales via HeatRules
	# (Alpha remediation Phase C Change 3 §7.4).
	if winner_peer_id != 0 and winner_score > 0:
		result.per_player[winner_peer_id]["crown_delta"] = 1
	for player in context.players:
		var pid = player.peer_id
		if busted.get(pid, false):
			continue  # busted players keep heat_delta = 0
		var locked = int(locked_scores.get(pid, 0))
		var won_crown = (pid == winner_peer_id) and (winner_score > 0)
		var base_heat = HeatRules.card_cannon_heat(locked, won_crown)
		var p_mods_heat = modifiers.get(pid, {})
		result.per_player[pid]["heat_delta"] = HeatRules.apply_heat_shield(base_heat, p_mods_heat)
	# Sub-project #7 Plan A Task 4: Sudden Death Jackpot via EventHelpers
	for player in context.players:
		var pid = player.peer_id
		var survives = not busted.get(pid, false) and int(locked_scores.get(pid, 0)) == 21
		EventHelpers.apply_sudden_death_bonus(context, pid, result.per_player, "locked_at_perfect", survives)
	# Alpha remediation Phase D Change 5 Task D.2 (§9.3): locked-score
	# chip attacks. Each non-busted shooter fires at their resolved
	# target. Attack scales with locked score per §9.3. Folded into
	# chip_delta (Approach A per §9.4). Bonus per-player keys for the
	# reveal: target_peer_id, attack_delta (shooter), incoming_attack
	# (target). Perfect 21 also adds +1 bonus Heat on the shooter.
	var attack_table = {
		21: 100,   # perfect
		20: 75, 19: 75,
		18: 50, 17: 50, 16: 50,
		15: 25, 14: 25, 13: 25, 12: 25, 11: 25,
	}
	for player in context.players:
		var shooter_pid = int(player.peer_id)
		if busted.get(shooter_pid, false):
			continue  # busted shooters don't fire
		var lscore = int(locked_scores.get(shooter_pid, 0))
		if lscore <= 10:
			# No attack tier — store 0 attack_delta for the reveal.
			result.per_player[shooter_pid]["target_peer_id"] = 0
			result.per_player[shooter_pid]["attack_delta"] = 0
			continue
		var target_pid = resolve_target_peer_id(context, shooter_pid)
		if target_pid == 0:
			result.per_player[shooter_pid]["target_peer_id"] = 0
			result.per_player[shooter_pid]["attack_delta"] = 0
			continue
		var atk = int(attack_table.get(lscore, 25))
		# Bonus heat for perfect 21 (§9.3): +1 bonus Heat on shooter.
		if lscore == 21:
			result.per_player[shooter_pid]["heat_delta"] = int(result.per_player[shooter_pid].get("heat_delta", 0)) + 1
		# Fold attack into shooter's chip_delta (positive).
		result.per_player[shooter_pid]["chip_delta"] = int(result.per_player[shooter_pid].get("chip_delta", 0)) + atk
		# Fold attack into target's chip_delta (negative). Ensure the
		# target has a per_player entry — busted targets are populated
		# in the main loop already, but defensive init keeps this safe.
		if not result.per_player.has(target_pid):
			result.per_player[target_pid] = {
				"chip_delta": 0, "crown_delta": 0, "heat_delta": 0,
				"bust": false, "cash_out_at": 0.0,
			}
		result.per_player[target_pid]["chip_delta"] = int(result.per_player[target_pid].get("chip_delta", 0)) - atk
		result.per_player[target_pid]["incoming_attack"] = int(result.per_player[target_pid].get("incoming_attack", 0)) + atk
		# Reveal fields on the shooter.
		result.per_player[shooter_pid]["target_peer_id"] = target_pid
		result.per_player[shooter_pid]["attack_delta"] = atk
	# Patch the scores_summary rows so the reveal sees the post-attack
	# chip_delta + the new combat fields (target_peer_id, attack_delta).
	for row in summary:
		var pid = int(row.get("peer_id", 0))
		var entry = result.per_player.get(pid, {})
		row["chip_delta"] = int(entry.get("chip_delta", row.get("chip_delta", 0)))
		row["target_peer_id"] = int(entry.get("target_peer_id", 0))
		row["attack_delta"] = int(entry.get("attack_delta", 0))
	result.painful_reveal = {
		"winner_peer_id": winner_peer_id,
		"winner_score": winner_score,
		"scores_summary": summary,
	}
	return result

static func _band_multiplier(score: int) -> float:
	if score == 21:
		return MatchConfig.CARD_CANNON_PAYOUT_BAND_PERFECT
	if score >= 19:
		return MatchConfig.CARD_CANNON_PAYOUT_BAND_HEAVY
	if score >= 16:
		return MatchConfig.CARD_CANNON_PAYOUT_BAND_STRONG
	if score >= 11:
		return MatchConfig.CARD_CANNON_PAYOUT_BAND_MEDIUM
	return MatchConfig.CARD_CANNON_PAYOUT_BAND_LOW
