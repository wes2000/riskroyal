# Card Cannon event. Async blackjack-to-21. Per-player independent
# draws from a number-cards + Ace deck (infinite-deck distribution).
# Lock at any time; bust at score > 21. Score-band payout tiers.
#
# Extends EventNode. compute_next_rank, compute_score, and
# compute_event_result are testable without scene instantiation.
extends "res://scripts/events/event_node.gd"

const MatchConfig = preload("res://scripts/match/match_config.gd")
const EventResult = preload("res://scripts/events/event_result.gd")

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

# RPC routing
var _multiplayer_node = null

# Test seams
var _force_next_rank_override: int = -1   # negative = use RNG

# Scene-tree refs
@onready var _score_label: Label = $VBox/ScoreLabel if has_node("VBox/ScoreLabel") else null
@onready var _hand_row: HBoxContainer = $VBox/HandRow if has_node("VBox/HandRow") else null
@onready var _draw_button: Button = $VBox/DrawButton if has_node("VBox/DrawButton") else null
@onready var _lock_button: Button = $VBox/LockButton if has_node("VBox/LockButton") else null

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
	_send_rpc("_rpc_draw_requested", [my_peer_id])

func submit_lock() -> void:
	var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
	_send_rpc("_rpc_lock_requested", [my_peer_id])

func _run(context) -> void:
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

func _send_rpc(method_name: String, args: Array = []) -> void:
	if _multiplayer_node == null:
		return
	match args.size():
		0: _multiplayer_node.rpc(method_name)
		1: _multiplayer_node.rpc(method_name, args[0])
		2: _multiplayer_node.rpc(method_name, args[0], args[1])
		3: _multiplayer_node.rpc(method_name, args[0], args[1], args[2])
		4: _multiplayer_node.rpc(method_name, args[0], args[1], args[2], args[3])
		_:
			push_error("CardCannonEvent._send_rpc: unsupported arity %d" % args.size())

func _send_rpc_to_peer(peer_id: int, method_name: String, args: Array = []) -> void:
	if _multiplayer_node == null:
		return
	match args.size():
		0: _multiplayer_node.rpc_id(peer_id, method_name)
		1: _multiplayer_node.rpc_id(peer_id, method_name, args[0])
		2: _multiplayer_node.rpc_id(peer_id, method_name, args[0], args[1])
		_:
			push_error("CardCannonEvent._send_rpc_to_peer: unsupported arity %d" % args.size())

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

static func compute_event_result(context, hands: Dictionary, locked_scores: Dictionary, busted: Dictionary) -> RefCounted:
	var result = EventResult.new()
	result.event_id = "card_cannon"
	return result
