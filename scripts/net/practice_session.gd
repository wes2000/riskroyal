# PracticeSession: builder + entry point for local-only "Practice vs Bots"
# matches. Constructs a MatchStart with one human seat (peer_id=1) and N
# bot seats (peer_id 1000..1000+N-1), caches it on NetSessionMain, flips
# the practice_mode flag, and transitions to the match scene.
#
# build_match_start() is pure (no side effects) so it can be unit-tested
# without a live SceneTree. start() wraps it with the side-effecting
# autoload mutation + scene change.
extends Object

const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

const HUMAN_PEER_ID: int = 1
const BOT_PEER_ID_BASE: int = 1000


# Pure builder: returns a MatchStart fixture for a practice match.
# bot_count >= 1; if seed == 0, a time-based seed is used so the rng_seed
# field is always non-zero (callers can pass 0 to mean "random").
static func build_match_start(bot_count: int, seed: int = 0) -> MatchStart:
	var ms = MatchStart.new()
	ms.host_peer_id = HUMAN_PEER_ID
	ms.rng_seed = seed if seed != 0 else int(Time.get_ticks_msec())
	ms.mode = "quick_clash"
	ms.rules = {}

	# Human seat (seat 0).
	var human = PlayerSlot.new()
	human.peer_id = HUMAN_PEER_ID
	human.seat_index = 0
	human.name = "You"
	human.color_index = 0
	human.is_host = true
	human.connected = true
	ms.seats.append(human)

	# Bot seats (seat 1..bot_count). Peer IDs >= 1000 to stay above the
	# Godot multiplayer peer ID range (real peers start at 1).
	for i in range(bot_count):
		var bot = PlayerSlot.new()
		bot.peer_id = BOT_PEER_ID_BASE + i
		bot.seat_index = i + 1
		bot.name = "Bot %d" % (i + 1)
		bot.color_index = (i + 1) % 8
		bot.is_host = false
		bot.connected = true
		ms.seats.append(bot)

	return ms


# Side-effecting entry point: builds the MatchStart, caches it on
# NetSessionMain, flips practice_mode = true, marks the session as
# local-host, and transitions to the match scene. Called by the
# Practice Setup overlay's Start button handler.
static func start(bot_count: int, seed: int, tree: SceneTree) -> void:
	var ms = build_match_start(bot_count, seed)
	if tree != null and tree.root != null and tree.root.has_node("NetSessionMain"):
		var nsm = tree.root.get_node("NetSessionMain")
		if nsm.has_method("set_last_match_start"):
			nsm.set_last_match_start(ms)
		if "practice_mode" in nsm:
			nsm.practice_mode = true
		if nsm.session != null:
			nsm.session.local_peer_id = HUMAN_PEER_ID
			nsm.session.is_host = true
	if tree != null:
		tree.change_scene_to_file("res://scenes/match_scene.tscn")
