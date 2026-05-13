# Shop controller helpers. Extracted from MatchController in Plan B
# Phase 7. Pure state mutation; caller handles RPC outbound.
extends Object

const CardRegistry = preload("res://scripts/cards/card_registry.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")

# Initialize shop: shuffle pool, slice SHOP_OFFER_SIZE, clear done peers.
# Returns a copy of the offer for the caller to broadcast.
static func open(state) -> Array:
	var pool = CardRegistry.shop_pool().duplicate()
	pool.shuffle()
	state.current_shop_offer = pool.slice(0, min(MatchConfig.SHOP_OFFER_SIZE, pool.size()))
	state.shop_done_peers = []
	return state.current_shop_offer.duplicate()

# Close shop: clear offer + done peers.
static func close(state) -> void:
	state.current_shop_offer = []
	state.shop_done_peers = []

# Check whether all active peers have marked themselves done.
static func all_active_done(state) -> bool:
	for p in state.players:
		if p.is_active_this_event and not (p.peer_id in state.shop_done_peers):
			return false
	return true

# Validate a buy attempt. Returns dict with status string + cost (if applicable):
#   {status: "ok", cost: int}
#   {status: "not_in_offer"}
#   {status: "already_done"}
#   {status: "no_such_player"}
#   {status: "insufficient_chips", cost: int}
#   {status: "hand_full", cost: int}
static func validate_buy(state, peer_id: int, card_id: String) -> Dictionary:
	if not (card_id in state.current_shop_offer):
		return {"status": "not_in_offer"}
	if peer_id in state.shop_done_peers:
		return {"status": "already_done"}
	var player = _find_player(state, peer_id)
	if player == null:
		return {"status": "no_such_player"}
	var cost = _card_cost(card_id)
	if player.chips < cost:
		return {"status": "insufficient_chips", "cost": cost}
	if player.hand.size() >= MatchConfig.MAX_HAND_SIZE:
		return {"status": "hand_full", "cost": cost}
	return {"status": "ok", "cost": cost}

# Apply a validated buy: deduct chips, append to hand, mark peer done.
static func apply_buy(state, peer_id: int, card_id: String, cost: int) -> void:
	var player = _find_player(state, peer_id)
	if player == null:
		return
	player.chips -= cost
	player.hand.append(card_id)
	if not (peer_id in state.shop_done_peers):
		state.shop_done_peers.append(peer_id)

static func _card_cost(card_id: String) -> int:
	var card = CardRegistry.get_card(card_id)
	return int(card.get("cost_chips", 0))

static func _find_player(state, peer_id: int):
	for p in state.players:
		if p.peer_id == peer_id:
			return p
	return null
