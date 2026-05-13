# House Twists Plan B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the remaining 2 of 6 MVP House Twists (Lowest Chips Picks async picker + Sudden Death Jackpot lazy-condition crown bonus) to complete sub-project #6.

**Architecture:** Lowest Chips Picks defers `_process_event_selection` to an async picker flow (3 new RPCs + 10s timeout watchdog + host fallback + new EventPickerOverlay UI). Sudden Death Jackpot uses lazy condition resolution: `compute_twist_params` returns `{condition: ""}` at HOUSE_TWIST; after EVENT_SELECTION picks the event, `HouseTwistController.finalize_pending_params(state)` maps event_id → condition (`cash_out_over_5x` / `pull_out_after_80_pct` / `locked_at_perfect`) and broadcasts the updated twist params. Per-event `compute_event_result` adds `crown_delta += 1` for survivors meeting the condition.

**Tech Stack:** Godot 4.6 + GDScript; GUT testing; host-authoritative @rpc.

---

## File Structure

**New files (Plan B):**
- `scripts/ui/event_picker_overlay.gd` + `scenes/ui/event_picker_overlay.tscn` — picker UI (3 buttons + countdown + waiting banner)
- `tests/unit/test_house_twist_controller_lowest_chips_picks_params.gd`
- `tests/unit/test_house_twist_controller_finalize_pending_params.gd`
- `tests/unit/test_match_controller_event_picker_flow.gd`
- `tests/unit/test_match_controller_event_picker_rpc.gd`
- `tests/unit/test_match_controller_sudden_death_finalize.gd`
- `tests/unit/test_rocket_clash_sudden_death.gd`
- `tests/unit/test_bomb_pot_sudden_death.gd`
- `tests/unit/test_card_cannon_sudden_death.gd`
- `tests/unit/test_event_picker_overlay.gd`
- `tests/integration/test_lowest_chips_picker.gd` — PENDING stub

**Modified files (Plan B):**
- `scripts/match/house_twist_controller.gd` — drop `PLAN_A_TWISTS` (or fold into TWIST_POOL); populate real `lowest_chips_picks` params; add `finalize_pending_params(state)`
- `scripts/match/match_controller.gd` — `_process_event_selection` branches on `lowest_chips_picks`; new RPC trio (`_rpc_event_picker_started`, `_rpc_event_picker_choice`, `_rpc_event_picker_resolved`); new `_rpc_house_twist_params_updated` for late-bind broadcast; `finalize_pending_params` call after event selected; `submit_event_pick(chosen_path)` public entry
- `scripts/events/rocket_clash/rocket_clash_event.gd` — `compute_event_result` reads `ctx.house_twist.params.condition` for `cash_out_over_5x`
- `scripts/events/bomb_pot/bomb_pot_event.gd` — same for `pull_out_after_80_pct` (uses `bomb_at_sec` from compute args; condition met when pull-out timestamp > 80% of bomb-time)
- `scripts/events/card_cannon/card_cannon_event.gd` — same for `locked_at_perfect` (locked == 21)
- `scripts/ui/match_scene.gd` + `scenes/match_scene.tscn` — add `EventPickerSlot` Container + builder
- `tests/unit/test_house_twist_controller.gd` — widen the existing `test_select_next_twist_picks_from_plan_a_pool_when_no_history` to assert against `TWIST_POOL`
- `docs/PLAYTEST_CHECKLIST.md` — append scenarios 22-27 covering picker + sudden death

**Baseline (post Plan A merge):** 541 unit + 6 integration. **Target after Task 12 (end of Plan B):** ~564 unit + 7 integration (+23 new unit + 1 new integration). The per-task rolling counts below treat 541 as the starting point.

---

## Notes for the implementer

- **Test seam naming.** Plan A established a pattern: `<phase>_timeout_sec_override: float = -1.0`, `_<phase>_timeout_sec()` helper, and 0.0 = bypass timer entirely / negative = use MatchConfig default. Plan B's picker timer reuses that pattern: `event_picker_timeout_sec_override: float = -1.0` + `_event_picker_timeout_sec()` helper. Default in MatchConfig is `EVENT_PICKER_TIMEOUT_SEC: int = 10`.
- **RPC sender arity cap.** `MatchRpcSender.send` and `send_to_peer` cap at 3 args today (see `scripts/match/match_rpc_sender.gd`). All Plan B RPCs are 1-2 args, so no bump needed — but if you redesign and need 4 args, flag it before continuing.
- **Carry-forward folded in.** This plan optionally folds in one Plan A carry-forward: Task 1 also adds the 3-line defensive reset of `state.house_twist`, `last_twist_type`, `previous_event_id` to `MatchController.start_match` (resolves the "start_match doesn't reset twist tracking" item from `project_riskroyal_followups.md`). Scoped intentionally; reviewers will see it called out in the Task 1 description.
- **DRY extraction NOT folded in.** Plan A's review identified that the 3 events' `compute_event_result` Leader Cursed blocks are 7-line copies (5 sites total now, 7 if Plan B copies the same shape for Sudden Death). The fix is `EventHelpers.apply_leader_cursed_multiplier` / `apply_sudden_death_bonus`. **Sub-project #7 will do this consolidation** because: (a) folding it in adds 1 task + 1 test file for 0 functional behavior change, slowing Plan B; (b) the carry-forward note already commits #7 to the cleanup. Plan B per-event consumers (Tasks 7-9) copy the pattern verbatim and add `# Sub-project #7: extract to EventHelpers.apply_sudden_death_bonus` comments above each block.
- **Per-event Sudden Death conditions.** The spec § 7.6 maps:
  - Rocket Clash → `cash_out_over_5x` → `cash_outs[pid] > 5.0` (the cash-out multiplier captured in `cash_outs` arg).
  - Bomb Pot → `pull_out_after_80_pct` → puller AND `pull_out_timestamps[pid] >= bomb_at_sec * 1000 * 0.80` (timestamps are in milliseconds; `bomb_at_sec` is the compute_event_result argument).
  - Card Cannon → `locked_at_perfect` → `locked == 21`.

---

## Phase 1: HouseTwistController updates (Tasks 1-3)

### Task 1: Widen selection pool from `PLAN_A_TWISTS` to full `TWIST_POOL` + reset twist tracking in start_match

Plan A gated `select_next_twist` to the 4 fully-wired twists via the `PLAN_A_TWISTS` constant. With Plan B wiring the remaining 2 twists fully end-to-end, the gate retires. The existing `test_select_next_twist_picks_from_plan_a_pool_when_no_history` test updates to assert against `TWIST_POOL` (and renames). Also folds in the Plan A review carry-forward to reset twist/event-pool tracking fields in `start_match` — defensive insurance even though production never reuses a controller instance.

**Files:**
- Modify: `scripts/match/house_twist_controller.gd`
- Modify: `tests/unit/test_house_twist_controller.gd`
- Modify: `scripts/match/match_controller.gd` (start_match reset)
- Create: `tests/unit/test_match_controller_start_match_resets_twist_fields.gd`

- [ ] **Step 1: Update the existing test**

In `tests/unit/test_house_twist_controller.gd`, rename + retarget the existing test:

```gdscript
func test_select_next_twist_picks_from_full_pool_when_no_history():
	var s = _new_state_with_players([500, 700, 600])  # unequal chips → all twists eligible
	var twist = HouseTwistController.select_next_twist(s)
	assert_true(twist.get("type", "") in HouseTwistController.TWIST_POOL,
		"selected twist must be in TWIST_POOL (Plan B widens selection)")
```

That is the entire change to the existing test: rename it (drop `_plan_a_pool_` for `_full_pool_`) and swap `PLAN_A_TWISTS` for `TWIST_POOL` in the assertion.

- [ ] **Step 2: Write the new tests for the start_match reset**

`tests/unit/test_match_controller_start_match_resets_twist_fields.gd`:
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

func test_start_match_resets_house_twist_fields():
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	# Pre-poison the controller's state as if a prior match left these set
	c.state.house_twist = {"type": "double_bounty", "params": {}}
	c.state.last_twist_type = "double_bounty"
	c.state.previous_event_id = "res://scenes/events/rocket_clash/rocket_clash_event.tscn"
	c.start_match(_build_match_start(2))
	assert_eq(c.state.house_twist, {}, "house_twist reset to empty")
	assert_eq(c.state.last_twist_type, "", "last_twist_type reset to empty string")
	assert_eq(c.state.previous_event_id, "", "previous_event_id reset to empty string")
