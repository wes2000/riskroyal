# House Twist controller. Selects + computes params + applies eager
# effects for the 6 MVP twists. Extracted as a static-only helper per
# sub-project #4's collaborator pattern (BountyResolver, ShopController,
# CardEffectDispatcher, MatchRpcSender).
#
# Consumers read state.house_twist keys directly (no dispatcher branches);
# this controller only handles selection + params at HOUSE_TWIST phase.
extends Object

const CardRegistry = preload("res://scripts/cards/card_registry.gd")

# Full 6-twist pool. Plan A implements 4 (double_bounty, no_insurance,
# leader_cursed, power_surge); Plan B adds lowest_chips_picks + sudden_death_jackpot.
const TWIST_POOL: Array = [
	"double_bounty",
	"no_insurance",
	"leader_cursed",
	"power_surge",
	"lowest_chips_picks",
	"sudden_death_jackpot",
]

# Picks the next twist uniformly from the pool, with no-repeat filter
# (excludes state.last_twist_type) and degenerate-case filters
# (lowest_chips_picks + leader_cursed excluded when all peers have
# equal chips).
static func select_next_twist(state) -> Dictionary:
	var pool = TWIST_POOL.duplicate()
	# No-repeat filter
	if state.last_twist_type != "":
		pool.erase(state.last_twist_type)
	# Degenerate filter: equal-chips twists require unequal chips
	if _all_chips_equal(state):
		pool.erase("lowest_chips_picks")
		pool.erase("leader_cursed")
	# Defensive: fall back to full pool if filters emptied the candidates
	if pool.is_empty():
		pool = TWIST_POOL.duplicate()
	var idx = state.rng.randi() % pool.size()
	var twist_type = pool[idx]
	return {
		"type": twist_type,
		"params": compute_twist_params(twist_type, state),
	}

# Per-twist params builder. Plan A twists are state-only; Plan B's
# lowest_chips_picks + sudden_death_jackpot will return richer params
# (picker_peer_id, options, condition string).
static func compute_twist_params(twist_type: String, state) -> Dictionary:
	match twist_type:
		"double_bounty":
			return {
				"reward_multiplier": 2.0,
				"place_bounty_discount": 0.25,
			}
		"no_insurance":
			return {}
		"leader_cursed":
			var leader_id = _find_chip_leader_peer_id(state)
			return {
				"leader_peer_id": leader_id,
				"reward_multiplier": 0.75,
			}
		"power_surge":
			# cards_dealt populated by apply_pre_event_effects below
			return {"cards_dealt": {}}
		"lowest_chips_picks":
			# Plan B will populate picker_peer_id + options
			return {"timeout_sec": 10}
		"sudden_death_jackpot":
			# Plan B will populate condition (lazy per the spec § 7.6)
			return {"condition": ""}
		_:
			push_warning("HouseTwistController: unknown twist type: %s" % twist_type)
			return {}

# Eager state mutations at HOUSE_TWIST phase. Power Surge deals
# +1 bonus card from CardRegistry.starter_pool() to every active peer's
# hand. Other Plan A twists are pure state flags (no mutation needed).
static func apply_pre_event_effects(state, twist: Dictionary) -> void:
	match twist.get("type", ""):
		"power_surge":
			var pool = CardRegistry.starter_pool()
			if pool.is_empty():
				return
			var cards_dealt: Dictionary = {}
			for p in state.players:
				if not p.is_active_this_event:
					continue
				var idx = state.rng.randi() % pool.size()
				var card_id = pool[idx]
				p.hand.append(card_id)  # intentionally bypasses MAX_HAND_SIZE
				cards_dealt[p.peer_id] = card_id
			twist["params"]["cards_dealt"] = cards_dealt

# Helpers

static func _all_chips_equal(state) -> bool:
	if state.players.size() <= 1:
		return true
	var first_chips = state.players[0].chips
	for p in state.players:
		if p.chips != first_chips:
			return false
	return true

# Computes the chip leader peer_id with deterministic tie-break by
# lower seat_index. Diverges from BountyResolver.find_chip_leader_peer_id
# (which uses first-encountered traversal order in ties); the two are
# not currently consolidated because BountyResolver's tie behavior is
# tolerated for bounty placement, while leader_cursed needs determinism
# for replayability.
static func _find_chip_leader_peer_id(state) -> int:
	if state.players.is_empty():
		return 0
	var leader = state.players[0]
	for p in state.players:
		if p.chips > leader.chips:
			leader = p
		elif p.chips == leader.chips and p.seat_index < leader.seat_index:
			leader = p  # seat_index tie-break
	return leader.peer_id
