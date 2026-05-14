# BotDecisions: static-only helper for Practice-mode bot decisions. Every
# decision point a bot needs (wager amount, cash-out delay, pull-out delay,
# Card Cannon threshold, loadout pick, shop purchase, event-picker path) is
# a pure function that takes a seeded RandomNumberGenerator. That keeps
# behavior reproducible per match (match_seed + bot peer_id), testable in
# isolation, and leaves a clean seam for layering heuristic personalities
# later behind the same signatures.
#
# Follows the static-only Object pattern of HeatRules, PlayerSelectors,
# BountyResolver.
extends Object

# Returns wager in [0, min(max_wager, player_chips)]. Mildly biased toward
# the middle of the legal range (average of two uniform draws) so bots
# rarely pick 0 — that feels like the bot skipped its turn.
static func pick_wager(max_wager: int, player_chips: int, rng: RandomNumberGenerator) -> int:
	var cap: int = min(max_wager, player_chips)
	if cap <= 0:
		return 0
	var a: int = rng.randi_range(0, cap)
	var b: int = rng.randi_range(0, cap)
	return (a + b) / 2

# Rocket Clash: ms after launch when the bot requests cash-out. Range
# 2500-8000.
static func pick_cash_out_delay_ms(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(2500, 8000)

# Bomb Pot: ms after pot open when the bot pulls out. Range 4500-13500
# (~30%-90% of the 15s mid-detonation point).
static func pick_pull_out_delay_ms(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(4500, 13500)

# Card Cannon: locked-score the bot is aiming for before locking in. Range
# 14-19 (below the 21 bust line, mostly above the 14 dealer-stand mark).
static func pick_card_cannon_threshold(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(14, 19)

# BET_LOADOUT loadout selection. Returns up to `max_loadout_size` card ids
# from `hand` via a Fisher-Yates shuffle driven by the supplied rng.
# (Godot's built-in Array.shuffle() uses the global RNG, so we cannot use
# it here — practice-match determinism depends on the seeded rng.)
static func pick_loadout(hand: Array, max_loadout_size: int, rng: RandomNumberGenerator) -> Array:
	if hand.is_empty() or max_loadout_size <= 0:
		return []
	var copy: Array = hand.duplicate()
	# Fisher-Yates: walk from end to start, swap with a random earlier idx.
	for i in range(copy.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = copy[i]
		copy[i] = copy[j]
		copy[j] = tmp
	var n: int = min(max_loadout_size, copy.size())
	return copy.slice(0, n)

# SHOP: return the first offered card id whose cost is <= half the bot's
# chip stack (don't burn half the stack on one buy). "" means skip.
static func pick_shop_purchase(offered_card_ids: Array, offer_costs: Dictionary, player_chips: int, rng: RandomNumberGenerator) -> String:
	var budget: int = int(player_chips / 2)
	for id in offered_card_ids:
		var cost: int = int(offer_costs.get(id, 0))
		if cost <= budget:
			return String(id)
	return ""

# EVENT_PICKER: choose one of the offered paths at random. "" if empty.
static func pick_event_path(options: Array, rng: RandomNumberGenerator) -> String:
	if options.is_empty():
		return ""
	var idx: int = rng.randi() % options.size()
	return String(options[idx])

# Build a per-bot RNG derived from match seed + peer_id so two bots in the
# same match get different streams but the match overall is reproducible
# from match_seed alone. Pure hash: deterministic and stable across runs.
static func rng_for_bot(match_seed: int, bot_peer_id: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = match_seed * 31 + bot_peer_id
	return r
