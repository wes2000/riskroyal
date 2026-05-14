# Polish Pass Plan A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close accumulated carry-forward debt from sub-projects #2-6 so Plan B's UX polish lands on a tidy codebase. Two new helper classes (`EventHelpers`, `PlayerSelectors`); numeric edge cases; RPC bandwidth optimization.

**Architecture:** Spec §5. Refactor cluster (Tasks 1-6): extract 6 inlined twist-consumer blocks into `EventHelpers`; consolidate 3 find-chips-extremum near-clones into `PlayerSelectors`; clean redundant `"in context"` guards. Numeric edge cases (Tasks 7-9): Bomb Pot sentinel, Heat Shield doc, bounty tie-split modulo. RPC bandwidth + arity (Tasks 10-12): MatchRpcSender `callv` rewrite, starter pack per-peer narrowing, client→host `rpc_id`.

**Tech Stack:** Godot 4.6 + GDScript; GUT testing; host-authoritative @rpc.

---

## Notes for the implementer

- **Baseline test count:** sub-project #6 merged at **564 unit + 7 integration**. Per-task expected counts roll forward: 564 → 573 → 573 → 573 → 573 → 578 → 578 → 579 → 579 → 580 → 582 → 583 → **586** at end of Task 12.
- **FakeMultiplayerNode already discriminates `rpc` vs `rpc_id` calls.** Inspect `tests/fakes/fake_multiplayer_node.gd`: `rpc(...)` appends `{method, args}`; `rpc_id(...)` appends `{method, peer_id, args}`. Task 12's tests can assert on the presence of `peer_id` (or check both methods' arrays). Task 10 extends the fake to 6-arg slots; no further fake extension needed for Task 12.
- **Defensive dict access throughout.** Use `state.house_twist.get("params", {}).get("key", default)` style. Test fixtures replicate the `_new_state_with_players` / `_make_player` / `_make_context` helpers from sibling test files as needed.
- **Tabs, not spaces.** All GDScript snippets use literal tab characters. No `class_name`; use `preload()` for type imports.
- **Commit messages use `git commit -F - <<'EOF'` heredoc form.** This is the only form that survives PowerShell 5.1's quoting quirks reliably. Each commit message is 2-5 sentences explaining WHY, not just WHAT.
- **Refactor preserves behavior.** Tasks 1-6 do not change game semantics. If any existing test fails after a refactor, the refactor is wrong — debug, don't rewrite the test.

---

## Phase 1: Refactor cluster (Tasks 1-6)

### Task 1: Create `EventHelpers` static helper class

Two new pure-static helpers absorbing the boilerplate guards that wrap the 3 events' Leader Cursed and Sudden Death Jackpot consumer blocks. The caller still owns the per-player loop and the event-specific condition evaluation; the helpers absorb the outer `if ht.get("type") == ...` guard + the `int(chip_delta * mult)` / `crown_delta += 1` mutation.

**Files:**
- Create: `scripts/match/event_helpers.gd`
- Create: `tests/unit/test_event_helpers.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_event_helpers.gd`:
```gdscript
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
```

(Note: there are 9 `test_*` functions above. GUT counts test functions, so this task adds **9** new tests. Per-task rolling count below reflects +9.)

- [ ] **Step 2: Run, watch fail**

```
godot --headless --path c:/Users/whann/Desktop/Games/RocketMan -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
```

