# Bounty resolver. Extracted from MatchController in Plan B Phase 7.
# Pure state-mutation + return-value style: caller (MatchController)
# handles outbound RPCs based on the return values.
#
# auto_place(state) returns [Bounty, Bounty, ...] of newly placed bounties.
# resolve(state, result) returns [{claimant_peer_id, bounty_dict, reward_chips}, ...].
extends Object

const Bounty = preload("res://scripts/match/bounty.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")
const PlayerSelectors = preload("res://scripts/match/player_selectors.gd")

static func find_chip_leader_peer_id(state) -> int:
	return PlayerSelectors.find_chips_extremum(state, "max", false)

static func find_heat_leader_peer_id(state) -> int:
	var leader = state.players[0] if state.players.size() > 0 else null
	for p in state.players:
		if p.heat > leader.heat:
			leader = p
	return leader.peer_id if leader != null else 0

# Auto-places Leader + Heat bounties (skipped at event_index 0).
# Returns the placed Bounty instances; caller broadcasts via
# _rpc_bounties_placed and emits bounty_placed.
static func auto_place(state) -> Array:
	if state.event_index == 0:
		return []
	state.bounties = []
	var leader_id = find_chip_leader_peer_id(state)
	var heat_id = find_heat_leader_peer_id(state)
	var leader_target = _find_player(state, leader_id)
	var heat_target = _find_player(state, heat_id)
	var leader_bounty = _build_bounty("leader", leader_id, leader_target, state.event_index)
	var heat_bounty = _build_bounty("heat", heat_id, heat_target, state.event_index)
	state.bounties = [leader_bounty, heat_bounty]
	return [leader_bounty, heat_bounty]

# Resolves bounties against an EventResult. Returns awards array of
# {claimant_peer_id, bounty_dict, reward_chips}. Each unclaimed bounty
# returned with claimant_peer_id = 0 (caller broadcasts _rpc_bounty_unclaimed).
# Mutates state.players[claimant].chips and clears state.bounties.
#
# Phase C Change 4 (§8.5): claim_mode dispatcher routes the reward:
# - "survivors" (default, legacy): split across all satisfying survivors.
# - "placer": full reward to placed_by if they survived and condition holds.
# - "saboteur": full reward to result.per_player[target].failure_caused_by
#   if that player survived.
# Unknown claim_modes fall back to "survivors" behavior.
static func resolve(state, result) -> Array:
	var awards: Array = []
	for bounty in state.bounties:
		var claimants: Array = []
		for p in state.players:
			if Bounty.satisfies(bounty, result, p.peer_id):
				claimants.append(p.peer_id)
		if claimants.is_empty():
			awards.append({"claimant_peer_id": 0, "bounty_dict": bounty.to_dict(), "reward_chips": 0})
			continue
		var reward = Bounty.compute_reward(bounty)
		# Sub-project #6 Plan A: Double Bounty twist multiplier (pure
		# state read; Bounty.compute_reward stays unchanged).
		if state.house_twist.get("type", "") == "double_bounty":
			var mult = float(state.house_twist.get("params", {}).get("reward_multiplier", 1.0))
			reward = int(reward * mult)
		# Phase C Change 4: claim_mode dispatch. "placer" / "saboteur" route
		# the full reward to a single recipient; "survivors" (default) uses
		# the existing split path.
		var claim_mode = String(bounty.claim_mode) if "claim_mode" in bounty else "survivors"
		if claim_mode == "placer":
			var placer_id = int(bounty.placed_by)
			if placer_id != 0 and placer_id in claimants:
				var p = _find_player(state, placer_id)
				if p != null:
					p.chips += reward
				awards.append({"claimant_peer_id": placer_id, "bounty_dict": bounty.to_dict(), "reward_chips": reward})
			else:
				# Placer didn't survive or condition didn't hold for them.
				# Personal bounties don't fall through to public split.
				awards.append({"claimant_peer_id": 0, "bounty_dict": bounty.to_dict(), "reward_chips": 0})
			continue
		if claim_mode == "saboteur":
			var target_entry = result.per_player.get(bounty.target, {})
			var caused_by = int(target_entry.get("failure_caused_by", 0))
			if caused_by != 0 and caused_by in claimants:
				var p = _find_player(state, caused_by)
				if p != null:
					p.chips += reward
				awards.append({"claimant_peer_id": caused_by, "bounty_dict": bounty.to_dict(), "reward_chips": reward})
			else:
				awards.append({"claimant_peer_id": 0, "bounty_dict": bounty.to_dict(), "reward_chips": 0})
			continue
		# Default "survivors" path: legacy public-split.
		if claimants.size() == 1:
			var claimant = _find_player(state, claimants[0])
			if claimant != null:
				claimant.chips += reward
			awards.append({"claimant_peer_id": claimants[0], "bounty_dict": bounty.to_dict(), "reward_chips": reward})
		else:
			# Sub-project #7 Plan A Task 9: assign tie-split remainder
			# to lowest-seat_index claimant for deterministic payout.
			# Previously int(reward / claimants.size()) evaporated the
			# modulo (e.g. 100/3 -> 99 paid, 1 lost).
			var split = int(reward / claimants.size())
			var remainder = reward - (split * claimants.size())
			# Find the lowest seat_index among claimants
			var bonus_recipient = claimants[0]
			var bonus_seat = INF
			for c_id in claimants:
				var c = _find_player(state, c_id)
				if c != null and c.seat_index < bonus_seat:
					bonus_seat = c.seat_index
					bonus_recipient = c_id
			for c_id in claimants:
				var c = _find_player(state, c_id)
				var pay = split + (remainder if c_id == bonus_recipient else 0)
				if c != null:
					c.chips += pay
				awards.append({"claimant_peer_id": c_id, "bounty_dict": bounty.to_dict(), "reward_chips": pay})
	state.bounties = []
	return awards

static func _find_player(state, peer_id: int):
	for p in state.players:
		if p.peer_id == peer_id:
			return p
	return null

static func _build_bounty(origin: String, target_peer_id: int, target_player, event_index: int) -> RefCounted:
	var b = Bounty.new()
	b.origin = origin
	b.target = target_peer_id
	b.condition = "bust"
	b.reward_chips = MatchConfig.BOUNTY_BASE_REWARD
	b.placed_at_event = event_index
	b.placed_at_target_heat = target_player.heat if target_player != null else 0
	return b