```

- [ ] **Step 3: Run, watch fail**

```
godot --headless --path c:/Users/whann/Desktop/Games/RocketMan -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
```

Expected: 2 failures (the renamed test asserts `TWIST_POOL` but selection still uses `PLAN_A_TWISTS`; the start_match reset test fails because the field-reset is missing).

- [ ] **Step 4: Implement HouseTwistController widening**

In `scripts/match/house_twist_controller.gd`:

1. DELETE the `PLAN_A_TWISTS` constant block (lines 23-31):
   ```gdscript
   const PLAN_A_TWISTS: Array = [
   	"double_bounty",
   	"no_insurance",
   	"leader_cursed",
   	"power_surge",
   ]
   ```

2. In `select_next_twist`, replace `PLAN_A_TWISTS` with `TWIST_POOL` (2 occurrences — the initial duplicate and the fallback):

```gdscript
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
```

- [ ] **Step 5: Implement start_match reset**

In `scripts/match/match_controller.gd`, find `start_match`. Locate where `state.event_index = 0` is set (after `state.seed_rng()`). Add 3 lines immediately after:

```gdscript
	state.event_index = 0
	# Sub-project #6 Plan B Task 1: defensive reset of twist + event-pool
	# tracking. Production never reuses a controller instance, but this
	# closes the Plan A carry-forward documented in
	# project_riskroyal_followups.md.
	state.house_twist = {}
	state.last_twist_type = ""
	state.previous_event_id = ""
```

- [ ] **Step 6: Run, watch pass**

Expected: **544/544 tests pass** (541 prior + 1 renamed/updated existing + 1 new for start_match reset + 1 net change from `select_next_twist` test now searching a wider pool == still 1 test). Math: 541 + 1 = **542 unit tests** after this task. (The renamed existing test does not add to the count; the new test_match_controller_start_match... adds +1.)

Correction: Plan A's `541` baseline is the unit count cited by the controller's scope spec. The renamed test does not change count. The new file `test_match_controller_start_match_resets_twist_fields.gd` adds exactly 1 test. **Expected: 542/542 unit tests pass.**

- [ ] **Step 7: Commit**

```bash
git add scripts/match/house_twist_controller.gd scripts/match/match_controller.gd tests/unit/test_house_twist_controller.gd tests/unit/test_match_controller_start_match_resets_twist_fields.gd
git commit -F - <<'EOF'
feat(client): widen HouseTwist selection to all 6 twists + reset start_match

Plan A's PLAN_A_TWISTS gate (4 of 6 twists) retires now that Plan B
wires the remaining 2 fully end-to-end. select_next_twist picks
uniformly from the full TWIST_POOL.

Also folds in a Plan A review carry-forward: start_match now resets
state.house_twist, last_twist_type, and previous_event_id. Production
never reuses a controller instance (MatchScene._ready always builds
fresh), so moot today — but cheap defensive insurance against future
test setups or refactors that reuse controllers.

1 new test for the reset + 1 renamed/retargeted existing test.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 2: `compute_twist_params` for `lowest_chips_picks` returns real params

The Plan A stub returns `{timeout_sec: 10}`. Plan B populates the full picker contract: `{picker_peer_id, options, timeout_sec}`. `picker_peer_id` is the lowest-chips player (seat_index tie-break, mirroring the existing `_find_chip_leader_peer_id` shape but minimizing). `options` is `MatchConfig.EVENT_POOL.duplicate()` shuffled via `state.rng` (uses Fisher-Yates so the shuffle is deterministic for the seed).

**Files:**
- Modify: `scripts/match/house_twist_controller.gd`
- Create: `tests/unit/test_house_twist_controller_lowest_chips_picks_params.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_house_twist_controller_lowest_chips_picks_params.gd`:
```gdscript
extends GutTest

const HouseTwistController = preload("res://scripts/match/house_twist_controller.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _new_state_with_chips(chips_array: Array, seat_indices: Array = []) -> RefCounted:
	var s = MatchState.new()
	for i in chips_array.size():
		var p = MatchPlayer.new()
		p.peer_id = i + 1
		p.seat_index = seat_indices[i] if i < seat_indices.size() else i
		p.chips = chips_array[i]
		s.players.append(p)
	s.rng_seed = 1
	s.seed_rng()
	return s

func test_compute_lowest_chips_picks_params_identifies_lowest_chips_player():
	var s = _new_state_with_chips([700, 300, 500])  # P2 is lowest
	var params = HouseTwistController.compute_twist_params("lowest_chips_picks", s)
	assert_eq(int(params.get("picker_peer_id", 0)), 2,
		"picker_peer_id must be the lowest-chips player")
	assert_eq(int(params.get("timeout_sec", 0)), 10,
		"timeout_sec defaults to 10 per spec § 7.5")

func test_compute_lowest_chips_picks_params_tie_breaks_by_seat_index():
	# P1 and P3 both have 300 chips; P1 has seat_index 0, P3 has seat_index 2.
	# Tie-break is LOWEST seat_index, so P1 wins.
	var s = _new_state_with_chips([300, 700, 300], [0, 1, 2])
	var params = HouseTwistController.compute_twist_params("lowest_chips_picks", s)
	assert_eq(int(params.get("picker_peer_id", 0)), 1,
		"tie-break must pick lowest seat_index (P1 over P3)")

func test_compute_lowest_chips_picks_options_is_shuffled_event_pool():
	var s = _new_state_with_chips([700, 300, 500])
	var params = HouseTwistController.compute_twist_params("lowest_chips_picks", s)
	var options: Array = params.get("options", [])
	assert_eq(options.size(), MatchConfig.EVENT_POOL.size(),
		"options size matches EVENT_POOL size")
	for entry in options:
		assert_true(MatchConfig.EVENT_POOL.has(entry),
			"each option is an EVENT_POOL member: %s" % entry)
```

- [ ] **Step 2: Run, watch fail**

Expected: 3 failures (params lacks picker_peer_id + options keys).

- [ ] **Step 3: Implement**

In `scripts/match/house_twist_controller.gd`:

1. Add the `MatchConfig` preload near other preloads at the top of the file:
```gdscript
const MatchConfig = preload("res://scripts/match/match_config.gd")
```

2. Replace the `"lowest_chips_picks"` branch in `compute_twist_params`:
```gdscript
		"lowest_chips_picks":
			return {
				"picker_peer_id": _find_lowest_chips_peer_id(state),
				"options": _shuffled_event_pool(state),
				"timeout_sec": 10,
			}
```

3. Add helper functions at the bottom of the file (next to `_find_chip_leader_peer_id`):
```gdscript
# Lowest-chips player with deterministic tie-break by lower seat_index.
# Mirror-shape with _find_chip_leader_peer_id but minimizing instead of
# maximizing. Sub-project #7 may consolidate the two into a single helper
# with a tie-break/direction flag.
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

# Fisher-Yates shuffle of MatchConfig.EVENT_POOL using state.rng for
# determinism. Returns a new Array — does not mutate the const.
static func _shuffled_event_pool(state) -> Array:
	var arr = MatchConfig.EVENT_POOL.duplicate()
	for i in range(arr.size() - 1, 0, -1):
		var j = state.rng.randi() % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr
```

- [ ] **Step 4: Run, watch pass**

