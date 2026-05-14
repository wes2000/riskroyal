# Static-only helpers for consumer-side House Twist boilerplate. Extracted
# from the inlined Leader Cursed + Sudden Death blocks duplicated across
# Rocket Clash, Bomb Pot, and Card Cannon's compute_event_result. Follows
# the sub-project #4 collaborator pattern (BountyResolver, ShopController,
# CardEffectDispatcher, MatchRpcSender, HouseTwistController).
#
# Caller still owns the for-player loop and the event-specific condition
# evaluation. The helpers absorb the outer twist-type guard and the per-
# player mutation.
extends Object

# Apply Leader Cursed multiplier to chip_delta if the active twist is
# leader_cursed AND the given peer_id is the cursed leader. Returns the
# (possibly modified) chip_delta. Callers replace the 7-line inline block
# in compute_event_result with: `chip_delta = EventHelpers.apply_leader_cursed(context, pid, chip_delta)`.
static func apply_leader_cursed(context, pid: int, chip_delta: int) -> int:
	if context == null:
		return chip_delta
	var ht = context.house_twist
	if ht.get("type", "") != "leader_cursed":
		return chip_delta
	var leader_id = int(ht.get("params", {}).get("leader_peer_id", 0))
	if pid != leader_id:
		return chip_delta
	var mult = float(ht.get("params", {}).get("reward_multiplier", 1.0))
	if mult == 1.0:
		return chip_delta
	return int(chip_delta * mult)

# Apply Sudden Death Jackpot bonus crown for a single player if the
# active twist is sudden_death_jackpot AND the param condition matches
# expected_condition AND the caller's per-event check (survives) is true.
# Mutates per_player[pid].crown_delta in place. No-op otherwise.
#
# survives is the caller's pre-evaluated boolean — keeps this helper
# event-agnostic (the per-event condition uses event-private state like
# cash_outs / pull_out_timestamps / locked_scores that we don't want to
# leak into the helper).
static func apply_sudden_death_bonus(
	context, pid: int, per_player: Dictionary, expected_condition: String,
	survives: bool
) -> void:
	if context == null or not survives:
		return
	var ht = context.house_twist
	if ht.get("type", "") != "sudden_death_jackpot":
		return
	var actual = String(ht.get("params", {}).get("condition", ""))
	if actual != expected_condition:
		return
	if not per_player.has(pid):
		return  # defensive — caller hasn't populated this pid yet
	per_player[pid].crown_delta = int(per_player[pid].get("crown_delta", 0)) + 1
