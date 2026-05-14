extends GutTest

const EventHelpers = preload("res://scripts/match/event_helpers.gd")
const EventContext = preload("res://scripts/events/event_context.gd")

func _make_context_with_twist(twist_type: String, params: Dictionary) -> RefCounted:
	var ctx = EventContext.new()
	ctx.house_twist = {"type": twist_type, "params": params}
	return ctx

# --- apply_leader_cursed ---

func test_leader_cursed_applies_multiplier_to_leader():
	var ctx = _make_context_with_twist("leader_cursed", {"leader_peer_id": 2, "reward_multiplier": 0.75})
	var out = EventHelpers.apply_leader_cursed(ctx, 2, 100)
	assert_eq(out, 75, "leader's chip_delta multiplied by 0.75")

func test_leader_cursed_no_op_for_non_leader():
	var ctx = _make_context_with_twist("leader_cursed", {"leader_peer_id": 2, "reward_multiplier": 0.75})
	var out = EventHelpers.apply_leader_cursed(ctx, 3, 100)
	assert_eq(out, 100, "non-leader chip_delta unchanged")

func test_leader_cursed_no_op_when_multiplier_is_one():
	var ctx = _make_context_with_twist("leader_cursed", {"leader_peer_id": 2, "reward_multiplier": 1.0})
	var out = EventHelpers.apply_leader_cursed(ctx, 2, 100)
	assert_eq(out, 100, "mult == 1.0 short-circuits (returns input unchanged)")

func test_leader_cursed_no_op_when_twist_inactive():
	var ctx = _make_context_with_twist("double_bounty", {"reward_multiplier": 2.0})
	var out = EventHelpers.apply_leader_cursed(ctx, 2, 100)
	assert_eq(out, 100, "non-leader_cursed twist no-op")

func test_leader_cursed_null_context_returns_input():
	var out = EventHelpers.apply_leader_cursed(null, 2, 100)
	assert_eq(out, 100, "null context returns input chip_delta unchanged")

# --- apply_sudden_death_bonus ---

func test_sudden_death_bonus_awards_crown_when_survives_and_condition_matches():
	var ctx = _make_context_with_twist("sudden_death_jackpot", {"condition": "cash_out_over_5x"})
	var per_player = {2: {"crown_delta": 1}}
	EventHelpers.apply_sudden_death_bonus(ctx, 2, per_player, "cash_out_over_5x", true)
	assert_eq(int(per_player[2].crown_delta), 2, "crown_delta increments from 1 to 2")

func test_sudden_death_bonus_no_op_when_condition_mismatches():
	var ctx = _make_context_with_twist("sudden_death_jackpot", {"condition": "pull_out_after_80_pct"})
	var per_player = {2: {"crown_delta": 1}}
	EventHelpers.apply_sudden_death_bonus(ctx, 2, per_player, "cash_out_over_5x", true)
	assert_eq(int(per_player[2].crown_delta), 1, "wrong condition leaves crown_delta untouched")

func test_sudden_death_bonus_no_op_when_survives_false():
	var ctx = _make_context_with_twist("sudden_death_jackpot", {"condition": "cash_out_over_5x"})
	var per_player = {2: {"crown_delta": 0}}
	EventHelpers.apply_sudden_death_bonus(ctx, 2, per_player, "cash_out_over_5x", false)
	assert_eq(int(per_player[2].crown_delta), 0, "survives=false suppresses the bonus")

func test_sudden_death_bonus_no_op_when_twist_inactive():
	var ctx = _make_context_with_twist("double_bounty", {"reward_multiplier": 2.0})
	var per_player = {2: {"crown_delta": 0}}
	EventHelpers.apply_sudden_death_bonus(ctx, 2, per_player, "cash_out_over_5x", true)
	assert_eq(int(per_player[2].crown_delta), 0, "non-Sudden-Death twist no-op")
