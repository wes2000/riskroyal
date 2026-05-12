# Authoritative per-match state. Owned by host's MatchController; mirrored
# on clients via RPC. Field-level mutation is host-only.
extends RefCounted

const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

var event_index: int = 0
var phase: int = MatchPhase.Phase.HOUSE_REVEAL
var players: Array = []
var current_event_id: String = ""
var current_result = null  # EventResult or null
var rng_seed: int = 0
var rng: RandomNumberGenerator = null
var pending_wagers: Dictionary = {}
var bounties: Array = []
var current_shop_offer: Array = []   # Array of card_id strings — scalars only
var shop_done_peers: Array = []      # Array of peer_id ints — scalars only
var event_modifiers: Dictionary = {}
var pending_card_effects: Array = []

func seed_rng() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = rng_seed

func find_player(peer_id: int):
	for p in players:
		if p.peer_id == peer_id:
			return p
	return null

func active_players() -> Array:
	var out: Array = []
	for p in players:
		if p.is_active_this_event:
			out.append(p)
	return out

func to_dict() -> Dictionary:
	var player_dicts: Array = []
	for p in players:
		player_dicts.append(p.to_dict())
	return {
		"event_index": event_index,
		"phase": phase,
		"players": player_dicts,
		"current_event_id": current_event_id,
		"rng_seed": rng_seed,
		"pending_wagers": pending_wagers.duplicate(true),
		"bounties": _serialize_bounties(),
		"current_shop_offer": current_shop_offer.duplicate(),
		"shop_done_peers": shop_done_peers.duplicate(),
		"event_modifiers": event_modifiers.duplicate(true),
		"pending_card_effects": pending_card_effects.duplicate(true),
	}

static func from_dict(d: Dictionary) -> RefCounted:
	var s = load("res://scripts/match/match_state.gd").new()
	s.event_index = d.get("event_index", 0)
	s.phase = d.get("phase", MatchPhase.Phase.HOUSE_REVEAL)
	s.current_event_id = d.get("current_event_id", "")
	s.rng_seed = d.get("rng_seed", 0)
	s.pending_wagers = d.get("pending_wagers", {}).duplicate(true)
	s.bounties = _deserialize_bounties(d.get("bounties", []))
	s.current_shop_offer = d.get("current_shop_offer", []).duplicate()
	s.shop_done_peers = d.get("shop_done_peers", []).duplicate()
	s.event_modifiers = d.get("event_modifiers", {}).duplicate(true)
	s.pending_card_effects = d.get("pending_card_effects", []).duplicate(true)
	s.players = []
	for raw in d.get("players", []):
		s.players.append(MatchPlayer.from_dict(raw))
	return s

const Bounty = preload("res://scripts/match/bounty.gd")

func _serialize_bounties() -> Array:
	var out: Array = []
	for b in bounties:
		# Bounty instances expose to_dict; the live RPC path always populates
		# state.bounties with Bounty refs. Defensive fallback for dicts so
		# tests that seed raw dicts still round-trip.
		if b is Object and b.has_method("to_dict"):
			out.append(b.to_dict())
		else:
			out.append(b.duplicate(true) if b is Dictionary else b)
	return out

static func _deserialize_bounties(raw: Array) -> Array:
	var out: Array = []
	for d in raw:
		if d is Dictionary:
			out.append(Bounty.from_dict(d))
		else:
			out.append(d)
	return out