Expected: preload error for `event_helpers.gd` (file doesn't exist).

- [ ] **Step 3: Implement**

Create `scripts/match/event_helpers.gd`:
```gdscript
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
```

- [ ] **Step 4: Run, watch pass**

Expected: **573/573 tests pass** (564 prior + 9 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/match/event_helpers.gd tests/unit/test_event_helpers.gd
git commit -F - <<'EOF'
feat(client): EventHelpers static helper for House Twist consumer DRY

Closes the longest-standing carry-forward from sub-project #6 Plan B
final review: 3 events' compute_event_result contain near-identical
Leader Cursed (7-line) and Sudden Death Jackpot (~10-line) consumer
blocks. Extract into two static helpers:

- apply_leader_cursed(context, pid, chip_delta) -> int
- apply_sudden_death_bonus(context, pid, per_player, expected_condition,
  survives) -> void

The helpers absorb the outer twist-type guard plus the per-player
mutation; callers still own their for-player loops and the event-
specific survival checks (those use event-private state like cash_outs
or pull_out_timestamps that we don't want to leak into the helper).

Tasks 2-4 replace the inlined blocks with one-call-per-player helper
invocations.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 2: Replace Rocket Clash inline twist blocks with EventHelpers calls

Behavior-preserving refactor. Rocket Clash's `compute_event_result` currently has 2 inlined twist blocks (Leader Cursed at ~lines 279-284, Sudden Death at ~lines 318-328). Replace both with EventHelpers calls. All existing tests must continue to pass — including `test_rocket_clash_leader_cursed.gd` and `test_rocket_clash_sudden_death.gd`.

**Files:**
- Modify: `scripts/events/rocket_clash/rocket_clash_event.gd`

- [ ] **Step 1: Confirm baseline**

```
godot --headless --path c:/Users/whann/Desktop/Games/RocketMan -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
```

Expected: 573/573 (matches Task 1's commit).

- [ ] **Step 2: Add EventHelpers preload**

At the top of `scripts/events/rocket_clash/rocket_clash_event.gd`, near the other preloads (e.g. next to `const EventResult = preload(...)`), add:

```gdscript
const EventHelpers = preload("res://scripts/match/event_helpers.gd")
```

- [ ] **Step 3: Replace the Leader Cursed inline block**

In `compute_event_result`, find the existing block (after the Underdog multiplier, before the Late Cash bonus):

```gdscript
			# Sub-project #6 Plan A: Leader Cursed reduces leader's survivor reward
			if context != null:
				var ht = context.house_twist
				if ht.get("type", "") == "leader_cursed" and int(ht.get("params", {}).get("leader_peer_id", 0)) == pid:
					var lc_mult = float(ht.get("params", {}).get("reward_multiplier", 1.0))
					if lc_mult != 1.0:
						chip_delta = int(chip_delta * lc_mult)
```

Replace with the single helper call:

```gdscript
			# Sub-project #7 Plan A Task 2: Leader Cursed via EventHelpers
			chip_delta = EventHelpers.apply_leader_cursed(context, pid, chip_delta)
```

- [ ] **Step 4: Replace the Sudden Death inline block**

Find the block after the Crown award (around lines 314-328):

```gdscript
		# Sub-project #6 Plan B Task 7: Sudden Death Jackpot bonus crown.
		# Each surviving player whose cash_out > 5.0 earns +1 crown_delta
		# (stacks with regular Crown — only place where crown_delta = 2).
		# Sub-project #7: extract to EventHelpers.apply_sudden_death_bonus.
		if context != null:
			var ht = context.house_twist
			if ht.get("type", "") == "sudden_death_jackpot" \
					and String(ht.get("params", {}).get("condition", "")) == "cash_out_over_5x":
				for player in context.players:
					var pid = player.peer_id
					if busted.has(pid):
						continue
					var co = float(cash_outs.get(pid, 0.0))
					if co > 5.0:
						result.per_player[pid].crown_delta = int(result.per_player[pid].get("crown_delta", 0)) + 1
```

Replace with the helper-driven per-player loop:

```gdscript
		# Sub-project #7 Plan A Task 2: Sudden Death Jackpot via EventHelpers
		for player in context.players:
			var pid = player.peer_id
			var survives = not busted.has(pid) and float(cash_outs.get(pid, 0.0)) > 5.0
			EventHelpers.apply_sudden_death_bonus(context, pid, result.per_player, "cash_out_over_5x", survives)
```

- [ ] **Step 5: Run, verify zero regressions**

Expected: **573/573 tests still pass** (no count change — refactor only). If any Rocket Clash test fails, the most likely culprit is the inner-loop `pid` variable shadowing — the new block re-declares `pid` inside the `for player in context.players:` loop. If the surrounding scope already has a `pid` (it does, from the earlier survivor loop), GDScript is fine with the re-declaration since the new `for` introduces a new scope. Verify by reading the file end-to-end.

- [ ] **Step 6: Commit**

```bash
git add scripts/events/rocket_clash/rocket_clash_event.gd
git commit -F - <<'EOF'
refactor(client): Rocket Clash uses EventHelpers for twist consumers

Replaces 2 inlined twist-consumer blocks (Leader Cursed, Sudden Death
Jackpot) with single EventHelpers calls. Leader Cursed becomes a
one-line replacement inside the survivor loop; Sudden Death becomes a
3-line per-player loop with the helper consuming the twist-type guard.

Behavior preserved. All 573 tests still passing, including the
test_rocket_clash_leader_cursed and test_rocket_clash_sudden_death
suites that verify the precise chip_delta + crown_delta math.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 3: Replace Bomb Pot inline twist blocks with EventHelpers calls

Same shape as Task 2 for Bomb Pot. Note: Sudden Death's `survives` condition for Bomb Pot needs a precomputed `threshold_ms` outside the loop (Bomb Pot's per-event condition is `pull_out_timestamps[pid] >= bomb_at_sec * 1000 * 0.80`).

**Files:**
- Modify: `scripts/events/bomb_pot/bomb_pot_event.gd`

- [ ] **Step 1: Add EventHelpers preload**

At the top of `scripts/events/bomb_pot/bomb_pot_event.gd`, near the other preloads:

```gdscript
const EventHelpers = preload("res://scripts/match/event_helpers.gd")
```

- [ ] **Step 2: Replace the Leader Cursed inline block**

In `compute_event_result`, find the block at ~lines 190-196 inside the survivor branch:

```gdscript
			# Sub-project #6 Plan A: Leader Cursed reduces leader's survivor reward
			if context != null:
				var ht = context.house_twist
				if ht.get("type", "") == "leader_cursed" and int(ht.get("params", {}).get("leader_peer_id", 0)) == pid:
					var lc_mult = float(ht.get("params", {}).get("reward_multiplier", 1.0))
					if lc_mult != 1.0:
						chip_delta = int(chip_delta * lc_mult)
```

Replace with:

```gdscript
			# Sub-project #7 Plan A Task 3: Leader Cursed via EventHelpers
			chip_delta = EventHelpers.apply_leader_cursed(context, pid, chip_delta)
```

- [ ] **Step 3: Replace the Sudden Death inline block**

Find the block at ~lines 241-256 (after the last-puller Crown award):

```gdscript
		# Sub-project #6 Plan B Task 8: Sudden Death Jackpot bonus crown.
		# Each surviving puller whose pull-out timestamp >= 80% of bomb_at_sec
		# earns +1 crown_delta. Stacks with the regular last-puller Crown.
		# Sub-project #7: extract to EventHelpers.apply_sudden_death_bonus.
		if context != null:
			var ht = context.house_twist
			if ht.get("type", "") == "sudden_death_jackpot" \
					and String(ht.get("params", {}).get("condition", "")) == "pull_out_after_80_pct":
				var threshold_ms = bomb_at_sec * 1000.0 * 0.80
				for player in context.players:
					var pid = player.peer_id
					if not (pid in pulled_out_peers):
						continue  # busts don't qualify
					var ts = float(pull_out_timestamps.get(pid, 0))
					if ts >= threshold_ms:
						result.per_player[pid].crown_delta = int(result.per_player[pid].get("crown_delta", 0)) + 1
```

Replace with (note threshold_ms precomputed outside loop, no twist-type guard needed since helper handles it):

```gdscript
		# Sub-project #7 Plan A Task 3: Sudden Death Jackpot via EventHelpers
		var threshold_ms = bomb_at_sec * 1000.0 * 0.80
		for player in context.players:
			var pid = player.peer_id
			var survives = (pid in pulled_out_peers) and float(pull_out_timestamps.get(pid, 0)) >= threshold_ms
			EventHelpers.apply_sudden_death_bonus(context, pid, result.per_player, "pull_out_after_80_pct", survives)
```

- [ ] **Step 4: Run, verify zero regressions**

Expected: **573/573 tests still pass**.

- [ ] **Step 5: Commit**

```bash
git add scripts/events/bomb_pot/bomb_pot_event.gd
git commit -F - <<'EOF'
refactor(client): Bomb Pot uses EventHelpers for twist consumers

Same pattern as Rocket Clash. Leader Cursed becomes a one-line helper
call inside the survivor branch. Sudden Death becomes a per-player
loop with threshold_ms precomputed outside; helper absorbs the
twist-type + condition guards.

The threshold_ms precompute is a micro-optimization preserved from
the original block — bomb_at_sec * 1000 * 0.80 is hoisted out so it
doesn't recompute per peer.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 4: Replace Card Cannon inline twist blocks with EventHelpers calls

Same shape as Tasks 2-3 for Card Cannon. Sudden Death condition is `locked_scores[pid] == 21`.

**Files:**
- Modify: `scripts/events/card_cannon/card_cannon_event.gd`

- [ ] **Step 1: Add EventHelpers preload**

```gdscript
const EventHelpers = preload("res://scripts/match/event_helpers.gd")
```

- [ ] **Step 2: Replace the Leader Cursed inline block**

Find at ~lines 226-232 (in the survivor branch):

```gdscript
			# Sub-project #6 Plan A: Leader Cursed reduces leader's survivor reward
			if context != null:
				var ht = context.house_twist
				if ht.get("type", "") == "leader_cursed" and int(ht.get("params", {}).get("leader_peer_id", 0)) == pid:
					var lc_mult = float(ht.get("params", {}).get("reward_multiplier", 1.0))
					if lc_mult != 1.0:
						chip_delta = int(chip_delta * lc_mult)
```

Replace with:

```gdscript
			# Sub-project #7 Plan A Task 4: Leader Cursed via EventHelpers
			chip_delta = EventHelpers.apply_leader_cursed(context, pid, chip_delta)
```

- [ ] **Step 3: Replace the Sudden Death inline block**

Find at ~lines 255-268 (after the Crown award):

```gdscript
		# Sub-project #6 Plan B Task 9: Sudden Death Jackpot bonus crown.
		# Each surviving player whose locked score equals exactly 21 earns
		# +1 crown_delta. Stacks with the regular highest-locked-score
		# Crown. Sub-project #7: extract to EventHelpers.apply_sudden_death_bonus.
		if context != null:
			var ht = context.house_twist
			if ht.get("type", "") == "sudden_death_jackpot" \
					and String(ht.get("params", {}).get("condition", "")) == "locked_at_perfect":
				for player in context.players:
					var pid = player.peer_id
					if busted.get(pid, false):
						continue
					if int(locked_scores.get(pid, 0)) == 21:
						result.per_player[pid].crown_delta = int(result.per_player[pid].get("crown_delta", 0)) + 1
```

Replace with:

```gdscript
		# Sub-project #7 Plan A Task 4: Sudden Death Jackpot via EventHelpers
		for player in context.players:
			var pid = player.peer_id
			var survives = not busted.get(pid, false) and int(locked_scores.get(pid, 0)) == 21
			EventHelpers.apply_sudden_death_bonus(context, pid, result.per_player, "locked_at_perfect", survives)
```

- [ ] **Step 4: Run, verify zero regressions**

Expected: **573/573 tests still pass**.

- [ ] **Step 5: Commit**

```bash
git add scripts/events/card_cannon/card_cannon_event.gd
git commit -F - <<'EOF'
refactor(client): Card Cannon uses EventHelpers for twist consumers

Completes the 3-event refactor. Leader Cursed becomes a one-line
helper call inside the survivor branch. Sudden Death becomes a
per-player loop with the helper consuming the twist-type +
condition + locked_at_perfect guards.

All 573 tests still passing. The 6 inlined twist-consumer blocks
across Rocket Clash, Bomb Pot, and Card Cannon are now replaced by
6 helper invocations — net ~35 lines removed, semantics preserved.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 5: Create `PlayerSelectors` + delegate from 3 existing find-chip-extremum sites

`BountyResolver.find_chip_leader_peer_id` (max, no tie-break), `HouseTwistController._find_chip_leader_peer_id` (max, tie-break), and `HouseTwistController._find_lowest_chips_peer_id` (min, tie-break) are 3 near-clone implementations. Extract a single parameterized helper `PlayerSelectors.find_chips_extremum(state, direction, tie_break)`, keep the existing 3 functions as 1-line delegations so no call sites change.

**Files:**
- Create: `scripts/match/player_selectors.gd`
- Create: `tests/unit/test_player_selectors.gd`
- Modify: `scripts/match/bounty_resolver.gd`
- Modify: `scripts/match/house_twist_controller.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_player_selectors.gd`:
```gdscript
extends GutTest

const PlayerSelectors = preload("res://scripts/match/player_selectors.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _new_state(chips_array: Array, seat_indices: Array = []) -> RefCounted:
	var s = MatchState.new()
	for i in chips_array.size():
		var p = MatchPlayer.new()
		p.peer_id = i + 1
		p.seat_index = seat_indices[i] if i < seat_indices.size() else i
		p.chips = chips_array[i]
		s.players.append(p)
	return s

func test_find_max_returns_highest_chips_peer():
	var s = _new_state([300, 700, 500])  # P2 wins
	assert_eq(PlayerSelectors.find_chips_extremum(s, "max", false), 2)

func test_find_max_with_tie_break_picks_lowest_seat_index():
	# P1 and P3 tied at 700; P1 has seat_index 0, P3 has seat_index 2 -> P1 wins
	var s = _new_state([700, 300, 700], [0, 1, 2])
	assert_eq(PlayerSelectors.find_chips_extremum(s, "max", true), 1,
		"tie-break picks lowest seat_index (P1 over P3)")

func test_find_min_with_tie_break_picks_lowest_seat_index():
	# P1 and P3 tied at 300; P1 has seat_index 0 -> P1 wins
	var s = _new_state([300, 700, 300], [0, 1, 2])
	assert_eq(PlayerSelectors.find_chips_extremum(s, "min", true), 1,
		"min direction with tie-break picks lowest seat_index")

func test_empty_state_returns_zero():
	var s = MatchState.new()  # players is []
	assert_eq(PlayerSelectors.find_chips_extremum(s, "max", true), 0)
	assert_eq(PlayerSelectors.find_chips_extremum(s, "min", true), 0)

func test_single_player_returns_that_peer():
	var s = _new_state([500])
	assert_eq(PlayerSelectors.find_chips_extremum(s, "max", true), 1)
	assert_eq(PlayerSelectors.find_chips_extremum(s, "min", true), 1)
```

- [ ] **Step 2: Run, watch fail**

Expected: preload error for `player_selectors.gd`.

- [ ] **Step 3: Implement `PlayerSelectors`**

Create `scripts/match/player_selectors.gd`:
```gdscript
# Static-only chip-extremum helpers. Extracted from the 3 near-clone
# functions in BountyResolver + HouseTwistController. Follows the
# sub-project #4 collaborator pattern.
#
# direction: "max" or "min"; tie_break: if true, lower seat_index wins
# ties; if false, first-encountered traversal order wins (matches the
# legacy BountyResolver.find_chip_leader_peer_id behavior).
extends Object

static func find_chips_extremum(state, direction: String, tie_break: bool) -> int:
	if state.players.is_empty():
		return 0
	var best = state.players[0]
	for p in state.players:
		var wins: bool = false
		if direction == "max":
			wins = p.chips > best.chips
		else:
			wins = p.chips < best.chips
		if wins:
			best = p
		elif tie_break and p.chips == best.chips and p.seat_index < best.seat_index:
			best = p
	return best.peer_id
```

- [ ] **Step 4: Delegate from `BountyResolver.find_chip_leader_peer_id`**

In `scripts/match/bounty_resolver.gd`, add the preload near the existing preloads:

```gdscript
const PlayerSelectors = preload("res://scripts/match/player_selectors.gd")
```

Replace the existing function body:

```gdscript
static func find_chip_leader_peer_id(state) -> int:
	var leader = state.players[0] if state.players.size() > 0 else null
	for p in state.players:
		if p.chips > leader.chips:
			leader = p
	return leader.peer_id if leader != null else 0
```

with the 1-line delegation:

```gdscript
static func find_chip_leader_peer_id(state) -> int:
	return PlayerSelectors.find_chips_extremum(state, "max", false)
```

(Note: BountyResolver's legacy behavior is no tie-break — preserve it. If a future review wants to upgrade BountyResolver to tie-break for consistency, that's an out-of-scope change.)

- [ ] **Step 5: Delegate from `HouseTwistController._find_chip_leader_peer_id` and `_find_lowest_chips_peer_id`**

In `scripts/match/house_twist_controller.gd`, add the preload near the existing preloads:

```gdscript
const PlayerSelectors = preload("res://scripts/match/player_selectors.gd")
```

Replace `_find_chip_leader_peer_id`:

```gdscript
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
```

with:

```gdscript
static func _find_chip_leader_peer_id(state) -> int:
	return PlayerSelectors.find_chips_extremum(state, "max", true)
```

And replace `_find_lowest_chips_peer_id`:

```gdscript
static func _find_lowest_chips_peer_id(state) -> int:
	if state.players.is_empty():
		return 0
	var lowest = state.players[0]
	for p in state.players:
		if p.chips < lowest.chips:
			lowest = p
		elif p.chips == lowest.chips and p.seat_index < lowest.seat_index:
			lowest = p  # seat_index tie-break
	return lowest.peer_id
```

with:

```gdscript
static func _find_lowest_chips_peer_id(state) -> int:
	return PlayerSelectors.find_chips_extremum(state, "min", true)
```

The function names stay so existing call sites + tests against `BountyResolver.find_chip_leader_peer_id` and `HouseTwistController._find_chip_leader_peer_id` / `_find_lowest_chips_peer_id` continue to work unchanged. Update the leading comment block on `_find_chip_leader_peer_id` (the "Diverges from BountyResolver.find_chip_leader_peer_id..." paragraph) to note the divergence is now intentional and explicit via the `tie_break` flag passed to `PlayerSelectors`.

- [ ] **Step 6: Run, watch pass**

Expected: **578/578 tests pass** (573 prior + 5 new). All `test_bounty_resolver.gd` + `test_house_twist_controller*.gd` tests must continue to pass against the delegated implementations.

- [ ] **Step 7: Commit**

```bash
git add scripts/match/player_selectors.gd scripts/match/bounty_resolver.gd scripts/match/house_twist_controller.gd tests/unit/test_player_selectors.gd
git commit -F - <<'EOF'
feat(client): PlayerSelectors + delegate 3 find-chips-extremum sites

Closes the find_chip_leader consolidation carry-forward from
sub-project #6 final review. The 3 near-clone implementations
(BountyResolver.find_chip_leader_peer_id, HouseTwistController.
_find_chip_leader_peer_id, HouseTwistController._find_lowest_chips_
peer_id) now delegate to a single parameterized helper:

  PlayerSelectors.find_chips_extremum(state, direction, tie_break)

direction = "max" | "min"; tie_break = lower seat_index wins ties
(when true) or first-encountered order wins (when false, matching
BountyResolver's legacy behavior).

The 3 existing function bodies become 1-line delegations. No call
sites change — the wrappers preserve their pre-existing APIs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 6: Drop redundant `"event_modifiers" in context:` guards in 3 events

`EventContext` declares `event_modifiers` as a typed field (always present, default `{}`). The 3 events' `compute_event_result` open with a defensive `if context != null and "event_modifiers" in context:` guard where the membership check is dead code copied from an older Dictionary-style pattern. Drop it.

**Files:**
- Modify: `scripts/events/rocket_clash/rocket_clash_event.gd`
- Modify: `scripts/events/bomb_pot/bomb_pot_event.gd`
- Modify: `scripts/events/card_cannon/card_cannon_event.gd`

- [ ] **Step 1: Confirm the guard pattern**

In each of the 3 event scripts' `compute_event_result`, locate the line near the top of the function:

```gdscript
	var modifiers = {}
	if context != null and "event_modifiers" in context:
		modifiers = context.event_modifiers
```

- [ ] **Step 2: Simplify the guard (3 files)**

Replace each occurrence with:

```gdscript
	var modifiers = {}
	if context != null:
		modifiers = context.event_modifiers
```

(The remaining `context != null` guard stays — Plan A tests pass `context = null` in some unit-test fixtures. Preserve that safety.)

Apply identically to all 3 files. No other lines change.

- [ ] **Step 3: Run, verify zero regressions**

Expected: **578/578 tests still pass**.

- [ ] **Step 4: Commit**

```bash
git add scripts/events/rocket_clash/rocket_clash_event.gd scripts/events/bomb_pot/bomb_pot_event.gd scripts/events/card_cannon/card_cannon_event.gd
git commit -F - <<'EOF'
refactor(client): drop redundant "event_modifiers" in context guards

The 3 events' compute_event_result opened with
`if context != null and "event_modifiers" in context:`. The membership
check is dead code: EventContext declares event_modifiers as a typed
field (default {}), so the `in` operator is always true on a non-null
context. Simplifies to `if context != null:` — the null guard stays
because unit-test fixtures pass null contexts in a few places.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 2: Numeric edge cases (Tasks 7-9)

### Task 7: Bomb Pot `winner_pull_out_ms = -1` sentinel hardening

The current `winner_pull_out_ms` initializes to `-1` (sentinel). The host-side last-puller tracking is gated by `if pid in pulled_out_peers:` so the comparison `ts > winner_pull_out_ms` only ever runs for actual pullers — meaning the `-1` is currently safe. But the implicit invariant (puller-gating outside the comparison) is fragile to future refactors. Switch to an explicit `has_winner` flag so the invariant becomes load-bearing and verifiable. Add 1 test for the no-puller case.

**Files:**
- Modify: `scripts/events/bomb_pot/bomb_pot_event.gd`
- Create: `tests/unit/test_bomb_pot_no_winner_when_no_pullers.gd`

- [ ] **Step 1: Write failing test**

`tests/unit/test_bomb_pot_no_winner_when_no_pullers.gd`:
```gdscript
extends GutTest

const BombPotEvent = preload("res://scripts/events/bomb_pot/bomb_pot_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_context(player_count: int) -> RefCounted:
	var ctx = EventContext.new()
	for i in player_count:
		var p = MatchPlayer.new()
		p.peer_id = i + 1
		p.seat_index = i
		p.name = "P%d" % (i + 1)
		ctx.players.append(p)
		ctx.wagers[i + 1] = 100
	return ctx

func test_no_pullers_no_winner_crowned():
	# All 3 players bust (no one pulls out). The function should NOT
	# crown anyone via the winner_pull_out_ms sentinel comparison.
	var ctx = _make_context(3)
	var result = BombPotEvent.compute_event_result(
		ctx, 10.0,
		{},      # locked_shares — empty (no one pulled)
		[],      # pulled_out_peers — empty
		{}       # pull_out_timestamps — empty
	)
	# All players busted; none should have crown_delta > 0
	for pid in [1, 2, 3]:
		assert_eq(int(result.per_player[pid].get("crown_delta", 0)), 0,
			"P%d should not be crowned when no one pulled out" % pid)
	assert_eq(int(result.painful_reveal.get("winner_peer_id", -1)), 0,
		"winner_peer_id should be 0 when no pullers")
```

- [ ] **Step 2: Run, baseline pass**

This test is a defensive harness, not strict TDD red. The existing `-1` sentinel is safe because the `if pid in pulled_out_peers:` guard prevents any puller-side comparison from running — so the test passes on the unmodified code. Step 3 hardens the invariant without changing observable behavior.

Expected outcome on current code: **579/579 pass** (578 prior + 1 new pre-passing). If it fails, treat as a real bug and document it in the commit message.

- [ ] **Step 3: Harden with explicit `has_winner` flag**

In `scripts/events/bomb_pot/bomb_pot_event.gd`, find the `compute_event_result` function. Near the top, locate:

```gdscript
	var winner_peer_id = 0
	var winner_pull_out_ms = -1
	var winner_seat = INF
```

Replace with:

```gdscript
	var winner_peer_id = 0
	var winner_pull_out_ms: int = 0  # only meaningful when has_winner is true
	var winner_seat = INF
	var has_winner: bool = false
```

Then find the comparison inside the survivor branch (around line 211):

```gdscript
			# Track latest puller (with seat_index tie-break)
			var ts = int(pull_out_timestamps.get(pid, 0))
			if ts > winner_pull_out_ms or (ts == winner_pull_out_ms and player.seat_index < winner_seat):
				winner_pull_out_ms = ts
				winner_peer_id = pid
				winner_seat = player.seat_index
```

Replace with:

```gdscript
			# Track latest puller (with seat_index tie-break). has_winner
			# flag makes the "no pullers => no Crown" invariant explicit and
			# robust against future refactors that might decouple the
			# `pid in pulled_out_peers` guard from this block.
			var ts = int(pull_out_timestamps.get(pid, 0))
			if not has_winner or ts > winner_pull_out_ms or (ts == winner_pull_out_ms and player.seat_index < winner_seat):
				winner_pull_out_ms = ts
				winner_peer_id = pid
				winner_seat = player.seat_index
				has_winner = true
```

The Crown-award block below (around line 234) already gates on `if winner_peer_id != 0:` so no change needed there. The `winner_pull_out_ms` value still flows into `result.painful_reveal` unchanged.

- [ ] **Step 4: Run, verify pass**

Expected: **579/579 tests pass** (578 prior + 1 new). All existing Bomb Pot tests still pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/events/bomb_pot/bomb_pot_event.gd tests/unit/test_bomb_pot_no_winner_when_no_pullers.gd
git commit -F - <<'EOF'
refactor(client): Bomb Pot winner_pull_out_ms uses explicit has_winner flag

Closes the carry-forward "winner_pull_out_ms = -1 sentinel is fragile"
from sub-project #6 final review. The original invariant — no Crown
when no pullers — was load-bearing on an implicit puller-gating guard
plus a -1 sentinel that no puller could match via `ts > -1`.

Replaces with an explicit has_winner flag. The `if not has_winner or ...`
comparison makes the first-puller bootstrap explicit; subsequent
pullers slot into the tie-break math unchanged. Crown-award block
remains gated on winner_peer_id != 0.

Adds test_bomb_pot_no_winner_when_no_pullers verifying that an all-
bust round crowns nobody (baseline pass on both old and new code, but
the new shape makes the contract verifiable rather than incidental).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 8: Heat Shield int-div documentation

`heat_shield.gd` is currently a meta-only card — the int-div semantics actually live in the 3 events' Crown award blocks (e.g. Rocket Clash `var heat_delta = 1; if winner_mods.get("heat_shield", false): heat_delta = int(heat_delta / 2)`). The carry-forward note from sub-project #6 was flagged against `heat_shield.gd` as the "anchor" for the documentation, even though the math lives elsewhere. Add a doc-only comment to `heat_shield.gd` explaining the contract. No code change.

**Files:**
- Modify: `scripts/cards/effects/heat_shield.gd`

- [ ] **Step 1: Add the doc comment**

In `scripts/cards/effects/heat_shield.gd`, replace the existing file header comment:

```gdscript
# Heat Shield card: halves the heat_delta the player takes from this event.
# Set during BET_LOADOUT; resolved in compute_event_result by halving
# result.per_player[peer_id].heat_delta before it propagates.
extends Object
```

with the expanded doc comment:

```gdscript
# Heat Shield card: halves the heat_delta the player takes from this event.
# Set during BET_LOADOUT; resolved in compute_event_result by halving
# result.per_player[peer_id].heat_delta before it propagates.
#
# Sub-project #7 Plan A Task 8: integer-division contract.
# The halving math lives in each event's Crown-award block:
#   var heat_delta = 1
#   if winner_mods.get("heat_shield", false):
#       heat_delta = int(heat_delta / 2)   # 1 -> 0
#
# All 3 events award heat_delta = 1 to the Crown winner today, so
# int(1 / 2) = 0 is the intentional "fully shield the rare 1-point
# heat hit" semantic — Heat Shield is a binary cancel under this
# value table. If a future House Twist or rebalance promotes
# heat_delta to 2 for some event, this card silently becomes "halve
# 2 to 1" (int(2/2) = 1) which is a behavior change — flag for spec
# revisit at that time.
extends Object
```

- [ ] **Step 2: Run, verify no regressions**

Expected: **579/579 tests still pass** (no code change, doc-only).

- [ ] **Step 3: Commit**

```bash
git add scripts/cards/effects/heat_shield.gd
git commit -F - <<'EOF'
docs(cards): document Heat Shield int-div semantics

Closes the sub-project #6 carry-forward "Heat Shield int-div assumption
needs a future-proof note." The halving math actually lives in each
event's Crown-award block (int(heat_delta / 2)); heat_shield.gd is
meta-only. Add a header comment in heat_shield.gd anchoring the
contract: today all 3 events award heat_delta = 1 to Crown winners,
so int(1/2) = 0 is the intentional "binary cancel" semantic. If a
future twist promotes heat_delta to 2, the card silently becomes
"halve 2 to 1" — flag for spec revisit at that time.

Doc-only; no behavior change; 579 tests still passing.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 9: Bounty tie-split modulo to lowest seat_index

`BountyResolver.resolve` uses `var split = int(reward / claimants.size())` which evaporates the modulo when reward % claimant_count != 0 (e.g. reward=100 with 3 claimants yields 33+33+33 = 99 paid out, 1 chip lost). Refactor to assign the remainder to the claimant with the lowest seat_index for deterministic, replay-stable behavior.

**Files:**
- Modify: `scripts/match/bounty_resolver.gd`
- Create: `tests/unit/test_bounty_resolver_tie_split_modulo.gd`

- [ ] **Step 1: Write failing test**

`tests/unit/test_bounty_resolver_tie_split_modulo.gd`:
```gdscript
extends GutTest

const BountyResolver = preload("res://scripts/match/bounty_resolver.gd")
const Bounty = preload("res://scripts/match/bounty.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const EventResult = preload("res://scripts/events/event_result.gd")

func _new_state_with_3_players() -> RefCounted:
	var s = MatchState.new()
	for i in 3:
		var p = MatchPlayer.new()
		p.peer_id = i + 1
		p.seat_index = i
		p.name = "P%d" % (i + 1)
		p.chips = 1000
		s.players.append(p)
	return s

func test_3_way_tie_split_assigns_remainder_to_lowest_seat_index():
	# Three claimants tie; reward = 100. 100 / 3 = 33 each + 1 remainder.
	# The +1 must go to the claimant with the lowest seat_index (P1, seat 0).
	var s = _new_state_with_3_players()
	# Bust the target so all 3 claimants' bust-bounty conditions fire.
	var target = MatchPlayer.new()
	target.peer_id = 99
	target.seat_index = 99
	target.name = "Target"
	s.players.append(target)
	var b = Bounty.new()
	b.origin = "leader"
	b.target = 99
	b.condition = "bust"
	b.reward_chips = 100  # forces 100 / 3 = 33 + 1 remainder
	b.placed_at_event = 1
	s.bounties = [b]

	# Build an EventResult where P1, P2, P3 all qualify as claimants
	# by virtue of the target (peer 99) busting. The exact claim logic
	# is Bounty.satisfies(); for this test we rely on its existing
	# bust-target shape — the Bounty class accepts any claimant when
	# target busts. Verify the existing Bounty.satisfies API before
	# instantiating below if the contract differs in your codebase.
	var result = EventResult.new()
	result.event_id = "rocket_clash"
	result.per_player = {
		1: {"chip_delta": 0, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 5.0},
		2: {"chip_delta": 0, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 5.0},
		3: {"chip_delta": 0, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 5.0},
		99: {"chip_delta": -100, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0},
	}

	var awards = BountyResolver.resolve(s, result)

	# 3 awards expected, one per claimant
	assert_eq(awards.size(), 3, "exactly 3 awards (one per claimant)")
	var by_pid = {}
	for a in awards:
		by_pid[int(a.claimant_peer_id)] = int(a.reward_chips)
	assert_eq(by_pid.get(1, 0), 34, "P1 (lowest seat_index) gets 33 + 1 remainder = 34")
	assert_eq(by_pid.get(2, 0), 33, "P2 gets base share 33")
	assert_eq(by_pid.get(3, 0), 33, "P3 gets base share 33")
	# Total paid out = 100, no chips lost to int-div
	assert_eq(by_pid.get(1, 0) + by_pid.get(2, 0) + by_pid.get(3, 0), 100,
		"sum of awards equals full reward (no chips lost to modulo)")
```

**Notes for the implementer on the test:** verify `Bounty.satisfies` accepts the claimants used here before running. If `satisfies` requires non-bust + non-target claimants, the test fixture matches that. If it has narrower rules, adjust the fixture: e.g. add `cash_out_at` thresholds, or use the "heat" origin condition instead. The test's intent is "3 claimants, reward=100" — pick a fixture shape that produces exactly 3 claimants for the bounty in question.

- [ ] **Step 2: Run, watch fail**

Expected: 1 failure (P1 gets 33 instead of 34; total is 99, not 100).

- [ ] **Step 3: Implement the modulo fix**

In `scripts/match/bounty_resolver.gd`, find the existing tie-split block in `resolve`:

```gdscript
			else:
				var split = int(reward / claimants.size())
				for c_id in claimants:
					var c = _find_player(state, c_id)
					if c != null:
						c.chips += split
					awards.append({"claimant_peer_id": c_id, "bounty_dict": bounty.to_dict(), "reward_chips": split})
```

Replace with:

```gdscript
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
```

- [ ] **Step 4: Run, watch pass**

Expected: **580/580 tests pass** (579 prior + 1 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/match/bounty_resolver.gd tests/unit/test_bounty_resolver_tie_split_modulo.gd
git commit -F - <<'EOF'
fix(client): bounty tie-split assigns remainder to lowest seat_index

Closes the carry-forward "bounty tie-split int-div evaporates the
modulo" from sub-project #6. Previously `int(reward / claimants.size())`
paid floor(reward / N) to each claimant and lost the modulo (e.g.
reward=100 with 3 claimants -> 99 chips paid out, 1 lost).

Refactor: compute split = int(reward / claimants.size()) and
remainder = reward - split * claimants.size(); assign the remainder
to the claimant with the lowest seat_index. Deterministic for replay,
and the sum of awards now equals the full reward.

1 new test covers the 3-claimant tie with reward=100 (34/33/33 split).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 3: RPC bandwidth + arity (Tasks 10-12)

### Task 10: `MatchRpcSender` arity cap rewrite via `Callable.callv`

`MatchRpcSender.send` and `send_to_peer` use a `match args.size():` dispatcher that caps at 3 args (silently `push_error`s on 4+). Replace with `Callable.callv` so the sender handles arbitrary args, removing a latent bug class. This must land before Task 12 so that the 4-arg `_rpc_card_play_requested` test in Task 12 routes correctly through the sender.

**Files:**
- Modify: `scripts/match/match_rpc_sender.gd`
- Create: `tests/unit/test_match_rpc_sender_callv.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_match_rpc_sender_callv.gd`:
```gdscript
extends GutTest

const MatchRpcSender = preload("res://scripts/match/match_rpc_sender.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func test_send_4_args_passes_through_to_rpc():
	var fake = FakeMultiplayerNode.new()
	var sender = MatchRpcSender.new(fake)
	sender.send("_rpc_foo", ["a", "b", "c", "d"])
	assert_eq(fake.rpc_calls.size(), 1, "exactly 1 rpc call recorded")
	var call = fake.rpc_calls[0]
	assert_eq(String(call.method), "_rpc_foo")
	assert_eq(call.args, ["a", "b", "c", "d"],
		"4-arg send must pass all 4 args through (was silently push_error'd before)")

func test_send_to_peer_5_args_passes_through_to_rpc_id():
	var fake = FakeMultiplayerNode.new()
	var sender = MatchRpcSender.new(fake)
	sender.send_to_peer(2, "_rpc_bar", [1, 2, 3, 4, 5])
	assert_eq(fake.rpc_calls.size(), 1)
	var call = fake.rpc_calls[0]
	assert_eq(String(call.method), "_rpc_bar")
	assert_eq(int(call.peer_id), 2)
	assert_eq(call.args, [1, 2, 3, 4, 5],
		"5-arg send_to_peer must pass all 5 args through")
```

(Note: FakeMultiplayerNode's current `rpc(method, p1=null, ..., p4=null)` signature caps at 4 args. To support 5-arg tests, the fake needs a small extension — covered in Step 3 if needed.)

- [ ] **Step 2: Run, watch fail**

Expected: 2 failures — the 4-arg send fails the args-equality assertion because `_send_rpc`'s match statement falls through to the `push_error` branch and never records the call. The 5-arg fails identically.

- [ ] **Step 3: Extend FakeMultiplayerNode for arbitrary arity (if needed)**

Check `tests/fakes/fake_multiplayer_node.gd`: today its `rpc` signature is `func rpc(method: StringName, p1=null, p2=null, p3=null, p4=null) -> int:` — caps at 4 positional args. Extend it to capture arbitrary args. Replace the fake with:

```gdscript
# Records rpc(...) calls for sender-side tests. Each call is appended to
# rpc_calls as {method, args}. MatchController's _send_rpc helper invokes
# fake.rpc("method_name", arg1, arg2, ...) — we capture the method name
# and all positional arguments.
#
# Sub-project #7 Plan A Task 10: rpc / rpc_id accept up to 6 positional
# args (was 4) to support the callv-based MatchRpcSender that no longer
# caps at 3. If a future RPC needs more, extend the slots.
extends RefCounted

var rpc_calls: Array = []

func rpc(method: StringName, p1=null, p2=null, p3=null, p4=null, p5=null, p6=null) -> int:
	var args: Array = []
	if p1 != null: args.append(p1)
	if p2 != null: args.append(p2)
	if p3 != null: args.append(p3)
	if p4 != null: args.append(p4)
	if p5 != null: args.append(p5)
	if p6 != null: args.append(p6)
	rpc_calls.append({"method": String(method), "args": args})
	return OK

func rpc_id(peer_id: int, method: StringName, p1=null, p2=null, p3=null, p4=null, p5=null, p6=null) -> int:
	var args: Array = []
	if p1 != null: args.append(p1)
	if p2 != null: args.append(p2)
	if p3 != null: args.append(p3)
	if p4 != null: args.append(p4)
	if p5 != null: args.append(p5)
	if p6 != null: args.append(p6)
	rpc_calls.append({"method": String(method), "peer_id": peer_id, "args": args})
	return OK
```

**Notes for the implementer:** the `!= null` filter on each pX argument means that legitimate `null` args inside a call are dropped. This matches the existing fake's behavior — known quirk. Not in scope to fix.

- [ ] **Step 4: Implement the `Callable.callv` rewrite**

In `scripts/match/match_rpc_sender.gd`, replace the entire body with:

```gdscript
# Outbound RPC sender. Extracted from MatchController in Plan B Phase 7.
# Wraps the multiplayer_node so MatchController can construct one with
# either `self` (production: routes through the Node's rpc/rpc_id) or
# a FakeMultiplayerNode (tests: records calls in rpc_calls array).
#
# Receivers (@rpc-annotated methods) MUST stay on MatchController because
# Godot's MultiplayerAPI dispatches RPCs by NodePath. This class only
# handles the sender side.
#
# Sub-project #7 Plan A Task 10: arity-cap rewrite via Callable.callv.
# Previously a match args.size() dispatcher capped at 3 args and
# silently push_error'd on 4+. Now passes through any arity via callv.
extends RefCounted

var _multiplayer_node = null

func _init(multiplayer_node) -> void:
	_multiplayer_node = multiplayer_node

# Broadcast to all peers. Routes through _multiplayer_node.rpc with
# Callable.callv for arbitrary arity.
func send(method_name: String, args: Array = []) -> void:
	if _multiplayer_node == null:
		return
	var callable = Callable(_multiplayer_node, "rpc")
	var combined = [method_name]
	for a in args:
		combined.append(a)
	callable.callv(combined)

# Targeted send. Routes through _multiplayer_node.rpc_id with callv.
func send_to_peer(peer_id: int, method_name: String, args: Array = []) -> void:
	if _multiplayer_node == null:
		return
	var callable = Callable(_multiplayer_node, "rpc_id")
	var combined = [peer_id, method_name]
	for a in args:
		combined.append(a)
	callable.callv(combined)

# Convenience wrapper for the common "client submits to host" pattern.
# Delegates to send_to_peer with the host's peer_id; the @rpc receiver's
# `if not is_host: return` guard remains as defense in depth.
func send_to_host(host_peer_id: int, method_name: String, args: Array = []) -> void:
	send_to_peer(host_peer_id, method_name, args)
```

- [ ] **Step 5: Run, watch pass**

Expected: **582/582 tests pass** (580 prior + 2 new).

All existing MatchRpcSender tests (`test_match_rpc_sender.gd` if present) still pass — `Callable.callv` is a semantic-preserving substitution for the match-statement dispatch at arities 0-3, and adds support for 4+.

- [ ] **Step 6: Commit**

```bash
git add scripts/match/match_rpc_sender.gd tests/fakes/fake_multiplayer_node.gd tests/unit/test_match_rpc_sender_callv.gd
git commit -F - <<'EOF'
refactor(client): MatchRpcSender uses Callable.callv for arbitrary arity

Closes sub-project #6 carry-forward "MatchRpcSender arity cap at 3
args." Previously a match args.size() dispatcher handled 0-3 args
and silently push_error'd on 4+. Replace with Callable(node,
"rpc").bindv-style callv for arbitrary arity — no more silent
fall-through, no more arity ceiling.

send / send_to_peer / send_to_host all use the same pattern.
Behavior at arities 0-3 is preserved (callv with the same arg list
the match statement would have unpacked).

FakeMultiplayerNode's rpc / rpc_id signatures extended from 4 to 6
positional slots to support 5-arg test fixtures. The `!= null` filter
quirk (legitimate null args dropped) is preserved — known limitation.

2 new tests verify 4-arg and 5-arg pass-through.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 11: Starter pack broadcast narrowing — one rpc per peer

`_rpc_starter_pack_dealt(serialized_hands)` (`scripts/match/match_controller.gd` ~line 908) currently broadcasts a Dictionary containing every peer's full hand to every peer. With 5 peers and STARTER_PACK_SIZE=5 cards, that's ~25 card_ids serialized per peer × 5 peers = 125 serialized entries broadcast (each peer reads 25 but only uses 5). Refactor to one `rpc_id(peer_id, "_rpc_starter_pack_dealt", [peer_id, hand])` per peer with just that peer's hand.

There is exactly one call site: the initial deal in `_process_house_reveal` (~line 908). The Power Surge bonus deal uses a separate channel (`_rpc_house_twist_announced.params.cards_dealt`), not `_rpc_starter_pack_dealt`, so no second call site exists.

The receiver `_rpc_starter_pack_dealt(hands: Dictionary)` becomes `_rpc_starter_pack_dealt(peer_id: int, hand: Array)`.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_starter_pack_per_peer.gd`

- [ ] **Step 1: Write failing test**

`tests/unit/test_match_controller_starter_pack_per_peer.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start(player_count: int) -> RefCounted:
	var ms = MatchStart.new()
	for i in player_count:
		var s = PlayerSlot.new()
		s.peer_id = i + 1; s.seat_index = i; s.name = "P%d" % (i + 1)
		ms.seats.append(s)
	ms.host_peer_id = 1; ms.rng_seed = 1
	return ms

func test_starter_pack_dealt_fires_one_rpc_per_peer():
	# Start a match with 3 peers; the initial starter pack deal during
	# _process_house_reveal should fire 3 separate rpc_id calls (one
	# per peer with that peer's hand), not 1 broadcast with all hands.
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)  # host
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(3))
	# After start_match -> HOUSE_REVEAL phase ran -> starter pack dealt.
	var starter_pack_calls = []
	for call in fake.rpc_calls:
		if String(call.get("method", "")) == "_rpc_starter_pack_dealt":
			starter_pack_calls.append(call)
	assert_eq(starter_pack_calls.size(), 3,
		"expected 3 _rpc_starter_pack_dealt calls (1 per peer), got %d" % starter_pack_calls.size())
	# Each call should be targeted (has peer_id from rpc_id path)
	for call in starter_pack_calls:
		assert_true(call.has("peer_id"),
			"each starter_pack call must be rpc_id (targeted), not rpc broadcast")
	# Verify each peer_id appears exactly once
	var peer_ids_seen = []
	for call in starter_pack_calls:
		var pid = int(call.get("peer_id", 0))
		assert_false(pid in peer_ids_seen, "duplicate starter_pack to peer %d" % pid)
		peer_ids_seen.append(pid)
	assert_eq(peer_ids_seen.size(), 3, "all 3 peers received exactly one starter_pack call")
```

- [ ] **Step 2: Run, watch fail**

Expected: 1 failing test reporting `expected 3 calls, got 1` (the current code fires 1 broadcast).

- [ ] **Step 3: Refactor the initial deal in `_process_house_reveal`**

In `scripts/match/match_controller.gd`, find the existing block (around line 895-908):

```gdscript
	if not is_host:
		return
	var pool = CardRegistry.starter_pool()
	if pool.is_empty():
		return
	var serialized_hands: Dictionary = {}
	for p in state.players:
		var hand: Array = []
		for i in MatchConfig.STARTER_PACK_SIZE:
			var idx = state.rng.randi() % pool.size()
			hand.append(pool[idx])
		p.hand = hand
		serialized_hands[p.peer_id] = hand.duplicate()
	_send_rpc("_rpc_starter_pack_dealt", [serialized_hands])
```

Replace with per-peer narrowing:

```gdscript
	if not is_host:
		return
	var pool = CardRegistry.starter_pool()
	if pool.is_empty():
		return
	# Sub-project #7 Plan A Task 11: narrow from one broadcast-with-all-hands
	# to one rpc_id per peer with just that peer's hand. Apply hand
	# locally on host first, then send each peer their own hand.
	for p in state.players:
		var hand: Array = []
		for i in MatchConfig.STARTER_PACK_SIZE:
			var idx = state.rng.randi() % pool.size()
			hand.append(pool[idx])
		p.hand = hand
		_send_rpc_to_peer(p.peer_id, "_rpc_starter_pack_dealt", [p.peer_id, hand.duplicate()])
```

- [ ] **Step 4: Update the receiver signature**

Find the @rpc receiver:

```gdscript
@rpc("authority", "call_remote", "reliable")
func _rpc_starter_pack_dealt(hands: Dictionary) -> void:
	for pid_key in hands.keys():
		var pid = int(pid_key)
		var p = state.find_player(pid)
		if p != null:
			p.hand = hands[pid_key].duplicate()
```

Replace with:

```gdscript
@rpc("authority", "call_remote", "reliable")
func _rpc_starter_pack_dealt(peer_id: int, hand: Array) -> void:
	# Sub-project #7 Plan A Task 11: per-peer narrowing — receiver now
	# only knows its own hand. Other peers' hands stay private (defensive
	# vs future leak; today all client peers still see public events).
	var p = state.find_player(peer_id)
	if p != null:
		p.hand = hand.duplicate()
```

- [ ] **Step 5: Confirm no second call site**

Use the Grep tool: pattern `_rpc_starter_pack_dealt`, path `scripts/match/match_controller.gd`, output_mode content -n true. Verify there is exactly one call site (the initial deal in `_process_house_reveal`). The Power Surge bonus deal uses `_rpc_house_twist_announced.params.cards_dealt`, not this RPC, so no second narrowing is needed. If grep surfaces a second call site, narrow it with the same per-peer loop pattern and note in the commit message.

- [ ] **Step 6: Run, watch pass**

Expected: **583/583 tests pass** (582 prior + 1 new).

If any existing test depends on the OLD broadcast signature (`hands: Dictionary`), it will fail with a type mismatch. Most likely failure: an integration or unit test that calls `c._rpc_starter_pack_dealt({1: ["card_a"], 2: ["card_b"]})` directly. Update those tests to the new signature (`c._rpc_starter_pack_dealt(1, ["card_a"])` etc.) — the migration is mechanical.

- [ ] **Step 7: Commit**

```bash
git add scripts/match/match_controller.gd tests/unit/test_match_controller_starter_pack_per_peer.gd
git commit -F - <<'EOF'
perf(client): starter pack RPC narrows to one per-peer rpc_id

Closes sub-project #6 carry-forward "_rpc_starter_pack_dealt broadcasts
every peer's hand to every peer." Previously the host serialized a
Dictionary keyed by peer_id containing every peer's full hand and
broadcast it to all peers — 5x bandwidth waste at the steady-state 5-
peer match.

Refactor: one rpc_id(peer_id, "_rpc_starter_pack_dealt", [peer_id, hand])
per peer with just that peer's hand. Receiver signature changes from
(hands: Dictionary) to (peer_id: int, hand: Array). One call site
updated (initial deal in _process_house_reveal; Power Surge uses a
separate channel and is not affected).

Side benefit: peer hands stay private on the wire (defensive; today
all clients still see the broadcast events that surface per-player
chip + crown deltas, so this isn't a real privacy boundary — but it
moves in the right direction).

1 new test verifies 3-peer match fires exactly 3 targeted rpc_id calls.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 12: Client→host RPC call sites use `rpc_id(host_peer_id, ...)`

`MatchController`'s `submit_*` methods currently call `_send_rpc("_rpc_set_wager", ...)` etc., which routes through `_rpc_sender.send` → `_multiplayer_node.rpc(...)` and broadcasts to ALL peers. The host's `is_host: return` guard at the top of each receiver short-circuits non-host peers, so behavior is correct — but bandwidth is wasted on the N-1 non-host peers per call. Convert each client→host call site to `rpc_id(state.host_peer_id, ...)` so only the host receives.

**Implementation approach:** add a `_send_rpc_to_host(method_name, args)` helper on `MatchController` that reads `state.host_peer_id` from local state and delegates to the already-present `MatchRpcSender.send_to_host` (added in Task 10). Then convert the 4 submit_* call sites. Task 10's `callv` rewrite means `_rpc_card_play_requested`'s 4-arg call routes correctly through the sender.

**FakeMultiplayerNode note:** the fake already discriminates `rpc` vs `rpc_id` calls (the `rpc_id` path records `{method, peer_id, args}` while the `rpc` path records `{method, args}` — no `peer_id` key). Tests can assert on `peer_id` presence to verify the targeted path was used.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_rpc_bandwidth.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_match_controller_rpc_bandwidth.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start(player_count: int) -> RefCounted:
	var ms = MatchStart.new()
	for i in player_count:
		var s = PlayerSlot.new()
		s.peer_id = i + 1; s.seat_index = i; s.name = "P%d" % (i + 1)
		ms.seats.append(s)
	ms.host_peer_id = 1; ms.rng_seed = 1
	return ms

func _new_client_controller() -> RefCounted:
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(false, fake)  # client, not host
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(3))
	# state.host_peer_id is 1 from the match_start fixture
	# Clear any setup RPC calls the controller fired during start_match
	fake.rpc_calls.clear()
	return c

func _find_call(fake, method_name: String) -> Dictionary:
	for call in fake.rpc_calls:
		if String(call.get("method", "")) == method_name:
			return call
	return {}

func test_submit_wager_targets_host_via_rpc_id():
	var c = _new_client_controller()
	c.submit_wager(50)
	var call = _find_call(c._rpc_sender._multiplayer_node, "_rpc_set_wager")
	assert_true(call.has("peer_id"),
		"_rpc_set_wager must use rpc_id (peer_id key present in fake record)")
	assert_eq(int(call.get("peer_id", -1)), 1,
		"target peer_id must be host_peer_id (1)")

func test_submit_card_play_targets_host_via_rpc_id():
	var c = _new_client_controller()
	c.submit_card_play("heat_shield", 0, null)
	var call = _find_call(c._rpc_sender._multiplayer_node, "_rpc_card_play_requested")
	assert_true(call.has("peer_id"),
		"_rpc_card_play_requested must use rpc_id")
	assert_eq(int(call.get("peer_id", -1)), 1, "targets host")

func test_submit_event_pick_targets_host_via_rpc_id():
	var c = _new_client_controller()
	c.submit_event_pick("res://scenes/events/rocket_clash/rocket_clash_event.tscn")
	var call = _find_call(c._rpc_sender._multiplayer_node, "_rpc_event_picker_choice")
	assert_true(call.has("peer_id"),
		"_rpc_event_picker_choice must use rpc_id")
	assert_eq(int(call.get("peer_id", -1)), 1, "targets host")
```

- [ ] **Step 2: Run, watch fail**

Expected: 3 failures (the current `_send_rpc` path records `rpc` calls without `peer_id`).

- [ ] **Step 3: Add `_send_rpc_to_host` to MatchController**

In `scripts/match/match_controller.gd`, after the existing `_send_rpc_to_peer` helper, add:

```gdscript
func _send_rpc_to_host(method_name: String, args: Array = []) -> void:
	_rpc_sender.send_to_host(state.host_peer_id, method_name, args)
```

- [ ] **Step 4: Convert the 4 client→host submit_* call sites**

Find and update each of these 4 call sites in `scripts/match/match_controller.gd`:

1. `submit_loadout_change` (line ~191):
   ```gdscript
   _send_rpc("_rpc_loadout_set", [my_peer_id, loadout])
   ```
   becomes
   ```gdscript
   _send_rpc_to_host("_rpc_loadout_set", [my_peer_id, loadout])
   ```

2. `submit_card_play` (line ~195):
   ```gdscript
   _send_rpc("_rpc_card_play_requested", [my_peer_id, card_id, target_peer_id, params])
   ```
   becomes
   ```gdscript
   _send_rpc_to_host("_rpc_card_play_requested", [my_peer_id, card_id, target_peer_id, params])
   ```

3. `submit_wager` (line ~199):
   ```gdscript
   _send_rpc("_rpc_set_wager", [my_peer_id, amount])
   ```
   becomes
   ```gdscript
   _send_rpc_to_host("_rpc_set_wager", [my_peer_id, amount])
   ```

4. `submit_event_pick` (line ~205):
   ```gdscript
   _send_rpc("_rpc_event_picker_choice", [my_peer_id, chosen_path])
   ```
   becomes
   ```gdscript
   _send_rpc_to_host("_rpc_event_picker_choice", [my_peer_id, chosen_path])
   ```

**Verification:** after the edits, use the Grep tool: pattern `_send_rpc`, path `scripts/match/match_controller.gd`, output_mode content -n true. Expected: any remaining `_send_rpc` calls are host→client broadcasts (e.g. `_rpc_starter_pack_dealt`, `_rpc_match_ended`, `_rpc_bounties_placed`, etc.) — those stay as broadcasts.

- [ ] **Step 5: Run, watch pass**

Expected: **586/586 tests pass** (583 prior + 3 new). All existing MatchController tests still pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/match/match_controller.gd tests/unit/test_match_controller_rpc_bandwidth.gd
git commit -F - <<'EOF'
perf(client): client->host RPCs use rpc_id to skip broadcast

Closes sub-project #6 carry-forward "client->host RPC bandwidth waste."
The 4 client-initiated submit_* methods (submit_loadout_change,
submit_card_play, submit_wager, submit_event_pick) currently broadcast
to all peers via .rpc(); the host's `if not is_host: return` guard at
each receiver short-circuits non-host peers, so behavior is correct
but bandwidth is wasted on N-1 peers per call.

Switch to rpc_id(state.host_peer_id, ...) so only the host receives.
Added _send_rpc_to_host(method, args) helper on MatchController; uses
the already-present MatchRpcSender.send_to_host (added in Task 10).
The @rpc receiver's is_host guards stay as defense in depth.

3 new tests verify the targeted path via FakeMultiplayerNode's
rpc_id-vs-rpc discrimination (the fake records peer_id only on rpc_id
calls). Existing receiver tests cover the host-side behavior unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Done

Plan A complete. Sub-project #7 Plan A delivers:
- 2 new collaborator helpers (`EventHelpers`, `PlayerSelectors`) closing the longest-standing carry-forward
- 6 inlined twist-consumer blocks (3 Leader Cursed + 3 Sudden Death) replaced with 1-call-per-player helper invocations
- 3 numeric edge cases closed (Bomb Pot sentinel, Heat Shield doc, bounty tie-split modulo)
- RPC bandwidth optimization (client→host targeted; starter pack per-peer); MatchRpcSender arity cap removed via `Callable.callv`
- +22 unit tests

**Cumulative state after Plan A merge:**
- Test suite: ~586 unit + 7 integration
- All 6 House Twists wired, 12 cards, 6 events still rotating
- Codebase ready for Plan B UX polish

**Tags after Plan A merges:** `subproject-7-plan-a-complete`. After Plan B merges: `subproject-7-plan-b-complete` + `subproject-7-complete` + `mvp-complete`.

**Memory updates after Plan A merges:**
- `MEMORY.md` / `project_riskroyal.md` — mark Plan A done, Plan B next
- `project_riskroyal_followups.md` — close debt items (DRY, find_chip_leader, guard cleanup, sentinel, tie-split, RPC bandwidth, arity); UX polish items still tracked for Plan B