Expected: **545/545 tests pass** (542 prior + 3 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/match/house_twist_controller.gd tests/unit/test_house_twist_controller_lowest_chips_picks_params.gd
git commit -F - <<'EOF'
feat(client): compute_twist_params populates real lowest_chips_picks params

Plan A's lowest_chips_picks stub returned {timeout_sec: 10}. Plan B
fills the full contract spec § 7.5: picker_peer_id (lowest-chips
player with seat_index tie-break), options (Fisher-Yates shuffled
MatchConfig.EVENT_POOL, deterministic per state.rng), and timeout_sec.

Two helpers added: _find_lowest_chips_peer_id (mirrors the existing
_find_chip_leader_peer_id shape but minimizing) and
_shuffled_event_pool (deterministic Fisher-Yates).

3 new unit tests cover the lowest-chips lookup, the seat_index
tie-break, and the options-size + membership invariant.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 3: `HouseTwistController.finalize_pending_params(state)` for Sudden Death

After `_process_event_selection` sets `state.current_event_id`, the host calls `HouseTwistController.finalize_pending_params(state)`. This is a no-op for all twist types EXCEPT `sudden_death_jackpot` (per spec § 7.6 lazy-condition pattern). For Sudden Death it maps `state.current_event_id` → condition string and rewrites `state.house_twist.params.condition` in-place.

**Files:**
- Modify: `scripts/match/house_twist_controller.gd`
- Create: `tests/unit/test_house_twist_controller_finalize_pending_params.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_house_twist_controller_finalize_pending_params.gd`:
```gdscript
extends GutTest

const HouseTwistController = preload("res://scripts/match/house_twist_controller.gd")
const MatchState = preload("res://scripts/match/match_state.gd")

func test_finalize_pending_params_maps_rocket_clash_to_cash_out_over_5x():
	var s = MatchState.new()
	s.house_twist = {"type": "sudden_death_jackpot", "params": {"condition": ""}}
	s.current_event_id = "res://scenes/events/rocket_clash/rocket_clash_event.tscn"
	HouseTwistController.finalize_pending_params(s)
	assert_eq(String(s.house_twist.params.get("condition", "")), "cash_out_over_5x")

func test_finalize_pending_params_maps_bomb_pot_to_pull_out_after_80_pct():
	var s = MatchState.new()
	s.house_twist = {"type": "sudden_death_jackpot", "params": {"condition": ""}}
	s.current_event_id = "res://scenes/events/bomb_pot/bomb_pot_event.tscn"
	HouseTwistController.finalize_pending_params(s)
	assert_eq(String(s.house_twist.params.get("condition", "")), "pull_out_after_80_pct")

func test_finalize_pending_params_maps_card_cannon_to_locked_at_perfect():
	var s = MatchState.new()
	s.house_twist = {"type": "sudden_death_jackpot", "params": {"condition": ""}}
	s.current_event_id = "res://scenes/events/card_cannon/card_cannon_event.tscn"
	HouseTwistController.finalize_pending_params(s)
	assert_eq(String(s.house_twist.params.get("condition", "")), "locked_at_perfect")

func test_finalize_pending_params_no_op_for_non_sudden_death():
	var s = MatchState.new()
	s.house_twist = {"type": "double_bounty", "params": {"reward_multiplier": 2.0}}
	s.current_event_id = "res://scenes/events/rocket_clash/rocket_clash_event.tscn"
	HouseTwistController.finalize_pending_params(s)
	# No mutation: reward_multiplier still 2.0, no condition key added
	assert_almost_eq(float(s.house_twist.params.get("reward_multiplier", 0.0)), 2.0, 0.001)
	assert_false(s.house_twist.params.has("condition"),
		"non-Sudden-Death twists are untouched")

func test_finalize_pending_params_no_op_when_no_twist_active():
	var s = MatchState.new()
	s.house_twist = {}
	s.current_event_id = "res://scenes/events/rocket_clash/rocket_clash_event.tscn"
	HouseTwistController.finalize_pending_params(s)
	assert_eq(s.house_twist, {}, "empty twist stays empty")
```

- [ ] **Step 2: Run, watch fail**

Expected: 3 failures (finalize_pending_params doesn't exist).

- [ ] **Step 3: Implement**

In `scripts/match/house_twist_controller.gd`, add the new static after `apply_pre_event_effects`:

```gdscript
# Lazy condition resolution for Sudden Death Jackpot. Called by
# MatchController._process_event_selection AFTER state.current_event_id
# is set. Maps event scene path → condition string per spec § 7.6 and
# rewrites state.house_twist.params.condition in-place. No-op for all
# other twist types (defensive).
static func finalize_pending_params(state) -> void:
	if state.house_twist.get("type", "") != "sudden_death_jackpot":
		return
	var event_id = String(state.current_event_id)
	var condition = ""
	if event_id.ends_with("rocket_clash_event.tscn"):
		condition = "cash_out_over_5x"
	elif event_id.ends_with("bomb_pot_event.tscn"):
		condition = "pull_out_after_80_pct"
	elif event_id.ends_with("card_cannon_event.tscn"):
		condition = "locked_at_perfect"
	else:
		push_warning("HouseTwistController.finalize_pending_params: unknown event_id %s" % event_id)
		return
	# Mutate the params dict in-place; caller (MatchController) broadcasts
	# the updated dict via _rpc_house_twist_params_updated.
	if not state.house_twist.has("params"):
		state.house_twist["params"] = {}
	state.house_twist["params"]["condition"] = condition
```

- [ ] **Step 4: Run, watch pass**

Expected: **550/550 tests pass** (545 prior + 5 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/match/house_twist_controller.gd tests/unit/test_house_twist_controller_finalize_pending_params.gd
git commit -F - <<'EOF'
feat(client): HouseTwistController.finalize_pending_params for Sudden Death

Implements the lazy-condition pattern from spec § 7.6: at HOUSE_TWIST
phase, compute_twist_params for sudden_death_jackpot returns
{condition: ""} because we don't yet know which event will follow.
After EVENT_SELECTION picks state.current_event_id, MatchController
calls finalize_pending_params(state) to map event_id → condition:
- rocket_clash_event.tscn  → cash_out_over_5x
- bomb_pot_event.tscn      → pull_out_after_80_pct
- card_cannon_event.tscn   → locked_at_perfect

No-op for non-Sudden-Death twists (defensive). 5 new unit tests cover
all 3 event mappings + non-twist + empty-twist no-ops.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 2: Lowest Chips Picks integration (Tasks 4-5)

### Task 4: `_process_event_selection` defers to picker flow when twist active + host timeout fallback

When `state.house_twist.type == "lowest_chips_picks"`, the existing no-repeat selection is bypassed. Instead host broadcasts `_rpc_event_picker_started(picker_peer_id, options)`, starts a 10-second timer, awaits a picker submission (sets `state.current_event_id` synchronously) or timeout (host picks uniformly at random from `options`). The non-twist path (Plan A's no-repeat selection) is left untouched.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Modify: `scripts/match/match_config.gd` (add `EVENT_PICKER_TIMEOUT_SEC` constant)
- Create: `tests/unit/test_match_controller_event_picker_flow.gd`

- [ ] **Step 1: Add MatchConfig constant**

In `scripts/match/match_config.gd`, after `EVENT_TIMEOUT_SEC` (line 28) add:
```gdscript
const EVENT_PICKER_TIMEOUT_SEC: int = 10
```

- [ ] **Step 2: Write failing tests**

`tests/unit/test_match_controller_event_picker_flow.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")
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

func _new_controller() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.event_picker_timeout_sec_override = 0.0  # bypass timer entirely in this test
	c.start_match(_build_match_start(2))
	return {"controller": c, "fake": fake}

func test_event_selection_no_twist_uses_existing_no_repeat_path():
	# Plan A path untouched: no twist → uniform pick with no-repeat filter.
	var d = _new_controller()
	var c = d.controller
	c.state.house_twist = {}
	c.state.previous_event_id = ""
	c._process_event_selection()
	assert_true(MatchConfig.EVENT_POOL.has(c.state.current_event_id),
		"non-twist path picks a valid event_id")
	assert_eq(c.state.current_event_id, c.state.previous_event_id,
		"non-twist path sets previous_event_id")

func test_event_selection_lowest_chips_picks_broadcasts_picker_started():
	# Twist active → broadcasts _rpc_event_picker_started and does NOT
	# eagerly set state.current_event_id (deferred to picker submit or
	# timeout).
	var d = _new_controller()
	var c = d.controller
	c.state.house_twist = {
		"type": "lowest_chips_picks",
		"params": {
			"picker_peer_id": 2,
			"options": [
				"res://scenes/events/rocket_clash/rocket_clash_event.tscn",
				"res://scenes/events/bomb_pot/bomb_pot_event.tscn",
				"res://scenes/events/card_cannon/card_cannon_event.tscn",
			],
			"timeout_sec": 10,
		},
	}
	d.fake.rpc_calls.clear()
	c._process_event_selection()
	# Verify the broadcast went out
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_event_picker_started":
			found = true
			assert_eq(int(call.args[0]), 2, "picker_peer_id forwarded")
			assert_eq(call.args[1].size(), 3, "options forwarded with 3 entries")
			break
	assert_true(found, "_rpc_event_picker_started broadcast")

func test_event_selection_lowest_chips_picks_timeout_fallback_picks_from_options():
	# Same setup, but the timer (override=0.0) bypasses immediately and
	# host should pick uniformly from options + broadcast resolved.
	var d = _new_controller()
	var c = d.controller
	c.state.rng.seed = 42
	c.state.house_twist = {
		"type": "lowest_chips_picks",
		"params": {
			"picker_peer_id": 2,
			"options": [
				"res://scenes/events/rocket_clash/rocket_clash_event.tscn",
				"res://scenes/events/bomb_pot/bomb_pot_event.tscn",
			],
			"timeout_sec": 10,
		},
	}
	d.fake.rpc_calls.clear()
	await c._process_event_selection()
	# Host fallback should have set state.current_event_id from options
	assert_true(c.state.house_twist.params.options.has(c.state.current_event_id),
		"timeout fallback picks from options")
	# And broadcast _rpc_event_picker_resolved with reason="timeout"
	var resolved_call = null
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_event_picker_resolved":
			resolved_call = call
			break
	assert_ne(resolved_call, null, "_rpc_event_picker_resolved broadcast")
	assert_eq(String(resolved_call.args[1]), "timeout",
		"reason=timeout on host fallback")
```

- [ ] **Step 3: Run, watch fail**

Expected: 3 failures (timeout-override seam missing; `_rpc_event_picker_started` not broadcast; fallback not implemented).

- [ ] **Step 4: Implement test seam + helper**

In `scripts/match/match_controller.gd`, add the test seam near `shop_timeout_sec_override` (around line 78):
```gdscript
# Test seam: override EVENT_PICKER phase timeout. -1 = use MatchConfig.
# 0.0 = bypass timer entirely (synchronous host fallback).
var event_picker_timeout_sec_override: float = -1.0
```

Add the helper near `_shop_timeout_sec` (around line 96):
```gdscript
func _event_picker_timeout_sec() -> float:
	if event_picker_timeout_sec_override >= 0.0:
		return event_picker_timeout_sec_override
	return float(MatchConfig.EVENT_PICKER_TIMEOUT_SEC)
```

- [ ] **Step 5: Implement the picker branch in `_process_event_selection`**

Replace the current `_process_event_selection` body (around line 297). The Plan A logic moves into a `_select_event_with_no_repeat` helper; the picker branch is a new entry. Change the existing function:

```gdscript
func _process_event_selection() -> void:
	# Plan B Task 4: defer to async picker flow when the twist is active.
	if state.house_twist.get("type", "") == "lowest_chips_picks":
		await _process_event_selection_with_picker()
		return
	# Plan A path: uniform random with no-repeat filter.
	_select_event_with_no_repeat()
	# Sub-project #6 Plan B Task 6 will add finalize_pending_params here
	# (so Sudden Death's condition gets resolved); placeholder hook below.
	HouseTwistController.finalize_pending_params(state)

func _select_event_with_no_repeat() -> void:
	var pool = MatchConfig.EVENT_POOL.duplicate()
	if not state.previous_event_id.is_empty():
		pool.erase(state.previous_event_id)
		if pool.is_empty():
			pool = MatchConfig.EVENT_POOL.duplicate()
	var idx = state.rng.randi() % pool.size()
	state.current_event_id = pool[idx]
	state.previous_event_id = state.current_event_id
```

Add the new `_process_event_selection_with_picker` function near the other phase handlers:

```gdscript
# Plan B Task 4: Lowest Chips Picks async picker flow.
# Host broadcasts picker UI start, awaits choice OR 10-second timeout,
# falls back to uniform-random pick from options on timeout. The host
# ALWAYS sets state.current_event_id before returning so the phase
# machine advances cleanly.
func _process_event_selection_with_picker() -> void:
	if not is_host:
		return
	var picker_peer_id = int(state.house_twist.params.get("picker_peer_id", 0))
	var options: Array = state.house_twist.params.get("options", [])
	if options.is_empty():
		# Defensive: no options to pick from. Fall back to Plan A path.
		_select_event_with_no_repeat()
		HouseTwistController.finalize_pending_params(state)
		return
	_send_rpc("_rpc_event_picker_started", [picker_peer_id, options])
	# Clear any stale prior pick
	state.current_event_id = ""
	var timeout_sec = _event_picker_timeout_sec()
	if timeout_sec <= 0.0:
		# Synchronous test path: skip the await entirely, fall through to
		# fallback. Tests can also pre-submit a choice via _rpc_event_picker_choice
		# before calling _process_event_selection if they want the happy path.
		pass
	elif not is_inside_tree():
		# Detached controller (some tests): no SceneTree for timer.
		pass
	else:
		var timer = get_tree().create_timer(timeout_sec)
		while timer.time_left > 0.0:
			if not state.current_event_id.is_empty():
				break  # picker submitted; _rpc_event_picker_choice set the id
			await get_tree().process_frame
	# Host fallback if no pick landed
	var reason = "submitted"
	if state.current_event_id.is_empty():
		var idx = state.rng.randi() % options.size()
		state.current_event_id = options[idx]
		reason = "timeout"
	state.previous_event_id = state.current_event_id
	HouseTwistController.finalize_pending_params(state)
	_send_rpc("_rpc_event_picker_resolved", [state.current_event_id, reason])
```

- [ ] **Step 6: Run, watch pass**

Expected: **553/553 tests pass** (550 prior + 3 new).

- [ ] **Step 7: Commit**

```bash
git add scripts/match/match_controller.gd scripts/match/match_config.gd tests/unit/test_match_controller_event_picker_flow.gd
git commit -F - <<'EOF'
feat(client): _process_event_selection defers to picker when twist active

Plan B Task 4 wires the host side of spec § 8.3. When
state.house_twist.type == "lowest_chips_picks":
- Broadcast _rpc_event_picker_started(picker_peer_id, options)
- Await picker submission (sets state.current_event_id via
  _rpc_event_picker_choice) or 10s timeout
- Timeout: host picks uniformly from options
- Broadcast _rpc_event_picker_resolved(chosen, reason)
- Call HouseTwistController.finalize_pending_params (Task 3) so
  Sudden Death's condition can be lazily resolved here too

Plan A's no-repeat path moves into _select_event_with_no_repeat
(unchanged behavior). New event_picker_timeout_sec_override test seam
mirrors the existing bet_loadout / shop timeout seams.

3 new tests: non-twist path unchanged; twist branch broadcasts
_rpc_event_picker_started; timeout fallback picks from options +
broadcasts _rpc_event_picker_resolved with reason=timeout.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 5: RPC trio — `_rpc_event_picker_started`, `_rpc_event_picker_choice`, `_rpc_event_picker_resolved`

The 3 new @rpc methods + the local-side `submit_event_pick(chosen_path)` entry point that picker clients call from EventPickerOverlay button presses.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_event_picker_rpc.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_match_controller_event_picker_rpc.gd`:
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

func _new_host() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(2))
	c.state.house_twist = {
		"type": "lowest_chips_picks",
		"params": {
			"picker_peer_id": 2,
			"options": [
				"res://scenes/events/rocket_clash/rocket_clash_event.tscn",
				"res://scenes/events/bomb_pot/bomb_pot_event.tscn",
			],
			"timeout_sec": 10,
		},
	}
	return {"controller": c, "fake": fake}

func test_rpc_event_picker_choice_happy_path_sets_state():
	var d = _new_host()
	var c = d.controller
	c._rpc_event_picker_choice(2, "res://scenes/events/bomb_pot/bomb_pot_event.tscn")
	assert_eq(c.state.current_event_id,
		"res://scenes/events/bomb_pot/bomb_pot_event.tscn",
		"valid pick from picker sets state.current_event_id")

func test_rpc_event_picker_choice_rejects_wrong_peer():
	# Player 1 is NOT the picker (picker is peer 2). Submitting should
	# be silently ignored — state.current_event_id stays empty.
	var d = _new_host()
	var c = d.controller
	c.state.current_event_id = ""
	c._rpc_event_picker_choice(1, "res://scenes/events/bomb_pot/bomb_pot_event.tscn")
	assert_eq(c.state.current_event_id, "",
		"non-picker submission ignored")

func test_rpc_event_picker_choice_rejects_invalid_path():
	# Picker submits a path NOT in options. Silently rejected.
	var d = _new_host()
	var c = d.controller
	c.state.current_event_id = ""
	c._rpc_event_picker_choice(2, "res://scenes/events/card_cannon/card_cannon_event.tscn")
	# Card Cannon is not in this test's options (only Rocket Clash + Bomb Pot)
	assert_eq(c.state.current_event_id, "",
		"out-of-options submission ignored")

func test_rpc_event_picker_choice_duplicate_submit_ignored():
	# Once a choice lands, subsequent submits from the picker do nothing.
	# Reason: state.current_event_id is locked once set.
	var d = _new_host()
	var c = d.controller
	c._rpc_event_picker_choice(2, "res://scenes/events/rocket_clash/rocket_clash_event.tscn")
	# Submit again with a different valid option
	c._rpc_event_picker_choice(2, "res://scenes/events/bomb_pot/bomb_pot_event.tscn")
	assert_eq(c.state.current_event_id,
		"res://scenes/events/rocket_clash/rocket_clash_event.tscn",
		"duplicate submit ignored; first pick wins")
```

- [ ] **Step 2: Run, watch fail**

Expected: 4 failures (the 3 @rpc methods + submit_event_pick don't exist).

- [ ] **Step 3: Implement @rpc methods + public submit**

In `scripts/match/match_controller.gd`, add new signals near the existing ones (around line 38):
```gdscript
signal event_picker_started(picker_peer_id: int, options: Array)
signal event_picker_resolved(chosen_path: String, reason: String)
```

Add the public submit method near the existing `submit_*` helpers (around line 175):
```gdscript
# Public: called locally by EventPickerOverlay button presses on the
# picker peer.
func submit_event_pick(chosen_path: String) -> void:
	var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
	_send_rpc("_rpc_event_picker_choice", [my_peer_id, chosen_path])
```

Add the 3 @rpc receivers near other broadcast receivers (the order doesn't matter; group with other house_twist RPCs around line 440):

```gdscript
# Plan B Task 5: picker UI start broadcast. Receives on all peers;
# picker peer's overlay shows buttons, non-pickers see a passive
# waiting banner. Re-emits a local signal for EventPickerOverlay.
@rpc("authority", "call_remote", "reliable")
func _rpc_event_picker_started(picker_peer_id: int, options: Array) -> void:
	event_picker_started.emit(picker_peer_id, options)

# Plan B Task 5: picker submits a choice. Host validates: must be the
# correct picker peer AND chosen_path must be in options. Silent reject
# on bad submit (the UI should not have shown buttons for invalid
# options); duplicate submits ignored because state.current_event_id
# is locked after the first valid pick.
@rpc("any_peer", "call_local", "reliable")
func _rpc_event_picker_choice(peer_id: int, chosen_path: String) -> void:
	if not is_host:
		return
	if state.house_twist.get("type", "") != "lowest_chips_picks":
		return  # twist already resolved or never active
	if not state.current_event_id.is_empty():
		return  # already locked (duplicate submit or timeout fired first)
	var picker_peer_id = int(state.house_twist.params.get("picker_peer_id", 0))
	if peer_id != picker_peer_id:
		return  # non-picker submission rejected
	var options: Array = state.house_twist.params.get("options", [])
	if not options.has(chosen_path):
		return  # invalid option rejected
	state.current_event_id = chosen_path

# Plan B Task 5: resolution broadcast. All peers receive the final
# picked event_id + reason (either "submitted" or "timeout") so the
# EventPickerOverlay can dismiss with the right message.
@rpc("authority", "call_remote", "reliable")
func _rpc_event_picker_resolved(chosen_path: String, reason: String) -> void:
	state.current_event_id = chosen_path
	state.previous_event_id = chosen_path
	event_picker_resolved.emit(chosen_path, reason)
```

- [ ] **Step 4: Run, watch pass**

Expected: **557/557 tests pass** (553 prior + 4 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/match/match_controller.gd tests/unit/test_match_controller_event_picker_rpc.gd
git commit -F - <<'EOF'
feat(client): @rpc trio for the Lowest Chips Picks async picker flow

Three new @rpc methods + one new submit helper:
- _rpc_event_picker_started(picker_peer_id, options): broadcast to all
  peers; picker peer's overlay shows buttons, non-pickers see passive
  waiting banner via the new event_picker_started local signal.
- _rpc_event_picker_choice(peer_id, chosen_path): @rpc("any_peer",
  "call_local", "reliable") — host validates that peer_id matches
  picker_peer_id AND chosen_path is in options. Silent reject on
  invalid; duplicate submits ignored because state.current_event_id
  locks after first valid pick.
- _rpc_event_picker_resolved(chosen_path, reason): broadcast final
  outcome; clients mirror state.current_event_id + previous_event_id
  and emit event_picker_resolved local signal.

submit_event_pick(chosen_path) is the public entry the
EventPickerOverlay will call from button presses.

4 new tests: happy path; wrong-peer reject; invalid-path reject;
duplicate-submit ignored.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 3: Sudden Death Jackpot integration (Tasks 6-9)

### Task 6: Broadcast `_rpc_house_twist_params_updated` after finalize_pending_params

Plan B Task 4 wired the `HouseTwistController.finalize_pending_params(state)` call into both branches of `_process_event_selection`. For Sudden Death Jackpot, this rewrites `state.house_twist.params.condition` on the host — clients now need to mirror that change. New broadcast `_rpc_house_twist_params_updated(params)` does this. Empty params (non-Sudden-Death) → no broadcast (cheap optimization, also tested).

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_sudden_death_finalize.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_match_controller_sudden_death_finalize.gd`:
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

func _new_host() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(2))
	return {"controller": c, "fake": fake}

func test_event_selection_with_sudden_death_finalizes_condition_and_broadcasts():
	var d = _new_host()
	var c = d.controller
	c.state.house_twist = {
		"type": "sudden_death_jackpot",
		"params": {"condition": ""},
	}
	c.state.previous_event_id = ""
	c.state.rng.seed = 1
	d.fake.rpc_calls.clear()
	c._process_event_selection()
	# Condition must be filled in
	var cond = String(c.state.house_twist.params.get("condition", ""))
	assert_ne(cond, "", "condition was populated by finalize_pending_params")
	assert_true(cond in ["cash_out_over_5x", "pull_out_after_80_pct", "locked_at_perfect"],
		"condition is one of the 3 valid strings")
	# Broadcast went out
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_house_twist_params_updated":
			found = true
			assert_eq(String(call.args[0].get("condition", "")), cond,
				"broadcast carries the resolved condition")
			break
	assert_true(found, "_rpc_house_twist_params_updated broadcast")

func test_event_selection_without_sudden_death_does_not_broadcast_params_updated():
	# Plan A path: non-Sudden-Death twist (or no twist) → no broadcast.
	var d = _new_host()
	var c = d.controller
	c.state.house_twist = {"type": "double_bounty", "params": {"reward_multiplier": 2.0}}
	c.state.previous_event_id = ""
	d.fake.rpc_calls.clear()
	c._process_event_selection()
	for call in d.fake.rpc_calls:
		assert_ne(call.method, "_rpc_house_twist_params_updated",
			"non-Sudden-Death must not broadcast params_updated")
```

- [ ] **Step 2: Run, watch fail**

Expected: 2 failures (broadcast not implemented; receiver missing).

- [ ] **Step 3: Implement the broadcast**

In `scripts/match/match_controller.gd`, modify `_process_event_selection` (the Plan A branch) AND `_process_event_selection_with_picker` to broadcast the updated params after `finalize_pending_params`. Replace the two `HouseTwistController.finalize_pending_params(state)` lines (added in Task 4) with:

```gdscript
	HouseTwistController.finalize_pending_params(state)
	_broadcast_sudden_death_finalized()
```

And add a new helper:

```gdscript
# Plan B Task 6: broadcast updated twist params after finalize_pending_params.
# Skipped unless the active twist is Sudden Death (avoids a round-trip for
# every event-selection in non-Sudden-Death rounds).
func _broadcast_sudden_death_finalized() -> void:
	if state.house_twist.get("type", "") != "sudden_death_jackpot":
		return
	if not is_host:
		return
	_send_rpc("_rpc_house_twist_params_updated", [state.house_twist.params])

# Plan B Task 6: client mirror for late-bind condition resolution.
# Replaces state.house_twist.params with the broadcast copy.
@rpc("authority", "call_remote", "reliable")
func _rpc_house_twist_params_updated(params: Dictionary) -> void:
	if state.house_twist.is_empty():
		return  # defensive: shouldn't happen, but tolerate
	state.house_twist["params"] = params.duplicate(true)
```

- [ ] **Step 4: Run, watch pass**

Expected: **559/559 tests pass** (557 prior + 2 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/match/match_controller.gd tests/unit/test_match_controller_sudden_death_finalize.gd
git commit -F - <<'EOF'
feat(client): broadcast updated twist params after Sudden Death finalize

After EVENT_SELECTION picks state.current_event_id,
HouseTwistController.finalize_pending_params(state) (Plan B Task 3)
rewrites state.house_twist.params.condition for Sudden Death Jackpot.
Clients now learn about the resolved condition via a new
_rpc_house_twist_params_updated(params) broadcast.

Helper guards: only broadcasts when twist type IS sudden_death_jackpot
(no round-trip for non-Sudden-Death event-selections); only runs
host-side. Client receiver does a defensive empty-twist check.

2 new tests cover the Sudden Death broadcast happy path + the
non-broadcast invariant for non-Sudden-Death twists.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 7: Rocket Clash Sudden Death consumer — `cash_out_over_5x` bonus crown

`compute_event_result` reads `ctx.house_twist.params.condition`. If the active twist is `sudden_death_jackpot` AND the condition is `cash_out_over_5x`, every survivor whose `cash_outs[pid] > 5.0` gets `crown_delta += 1`. Stacks with the regular Crown (so if the cash-out winner ALSO meets `> 5.0`, they get `crown_delta = 2`).

**Files:**
- Modify: `scripts/events/rocket_clash/rocket_clash_event.gd`
- Create: `tests/unit/test_rocket_clash_sudden_death.gd`

- [ ] **Step 1: Write failing test**

`tests/unit/test_rocket_clash_sudden_death.gd`:
```gdscript
extends GutTest

const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(peer_id: int, name: String, seat_index: int = -1) -> RefCounted:
	var p = MatchPlayer.new()
	p.peer_id = peer_id; p.name = name; p.is_active_this_event = true
	p.seat_index = seat_index if seat_index >= 0 else peer_id
	return p

func _make_context(player_count: int, wagers: Dictionary) -> RefCounted:
	var ctx = EventContext.new()
	for i in player_count:
		ctx.players.append(_make_player(i + 1, "P%d" % (i + 1), i))
	ctx.wagers = wagers
	return ctx

func test_sudden_death_cash_out_over_5x_awards_bonus_crown_and_stacks_with_winner():
	# P2 cashes at 6.0× (meets condition AND wins the crown for highest
	# cash-out) → crown_delta = 2. P1 cashes at 4.0× (no condition, no
	# crown) → crown_delta = 0.
	var ctx = _make_context(2, {1: 100, 2: 100})
	ctx.house_twist = {
		"type": "sudden_death_jackpot",
		"params": {"condition": "cash_out_over_5x"},
	}
	var cash_outs = {1: 4.0, 2: 6.0}
	var busted: Array = []
	var result = RocketClashEvent.compute_event_result(ctx, 10.0, cash_outs, busted)
	assert_eq(result.per_player[1].crown_delta, 0,
		"P1 cashed at 4.0× - below threshold")
	assert_eq(result.per_player[2].crown_delta, 2,
		"P2 winner + sudden death bonus = 1 + 1 = 2")
```

- [ ] **Step 2: Run, watch fail**

Expected: 1 failure (P2.crown_delta still 1).

- [ ] **Step 3: Implement**

In `scripts/events/rocket_clash/rocket_clash_event.gd`, in `compute_event_result`, AFTER the Crown award block (around line 313 — the `if winner_peer_id != 0:` block) and BEFORE building `painful_reveal`, add the Sudden Death survey:

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

- [ ] **Step 4: Run, watch pass**

Expected: **560/560 tests pass** (559 prior + 1 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/events/rocket_clash/rocket_clash_event.gd tests/unit/test_rocket_clash_sudden_death.gd
git commit -F - <<'EOF'
feat(client): Rocket Clash Sudden Death cash_out_over_5x bonus crown

When state.house_twist.params.condition == "cash_out_over_5x", every
surviving player whose cash_out > 5.0× earns +1 crown_delta. Stacks
with the regular highest-cash-out Crown: if the cash-out winner is
also > 5.0×, they end with crown_delta = 2 (the only place crown_delta
stacks beyond 1, documented in spec § 9).

1 new test verifies winner-plus-bonus stacks to 2 and below-threshold
survivors stay at 0.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 8: Bomb Pot Sudden Death consumer — `pull_out_after_80_pct` bonus crown

Survivor pulled out AND their pull-out timestamp is at or after 80% of bomb-time. `bomb_at_sec` is the `compute_event_result` argument; timestamps are in ms; condition: `pull_out_timestamps[pid] >= bomb_at_sec * 1000 * 0.80`.

**Files:**
- Modify: `scripts/events/bomb_pot/bomb_pot_event.gd`
- Create: `tests/unit/test_bomb_pot_sudden_death.gd`

- [ ] **Step 1: Write failing test**

`tests/unit/test_bomb_pot_sudden_death.gd`:
```gdscript
extends GutTest

const BombPotEvent = preload("res://scripts/events/bomb_pot/bomb_pot_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(peer_id: int, name: String, seat_index: int = -1) -> RefCounted:
	var p = MatchPlayer.new()
	p.peer_id = peer_id; p.name = name; p.is_active_this_event = true
	p.seat_index = seat_index if seat_index >= 0 else peer_id
	return p

func _make_context(player_count: int, wagers: Dictionary) -> RefCounted:
	var ctx = EventContext.new()
	for i in player_count:
		ctx.players.append(_make_player(i + 1, "P%d" % (i + 1), i))
	ctx.wagers = wagers
	return ctx

func test_sudden_death_pull_out_after_80_pct_awards_bonus_crown_and_stacks():
	# bomb_at_sec = 10.0 → 80% threshold = 8000 ms.
	# P1 pulls at 7000 ms (under threshold) → no bonus.
	# P2 pulls at 9500 ms (over threshold AND latest puller → wins regular Crown)
	# → crown_delta = 2.
	var ctx = _make_context(2, {1: 100, 2: 100})
	ctx.house_twist = {
		"type": "sudden_death_jackpot",
		"params": {"condition": "pull_out_after_80_pct"},
	}
	var locked = {1: 100, 2: 100}
	var pulled = [1, 2]
	var timestamps = {1: 7000, 2: 9500}
	var result = BombPotEvent.compute_event_result(ctx, 10.0, locked, pulled, timestamps)
	assert_eq(result.per_player[1].crown_delta, 0, "P1 below threshold")
	assert_eq(result.per_player[2].crown_delta, 2, "P2 winner + bonus = 2")
```

- [ ] **Step 2: Run, watch fail**

Expected: 1 failure (P2.crown_delta still 1).

- [ ] **Step 3: Implement**

In `scripts/events/bomb_pot/bomb_pot_event.gd`, in `compute_event_result`, AFTER the Crown award block (around line 240 — the `if winner_peer_id != 0:` block) and BEFORE building `painful_reveal`, add:

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

- [ ] **Step 4: Run, watch pass**

Expected: **561/561 tests pass** (560 prior + 1 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/events/bomb_pot/bomb_pot_event.gd tests/unit/test_bomb_pot_sudden_death.gd
git commit -F - <<'EOF'
feat(client): Bomb Pot Sudden Death pull_out_after_80_pct bonus crown

When state.house_twist.params.condition == "pull_out_after_80_pct",
every surviving puller whose pull-out timestamp is at or past 80% of
the bomb-time earns +1 crown_delta. Threshold computed as
bomb_at_sec * 1000 * 0.80 (timestamps are ms; bomb_at_sec is sec).
Stacks with the regular last-puller Crown.

1 new test: P2 wins regular Crown + bonus (9500 ms past 8000 ms
threshold for a 10 s bomb) and ends at crown_delta = 2.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 9: Card Cannon Sudden Death consumer — `locked_at_perfect` bonus crown

Survivor whose locked score equals exactly 21 (the perfect band).

**Files:**
- Modify: `scripts/events/card_cannon/card_cannon_event.gd`
- Create: `tests/unit/test_card_cannon_sudden_death.gd`

- [ ] **Step 1: Write failing test**

`tests/unit/test_card_cannon_sudden_death.gd`:
```gdscript
extends GutTest

const CardCannonEvent = preload("res://scripts/events/card_cannon/card_cannon_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(peer_id: int, name: String, seat_index: int = -1) -> RefCounted:
	var p = MatchPlayer.new()
	p.peer_id = peer_id; p.name = name; p.is_active_this_event = true
	p.seat_index = seat_index if seat_index >= 0 else peer_id
	return p

func _make_context(player_count: int, wagers: Dictionary) -> RefCounted:
	var ctx = EventContext.new()
	for i in player_count:
		ctx.players.append(_make_player(i + 1, "P%d" % (i + 1), i))
	ctx.wagers = wagers
	return ctx

func test_sudden_death_locked_at_perfect_awards_bonus_crown_and_stacks():
	# P1 locks 18 (no bonus). P2 locks exactly 21 (perfect — bonus AND
	# wins regular Crown via highest locked score). P2 → crown_delta = 2.
	var ctx = _make_context(2, {1: 100, 2: 100})
	ctx.house_twist = {
		"type": "sudden_death_jackpot",
		"params": {"condition": "locked_at_perfect"},
	}
	var hands = {1: [10, 8], 2: [10, 11]}
	var locked = {1: 18, 2: 21}
	var busted = {}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	assert_eq(result.per_player[1].crown_delta, 0, "P1 below 21")
	assert_eq(result.per_player[2].crown_delta, 2, "P2 perfect + winner = 2")
```

- [ ] **Step 2: Run, watch fail**

Expected: 1 failure (P2.crown_delta still 1).

- [ ] **Step 3: Implement**

In `scripts/events/card_cannon/card_cannon_event.gd`, in `compute_event_result`, AFTER the Crown award block (around line 254 — the `if winner_peer_id != 0 and winner_score > 0:` block) and BEFORE building `painful_reveal`:

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

- [ ] **Step 4: Run, watch pass**

Expected: **562/562 tests pass** (561 prior + 1 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/events/card_cannon/card_cannon_event.gd tests/unit/test_card_cannon_sudden_death.gd
git commit -F - <<'EOF'
feat(client): Card Cannon Sudden Death locked_at_perfect bonus crown

When state.house_twist.params.condition == "locked_at_perfect", every
surviving player whose locked score is exactly 21 earns +1 crown_delta.
Stacks with the regular highest-locked-score Crown — a player who
locks 21 (the perfect band) wins both.

1 new test: P2 locks exactly 21, wins regular Crown, plus the Sudden
Death bonus → crown_delta = 2.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 4: UI (Tasks 10-11)

### Task 10: `EventPickerOverlay` widget

PanelContainer with: 3 picker buttons (visible only when `local_peer_id == picker_peer_id`); passive waiting banner "Waiting for P<n>..." (visible otherwise); countdown timer label. Subscribes to `controller.event_picker_started` + `controller.event_picker_resolved`. Static formatter `format_event_button_label(event_id) -> String` for testable strings (mirrors `house_twist_overlay.format_twist_title` shape).

**Files:**
- Create: `scripts/ui/event_picker_overlay.gd`
- Create: `scenes/ui/event_picker_overlay.tscn`
- Create: `tests/unit/test_event_picker_overlay.gd`

- [ ] **Step 1: Write failing tests (static formatter)**

`tests/unit/test_event_picker_overlay.gd`:
```gdscript
extends GutTest

const EventPickerOverlay = preload("res://scripts/ui/event_picker_overlay.gd")

func test_format_event_button_label_per_event_id():
	assert_eq(EventPickerOverlay.format_event_button_label(
		"res://scenes/events/rocket_clash/rocket_clash_event.tscn"), "Rocket Clash")
	assert_eq(EventPickerOverlay.format_event_button_label(
		"res://scenes/events/bomb_pot/bomb_pot_event.tscn"), "Bomb Pot")
	assert_eq(EventPickerOverlay.format_event_button_label(
		"res://scenes/events/card_cannon/card_cannon_event.tscn"), "Card Cannon")
	assert_eq(EventPickerOverlay.format_event_button_label(""), "")

func test_format_waiting_banner_includes_picker_name():
	assert_eq(EventPickerOverlay.format_waiting_banner("P2"),
		"Waiting for P2 to pick the next event...")
	assert_eq(EventPickerOverlay.format_waiting_banner(""),
		"Waiting for the picker to choose...")
```

- [ ] **Step 2: Run, watch fail**

Expected: EventPickerOverlay preload error (file doesn't exist).

- [ ] **Step 3: Implement script**

`scripts/ui/event_picker_overlay.gd`:
```gdscript
# EventPickerOverlay: shown during EVENT_SELECTION when the active twist
# is lowest_chips_picks. Picker peer sees 3 buttons + countdown; non-picker
# peers see a passive waiting banner. Hides on event_picker_resolved.
extends PanelContainer

@onready var _picker_row: HBoxContainer = $VBox/PickerRow if has_node("VBox/PickerRow") else null
@onready var _waiting_label: Label = $VBox/WaitingLabel if has_node("VBox/WaitingLabel") else null
@onready var _countdown_label: Label = $VBox/CountdownLabel if has_node("VBox/CountdownLabel") else null

var controller  # MatchController-like
var local_player  # MatchPlayer-like (has peer_id)
var _is_picker: bool = false
var _options: Array = []
var _picker_peer_id: int = 0

func _ready() -> void:
	visible = false
	if controller != null:
		controller.event_picker_started.connect(_on_event_picker_started)
		controller.event_picker_resolved.connect(_on_event_picker_resolved)

func _on_event_picker_started(picker_peer_id: int, options: Array) -> void:
	_picker_peer_id = picker_peer_id
	_options = options
	var local_peer_id = local_player.peer_id if local_player != null else 0
	_is_picker = (local_peer_id == picker_peer_id)
	_rebuild_buttons()
	_refresh_waiting_label()
	visible = true

func _on_event_picker_resolved(_chosen_path: String, _reason: String) -> void:
	visible = false
	_options = []

func _rebuild_buttons() -> void:
	if _picker_row == null:
		return
	for child in _picker_row.get_children():
		child.queue_free()
	if not _is_picker:
		_picker_row.visible = false
		return
	_picker_row.visible = true
	for event_id in _options:
		var btn = Button.new()
		btn.text = format_event_button_label(event_id)
		btn.pressed.connect(func(): _on_pick_pressed(event_id))
		_picker_row.add_child(btn)

func _on_pick_pressed(chosen_path: String) -> void:
	if controller != null:
		controller.submit_event_pick(chosen_path)
	# Optimistically disable further presses; controller broadcast
	# event_picker_resolved will hide the overlay.
	if _picker_row != null:
		for child in _picker_row.get_children():
			if child is Button:
				child.disabled = true

func _refresh_waiting_label() -> void:
	if _waiting_label == null:
		return
	if _is_picker:
		_waiting_label.text = ""
		_waiting_label.visible = false
	else:
		_waiting_label.visible = true
		var picker_name = _picker_name_from_controller()
		_waiting_label.text = format_waiting_banner(picker_name)

func _picker_name_from_controller() -> String:
	if controller == null or controller.state == null:
		return ""
	var p = controller.state.find_player(_picker_peer_id)
	return p.name if p != null else ""

# Static formatters (testable without scene)

static func format_event_button_label(event_id: String) -> String:
	if event_id.ends_with("rocket_clash_event.tscn"):
		return "Rocket Clash"
	if event_id.ends_with("bomb_pot_event.tscn"):
		return "Bomb Pot"
	if event_id.ends_with("card_cannon_event.tscn"):
		return "Card Cannon"
	return ""

static func format_waiting_banner(picker_name: String) -> String:
	if picker_name.is_empty():
		return "Waiting for the picker to choose..."
	return "Waiting for %s to pick the next event..." % picker_name
```

- [ ] **Step 4: Implement scene**

`scenes/ui/event_picker_overlay.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/event_picker_overlay.gd" id="1"]

[node name="EventPickerOverlay" type="PanelContainer"]
script = ExtResource("1")

[node name="VBox" type="VBoxContainer" parent="."]

[node name="WaitingLabel" type="Label" parent="VBox"]
text = ""

[node name="PickerRow" type="HBoxContainer" parent="VBox"]

[node name="CountdownLabel" type="Label" parent="VBox"]
text = ""
```

- [ ] **Step 5: Run, watch pass**

Expected: **564/564 tests pass** (562 prior + 2 new).

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/event_picker_overlay.gd scenes/ui/event_picker_overlay.tscn tests/unit/test_event_picker_overlay.gd
git commit -F - <<'EOF'
feat(client): EventPickerOverlay widget for Lowest Chips Picks

PanelContainer with a picker button row (visible only when
local_peer_id == picker_peer_id), a waiting banner (visible otherwise),
and a countdown label slot for sub-project #7 polish to fill in.
Subscribes to controller.event_picker_started + event_picker_resolved
(both signals added in Plan B Task 5).

submit_event_pick(chosen_path) fires on button press; optimistic
disable prevents double-tap. The picker_resolved broadcast hides the
overlay for all peers.

Static formatters format_event_button_label (per-event-id label) and
format_waiting_banner (per-picker-name passive text) are testable
without scene instantiation. 2 new tests cover all 3 event labels +
both waiting-banner branches.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 11: MatchScene wiring for EventPickerOverlay

Adds the `EventPickerSlot` container + builder method. CRITICAL: set `controller` (and `local_player`) BEFORE `add_child` — mirrors Plan A's `_build_house_twist_overlay` ordering so the overlay's `_ready()` sees a non-null controller for signal connection.

**Files:**
- Modify: `scripts/ui/match_scene.gd`
- Modify: `scenes/match_scene.tscn`

- [ ] **Step 1: Read existing wiring for patterns**

Read `scripts/ui/match_scene.gd` (focus on `_build_house_twist_overlay` and `_build_shop_overlay` shapes).

- [ ] **Step 2: Add slot to scene file**

In `scenes/match_scene.tscn`, near the existing `HouseTwistSlot`, add a new container:
```
[node name="EventPickerSlot" type="Container" parent="VBox"]
```

- [ ] **Step 3: Add to match_scene.gd**

Add the preload near other UI scene preloads:
```gdscript
const EventPickerOverlayScene = preload("res://scenes/ui/event_picker_overlay.tscn")
```

Add the `@onready` slot reference + instance field near other overlay fields:
```gdscript
@onready var _event_picker_slot: Container = $VBox/EventPickerSlot if has_node("VBox/EventPickerSlot") else null
var _event_picker_overlay: Node = null
```

In `_ready()`, after `_build_house_twist_overlay()`, add:
```gdscript
	_build_event_picker_overlay()
```

Add the builder method (mirror Plan A's `_build_house_twist_overlay` exactly):
```gdscript
func _build_event_picker_overlay() -> void:
	if _event_picker_slot == null:
		return
	_event_picker_overlay = EventPickerOverlayScene.instantiate()
	# CRITICAL: set controller + local_player BEFORE add_child so the
	# overlay's _ready() sees non-null controller for signal connection.
	# Mirrors _build_house_twist_overlay + Plan A Task 16's pattern.
	_event_picker_overlay.controller = controller
	_event_picker_overlay.local_player = _find_local_player()
	_event_picker_slot.add_child(_event_picker_overlay)
```

- [ ] **Step 4: Run suite (no new tests; verify no regression)**

Expected: **564/564 tests still passing**.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/match_scene.gd scenes/match_scene.tscn
git commit -F - <<'EOF'
feat(client): wire EventPickerOverlay into MatchScene

EventPickerSlot container added to match_scene.tscn next to the
existing HouseTwistSlot. match_scene.gd preloads
EventPickerOverlayScene, declares slot + instance refs, and adds
_build_event_picker_overlay that runs in _ready alongside
_build_house_twist_overlay.

Critical: controller AND local_player set BEFORE add_child so the
overlay's _ready() can connect to controller.event_picker_started /
event_picker_resolved signals AND know whether the local peer is
the picker. Mirrors Plan A Task 16's pattern verbatim.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 5: Integration + docs (Task 12)

### Task 12: Integration test PENDING stub + PLAYTEST_CHECKLIST update

One new integration test that PENDINGs cleanly without the signaling server, mirroring Plan A's pattern. Plus 6 new playtest scenarios for the Plan B twists.

**Files:**
- Create: `tests/integration/test_lowest_chips_picker.gd`
- Modify: `docs/PLAYTEST_CHECKLIST.md`

- [ ] **Step 1: Create integration placeholder**

`tests/integration/test_lowest_chips_picker.gd`:
```gdscript
# Integration smoke test: real signaling + WebRTC + lowest_chips_picks
# twist drives the async picker flow. Spawns two NetSession instances;
# starts a match; forces the twist; verifies the picker peer's
# EventPickerOverlay shows buttons + the non-picker sees the waiting
# banner; submits a pick from the picker peer; verifies all peers'
# state.current_event_id mirror.
#
# Skips if signaling server is not reachable on ws://localhost:8080.
extends GutTest

const SIGNALING_URL := "ws://localhost:8080"

func _signaling_reachable() -> bool:
	var probe = WebSocketPeer.new()
	var err = probe.connect_to_url(SIGNALING_URL)
	if err != OK:
		return false
	var t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1000:
		probe.poll()
		if probe.get_ready_state() == WebSocketPeer.STATE_OPEN:
			probe.close()
			return true
		if probe.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			return false
		await get_tree().process_frame
	probe.close()
	return false

func test_lowest_chips_picker_flow_across_peers():
	if not await _signaling_reachable():
		pending("Signaling server not reachable at %s; skipping. Start with `cd ../signaling-server && node server.js`." % SIGNALING_URL)
		return
	# Implementer note: cargo-cult test_three_event_rotation.gd / Plan A's
	# test_house_twist_announce.gd. Force state.house_twist.type to
	# "lowest_chips_picks" via direct mutation before EVENT_SELECTION
	# fires; submit submit_event_pick from the picker peer; assert both
	# peers' state.current_event_id mirror after _rpc_event_picker_resolved.
	pending("Implementer: cargo-cult test_house_twist_announce.gd; assert picker submit propagates state.current_event_id across peers + verify timeout fallback on the host side.")
```

- [ ] **Step 2: Update PLAYTEST_CHECKLIST.md**

Append:

```markdown
## Sub-project #6 Plan B additions

| # | Scenario | Pass criteria |
|---|----------|---------------|
| 22 | Lowest Chips Picks: picker UI on lowest-chips peer | At HOUSE_TWIST → EVENT_SELECTION, the lowest-chips player's screen shows EventPickerOverlay with 3 buttons (Rocket Clash / Bomb Pot / Card Cannon); other peers see "Waiting for P<n> to pick the next event..." |
| 23 | Lowest Chips Picks: pick propagates | Picker clicks one of the 3 buttons → all peers' state.current_event_id matches the picked path; EventPickerOverlay hides; MAIN_EVENT loads the chosen event |
| 24 | Lowest Chips Picks: 10s timeout fallback | Picker does nothing for 10 seconds → host picks uniformly from options + broadcasts _rpc_event_picker_resolved with reason="timeout"; toast or banner mentions the timeout |
| 25 | Sudden Death + Rocket Clash: cash_out_over_5x | Twist announced (state.house_twist.type == "sudden_death_jackpot"); after EVENT_SELECTION picks Rocket Clash, state.house_twist.params.condition == "cash_out_over_5x"; any survivor who cashes > 5.0× earns +1 crown_delta (stacks with regular Crown to 2 if they also win highest cash-out) |
| 26 | Sudden Death + Bomb Pot: pull_out_after_80_pct | Same flow → condition = "pull_out_after_80_pct"; pullers whose pull-out timestamp >= 80% of bomb-time earn +1 crown_delta |
| 27 | Sudden Death + Card Cannon: locked_at_perfect | Same flow → condition = "locked_at_perfect"; any survivor who locks exactly 21 earns +1 crown_delta |
```

- [ ] **Step 3: Run unit suite (PLAYTEST + integration stub don't affect unit count)**

Expected: **564/564 unit tests still passing**. Integration suite: 6 prior + 1 new = **7 PENDING**.

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test_lowest_chips_picker.gd docs/PLAYTEST_CHECKLIST.md
git commit -F - <<'EOF'
test+docs(client): Plan B integration stub + playtest scenarios

Integration test: PENDING placeholder per sub-project #3/#4/#5/Plan A
precedent; manual verification via running the game is the primary
surface. Stub verifies (a) picker UI shows only on lowest-chips peer,
(b) submit_event_pick propagates state.current_event_id across peers,
(c) 10s timeout falls back to host pick.

PLAYTEST_CHECKLIST: 6 new scenarios covering Lowest Chips Picks UI +
propagation + timeout, plus Sudden Death Jackpot conditions across
all 3 events (cash_out_over_5x / pull_out_after_80_pct /
locked_at_perfect).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Done

Plan B complete. Sub-project #6 Plan B delivers:
- 2 of 6 MVP House Twists fully wired (Lowest Chips Picks async picker + Sudden Death Jackpot lazy-condition crown bonus)
- Full TWIST_POOL active (PLAN_A_TWISTS subset retired; all 6 twists selectable)
- New RPC trio for the async picker flow + new `_rpc_house_twist_params_updated` for Sudden Death late-bind
- New EventPickerOverlay UI widget
- +23 new unit tests + 1 new integration test target

**Cumulative state after Plan B merge:**
- Test suite: ~564 unit + 7 integration
- 6 House Twists rotating; 3-event pool unchanged
- 12 power cards unchanged (Plan B introduces no new cards)

**Tags after Plan B merges:** `subproject-6-plan-b-complete` + `subproject-6-complete`.

**Memory updates after Plan B merges:**
- `MEMORY.md` / `project_riskroyal.md` — mark sub-project #6 fully complete; #7 next
- `project_riskroyal_followups.md` — close all Plan A carry-forwards if Plan B addressed them; document any Plan B review fixups. Specifically: Task 1 closes the "start_match doesn't reset twist tracking" carry-forward; DRY extraction of twist consumer pattern remains open and explicitly inherited by sub-project #7 (Polish) along with the find_chip_leader divergence note.
