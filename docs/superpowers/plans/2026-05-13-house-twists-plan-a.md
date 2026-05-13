# House Twists Implementation Plan — Plan A

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the foundation + 4 simpler House Twists (Double Bounty Round, No Insurance, Leader Starts Cursed, Power Surge) + the carry-forward harmonization from sub-project #5 (M1 scene-path unification + M2 `_send_rpc` hoist to `event_node.gd` base + tunable event constants via `EventContext.tuning` + no-repeat event-pool selection).

**Architecture:** Single `state.house_twist: Dictionary` populated at HOUSE_TWIST phase by a new `HouseTwistController` static helper. Consumers are existing collaborators (BountyResolver, CardEffectDispatcher, the 3 events' `compute_event_result`) reading state keys — no new dispatcher branches; no new cards. A `HouseTwistOverlay` UI announces the active twist as a 3-second banner then shrinks to a corner chip. Plan B (separate) layers Lowest Chips Picks (async picker UI) + Sudden Death Jackpot (per-event Crown bonus) on top of this foundation.

**Tech Stack:** Godot 4.6, GDScript with tabs (no `class_name`), GUT testing framework, host-authoritative RPC pattern with `@rpc("any_peer", "call_local", "reliable")` for requests and `@rpc("authority", "call_remote", "reliable")` for broadcasts. `FakeMultiplayerNode` injection for RPC testing.

**Baseline (post sub-project #5 merge):** 504 unit + 5 integration tests passing. **Target after Task 17 (end of Plan A):** ~538 unit + 6 integration (+34 new unit + 1 new integration). Plan B will add ~15 more unit tests for Lowest Chips Picks + Sudden Death Jackpot.

---

## File Structure

**New files (Plan A):**
- `scripts/match/house_twist_controller.gd` — static helper for twist selection + per-twist params + eager effects
- `scripts/ui/house_twist_overlay.gd` + `scenes/ui/house_twist_overlay.tscn` — twist announce banner + corner chip
- 8 new test files (per-task)
- `tests/integration/test_house_twist_announce.gd` — integration PENDING placeholder

**Modified files (Plan A):**
- `scripts/match/match_state.gd` — 3 new fields (`house_twist`, `last_twist_type`, `previous_event_id`)
- `scripts/events/event_context.gd` — 2 new fields (`house_twist`, `tuning`)
- `scripts/events/event_node.gd` — hoists `_send_rpc`/`_send_rpc_to_peer` + `_multiplayer_node` field + self-wire (M2 harmonization)
- `scripts/events/rocket_clash/rocket_clash_event.gd` — strips local `_send_rpc` copies; populates `ctx.tuning` in `_run`
- `scripts/events/bomb_pot/bomb_pot_event.gd` — same strip + populate
- `scripts/events/card_cannon/card_cannon_event.gd` — same strip + populate
- `scripts/match/match_controller.gd` — `_build_event_context` adds house_twist+tuning; `_process_event_selection` no-repeat; `_process_house_twist` phase handler; `_resolve_bounties` reads double_bounty multiplier; `_apply_effect_result` wrapper short-circuits insurance under no_insurance twist
- `scripts/match/bounty_resolver.gd` — `resolve` reads `state.house_twist.params.reward_multiplier`
- `scripts/match/card_effect_dispatcher.gd` — `apply` short-circuits `insurance_pre` under `no_insurance`
- `scripts/ui/match_scene.gd` + `scenes/match_scene.tscn` — wire HouseTwistOverlay into a HouseTwistSlot
- `scripts/match/match_config.gd` — EVENT_POOL string for Rocket Clash updates to the new scene path
- `tests/unit/test_match_config.gd` — assertion mirror for the new Rocket Clash path
- `docs/PLAYTEST_CHECKLIST.md` — 4 new scenarios for Plan A twists

**Moved file (Plan A Task 4 — M1 harmonization):**
- `scripts/events/rocket_clash/rocket_clash_event.tscn` → `scenes/events/rocket_clash/rocket_clash_event.tscn`

---

## Phase 1: State + EventContext foundation (Tasks 1-2)

### Task 1: MatchState new fields + round-trip

Adds the three fields the entire sub-project consumes: `house_twist` (active twist data), `last_twist_type` (no-repeat tracker), `previous_event_id` (no-repeat event-pool tracker). All round-trip via `to_dict()` / `from_dict()`.

**Files:**
- Modify: `scripts/match/match_state.gd`
- Create: `tests/unit/test_match_state_house_twist_fields.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_match_state_house_twist_fields.gd`:
```gdscript
extends GutTest

const MatchState = preload("res://scripts/match/match_state.gd")

func test_house_twist_defaults_empty_dict():
	var s = MatchState.new()
	assert_eq(s.house_twist, {})

func test_last_twist_type_defaults_empty_string():
	var s = MatchState.new()
	assert_eq(s.last_twist_type, "")

func test_previous_event_id_defaults_empty_string():
	var s = MatchState.new()
	assert_eq(s.previous_event_id, "")

func test_round_trip_preserves_house_twist_fields():
	var s = MatchState.new()
	s.house_twist = {"type": "double_bounty", "params": {"reward_multiplier": 2.0}}
	s.last_twist_type = "double_bounty"
	s.previous_event_id = "res://scenes/events/rocket_clash/rocket_clash_event.tscn"
	var d = s.to_dict()
	var s2 = MatchState.from_dict(d)
	assert_eq(s2.house_twist.get("type", ""), "double_bounty")
	assert_almost_eq(float(s2.house_twist.get("params", {}).get("reward_multiplier", 0.0)), 2.0, 0.001)
	assert_eq(s2.last_twist_type, "double_bounty")
	assert_eq(s2.previous_event_id, "res://scenes/events/rocket_clash/rocket_clash_event.tscn")
```

- [ ] **Step 2: Run, watch fail**

```
godot --headless --path c:/Users/whann/Desktop/Games/RocketMan -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
```
Expected: 4 failures (missing fields on MatchState).

- [ ] **Step 3: Implement**

In `scripts/match/match_state.gd`, add fields near the existing block (after `pending_card_effects`):

```gdscript
# Sub-project #6 (House Twists)
var house_twist: Dictionary = {}           # active twist: {type: String, params: Dictionary} or {}
var last_twist_type: String = ""           # for no-repeat selection filter
var previous_event_id: String = ""         # for no-repeat event-pool selection
```

Update `to_dict()` to include the new fields (use `.duplicate(true)` for `house_twist` to deep-copy the nested params dict):

Find the existing `to_dict()` return statement and add these three keys before the closing `}`:
```gdscript
		"house_twist": house_twist.duplicate(true),
		"last_twist_type": last_twist_type,
		"previous_event_id": previous_event_id,
```

Update `from_dict()` similarly. After the existing `s.pending_card_effects = ...` line, add:
```gdscript
	s.house_twist = d.get("house_twist", {}).duplicate(true)
	s.last_twist_type = d.get("last_twist_type", "")
	s.previous_event_id = d.get("previous_event_id", "")
```

- [ ] **Step 4: Run, watch pass**

Expected: **508/508 tests pass** (504 prior + 4 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/match/match_state.gd tests/unit/test_match_state_house_twist_fields.gd
git commit -F - <<'EOF'
feat(client): MatchState fields for House Twists

Three new fields with round-trip support:
- house_twist (active twist data, {type: String, params: Dictionary})
- last_twist_type (most recent twist type, for no-repeat selection filter)
- previous_event_id (most recent event scene path, for no-repeat
  event-pool selection)

house_twist uses .duplicate(true) on serialize/deserialize for nested
params dict safety; the two strings are scalar.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 2: EventContext new fields + round-trip

Adds `house_twist` (snapshot from state at MAIN_EVENT entry) and `tuning` (per-event tunable values populated in `_run`). These are the data plumbing that consumers in later tasks read from.

**Files:**
- Modify: `scripts/events/event_context.gd`
- Create: `tests/unit/test_event_context_house_twist_and_tuning.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_event_context_house_twist_and_tuning.gd`:
```gdscript
extends GutTest

const EventContext = preload("res://scripts/events/event_context.gd")

func test_house_twist_defaults_empty_dict():
	var ctx = EventContext.new()
	assert_eq(ctx.house_twist, {})

func test_tuning_defaults_empty_dict():
	var ctx = EventContext.new()
	assert_eq(ctx.tuning, {})

func test_round_trip_preserves_house_twist_and_tuning():
	var ctx = EventContext.new()
	ctx.house_twist = {"type": "leader_cursed", "params": {"leader_peer_id": 3, "reward_multiplier": 0.75}}
	ctx.tuning = {"growth_rate": 0.18, "instabust_prob": 0.05}
	var d = ctx.to_dict()
	var ctx2 = EventContext.from_dict(d)
	assert_eq(ctx2.house_twist.get("type", ""), "leader_cursed")
	assert_eq(ctx2.house_twist.get("params", {}).get("leader_peer_id", 0), 3)
	assert_almost_eq(float(ctx2.tuning.get("growth_rate", 0.0)), 0.18, 0.001)
```

- [ ] **Step 2: Run, watch fail**

Expected: 3 failures (missing fields).

- [ ] **Step 3: Implement**

Read `scripts/events/event_context.gd` to see existing structure. Add two fields near existing `event_modifiers`:
```gdscript
var house_twist: Dictionary = {}  # Snapshot from state.house_twist at MAIN_EVENT entry
var tuning: Dictionary = {}       # Per-event tunable values populated by each event's _run
```

Update `to_dict()` adding two keys before the closing brace:
```gdscript
		"house_twist": house_twist.duplicate(true),
		"tuning": tuning.duplicate(true),
```

Update `from_dict()` adding two lines after the existing `event_modifiers` line:
```gdscript
	c.house_twist = d.get("house_twist", {}).duplicate(true)
	c.tuning = d.get("tuning", {}).duplicate(true)
```

- [ ] **Step 4: Run, watch pass**

Expected: **511/511 tests pass** (508 prior + 3 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/events/event_context.gd tests/unit/test_event_context_house_twist_and_tuning.gd
git commit -F - <<'EOF'
feat(client): EventContext fields for House Twists + tuning

Two new fields with round-trip support:
- house_twist (snapshot from state.house_twist at MAIN_EVENT entry;
  consumed by compute_event_result for Leader Cursed + Sudden Death)
- tuning (per-event tunable values populated by each event's _run;
  overridable via state.house_twist.params.tuning_overrides in future
  sub-projects)

Both use .duplicate(true) for nested-dict safety.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 2: Events-pattern harmonization (Tasks 3-4 — M1 + M2 carry-forwards from #5)

### Task 3: Hoist `_send_rpc` + self-wire into `event_node.gd` base

Closes sub-project #5 final-review item M2. Currently all 3 events (Rocket Clash, Bomb Pot, Card Cannon) duplicate `_send_rpc` + `_send_rpc_to_peer` + `_multiplayer_node` field + the `is_inside_tree()` self-wire in `_run`. Hoists those into `event_node.gd` so subclasses inherit them.

**Important:** all 504 existing tests must still pass after this task. Run the suite before AND after to catch regressions.

**Files:**
- Modify: `scripts/events/event_node.gd`
- Modify: `scripts/events/rocket_clash/rocket_clash_event.gd`
- Modify: `scripts/events/bomb_pot/bomb_pot_event.gd`
- Modify: `scripts/events/card_cannon/card_cannon_event.gd`

- [ ] **Step 1: Confirm baseline**

```
godot --headless --path c:/Users/whann/Desktop/Games/RocketMan -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
```
Expected: 511/511 (matches Task 2's commit).

- [ ] **Step 2: Implement base class additions**

Read `scripts/events/event_node.gd` first. It currently extends `Node` and declares signals `event_complete` + `event_progress`.

Add the field + helpers AFTER the existing signal declarations:

```gdscript
# Sub-project #6 Plan A Task 3: hoisted from RC/BP/CC for M2 harmonization.
# Subclasses set _multiplayer_node directly (test injection) or call
# super._run(context) which self-wires when in-tree.
var _multiplayer_node = null

func _run(context) -> void:
	# Default self-wire; subclasses MUST call super._run(context) at the
	# top of their override to inherit this.
	if _multiplayer_node == null and is_inside_tree():
		_multiplayer_node = self

func _send_rpc(method_name: String, args: Array = []) -> void:
	if _multiplayer_node == null:
		return
	match args.size():
		0: _multiplayer_node.rpc(method_name)
		1: _multiplayer_node.rpc(method_name, args[0])
		2: _multiplayer_node.rpc(method_name, args[0], args[1])
		3: _multiplayer_node.rpc(method_name, args[0], args[1], args[2])
		4: _multiplayer_node.rpc(method_name, args[0], args[1], args[2], args[3])
		_:
			push_error("EventNode._send_rpc: unsupported arity %d" % args.size())

func _send_rpc_to_peer(peer_id: int, method_name: String, args: Array = []) -> void:
	if _multiplayer_node == null:
		return
	match args.size():
		0: _multiplayer_node.rpc_id(peer_id, method_name)
		1: _multiplayer_node.rpc_id(peer_id, method_name, args[0])
		2: _multiplayer_node.rpc_id(peer_id, method_name, args[0], args[1])
		_:
			push_error("EventNode._send_rpc_to_peer: unsupported arity %d" % args.size())
```

- [ ] **Step 3: Strip duplicates from Rocket Clash**

In `scripts/events/rocket_clash/rocket_clash_event.gd`:

1. DELETE the local `var _multiplayer_node = null` line (inherits from base).
2. DELETE the local `_send_rpc` function entirely.
3. DELETE the local `_send_rpc_to_peer` function entirely.
4. **`_run` override is required after this task** (Tasks 5 and 14 will both add code to it). The base class's `_run` performs the self-wire when in-tree; the Rocket Clash override must call `super._run(context)` so the wire fires.
   - **If Rocket Clash already has a `_run` override:** add `super._run(context)` as the FIRST line; then DELETE any local self-wire (`if _multiplayer_node == null and is_inside_tree(): _multiplayer_node = self`) wherever it lives in the file (most likely inside `_on_rocket_launched_local`).
   - **If Rocket Clash has no `_run` override:** ADD one:
     ```gdscript
     func _run(context) -> void:
     	super._run(context)
     ```
     Then DELETE the local self-wire from wherever it lives (likely `_on_rocket_launched_local`).
5. Read the file end-to-end after the edits to confirm no leftover self-wire pattern remains in any method.

- [ ] **Step 4: Strip duplicates from Bomb Pot**

Same operation in `scripts/events/bomb_pot/bomb_pot_event.gd`:

1. DELETE `var _multiplayer_node = null`.
2. DELETE `_send_rpc` function.
3. DELETE `_send_rpc_to_peer` function.
4. Replace the self-wire in `_run` with `super._run(context)`. Specifically, find:
   ```gdscript
   func _run(context) -> void:
   	_stashed_context = context
   	_is_host = context.is_host
   	# Self-wire _multiplayer_node when in-tree and not explicitly injected
   	# (e.g. by tests). Matches RocketClashEvent's pattern so production RPC
   	# routing works whenever MatchController adds the event to the scene tree.
   	if _multiplayer_node == null and is_inside_tree():
   		_multiplayer_node = self
   	_active_peers = []
   ```
   Replace with:
   ```gdscript
   func _run(context) -> void:
   	super._run(context)  # base self-wires _multiplayer_node
   	_stashed_context = context
   	_is_host = context.is_host
   	_active_peers = []
   ```

- [ ] **Step 5: Strip duplicates from Card Cannon**

Same pattern in `scripts/events/card_cannon/card_cannon_event.gd`:

1. DELETE `var _multiplayer_node = null`.
2. DELETE `_send_rpc` (4-arity version — base now covers 0-4, so no regression).
3. DELETE `_send_rpc_to_peer`.
4. Replace self-wire in `_run` with `super._run(context)`.

- [ ] **Step 6: Run, verify zero regressions**

Expected: **511/511 tests still pass** (no new tests; refactor only).

If any test fails, debug: most likely cause is that a subclass's `_run` doesn't call `super._run` so `_multiplayer_node` stays null where it shouldn't, OR a test bypasses `_run` entirely but expected the local field. Tests typically inject `_multiplayer_node` directly so this shouldn't break them, but verify.

- [ ] **Step 7: Commit**

```bash
git add scripts/events/event_node.gd scripts/events/rocket_clash/rocket_clash_event.gd scripts/events/bomb_pot/bomb_pot_event.gd scripts/events/card_cannon/card_cannon_event.gd
git commit -F - <<'EOF'
refactor(client): hoist _send_rpc + self-wire to event_node.gd base

Closes sub-project #5 final-review M2: deduplicates _send_rpc /
_send_rpc_to_peer / _multiplayer_node field across Rocket Clash,
Bomb Pot, Card Cannon. Base class now provides:
- var _multiplayer_node = null
- _send_rpc (arity 0-4, matches Card Cannon's max)
- _send_rpc_to_peer (arity 0-2)
- _run that self-wires _multiplayer_node = self when in-tree

Subclasses call super._run(context) at the top of their override
to inherit the self-wire. All 511 existing tests still pass.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 4: Scene-path unification (M1 carry-forward)

Closes sub-project #5 final-review item M1. Rocket Clash's `.tscn` lives at `scripts/events/rocket_clash/rocket_clash_event.tscn` (legacy from sub-project #3). Bomb Pot and Card Cannon use the convention `scenes/events/<event>/<event>.tscn`. Unify on the latter.

The `.tscn`'s internal `ext_resource` pointer to `rocket_clash_event.gd` is a `res://` path (not a relative file path) so the move doesn't break it.

**Files:**
- Move: `scripts/events/rocket_clash/rocket_clash_event.tscn` → `scenes/events/rocket_clash/rocket_clash_event.tscn`
- Modify: `scripts/match/match_config.gd` (EVENT_POOL entry)
- Modify: `tests/unit/test_match_config.gd` (assertion mirror, if it asserts the exact path)

- [ ] **Step 1: Confirm baseline**

Run suite — expect 511/511 passing.

- [ ] **Step 2: Move the scene file**

```bash
mkdir -p scenes/events/rocket_clash
git mv scripts/events/rocket_clash/rocket_clash_event.tscn scenes/events/rocket_clash/rocket_clash_event.tscn
```

(If `git mv` doesn't work because the file isn't yet tracked, use a plain `mv`.)

If a `.tscn.uid` file exists at the source, delete it (`rm scripts/events/rocket_clash/rocket_clash_event.tscn.uid`) — Godot will regenerate at the new location on next import.

- [ ] **Step 3: Update EVENT_POOL**

In `scripts/match/match_config.gd`, find the `EVENT_POOL` array (it should currently have 3 entries):
```gdscript
const EVENT_POOL: Array = [
	"res://scripts/events/rocket_clash/rocket_clash_event.tscn",
	"res://scenes/events/bomb_pot/bomb_pot_event.tscn",
	"res://scenes/events/card_cannon/card_cannon_event.tscn",
]
```

Update the Rocket Clash entry:
```gdscript
const EVENT_POOL: Array = [
	"res://scenes/events/rocket_clash/rocket_clash_event.tscn",
	"res://scenes/events/bomb_pot/bomb_pot_event.tscn",
	"res://scenes/events/card_cannon/card_cannon_event.tscn",
]
```

- [ ] **Step 4: Audit other references**

Search the codebase for the OLD path to catch any stragglers:

```bash
grep -rn "scripts/events/rocket_clash/rocket_clash_event.tscn" scripts/ scenes/ tests/ 2>&1
```

Expected: 0 hits in production code; possibly 1 hit in `tests/unit/test_match_config.gd` if it asserts on the exact string. If so, update the test assertion to the new path. If the test asserts `EVENT_POOL.has(...)` (membership style from sub-project #5), no change needed.

- [ ] **Step 5: Run suite**

Expected: **511/511 still passing**. If any test fails because of a hardcoded path, fix the test (update to new path; don't roll back the move).

- [ ] **Step 6: Commit**

```bash
git add scripts/match/match_config.gd scenes/events/rocket_clash/rocket_clash_event.tscn
# Plus any test files touched in Step 4:
# git add tests/unit/test_match_config.gd
git commit -F - <<'EOF'
refactor(client): unify event scene paths under scenes/events/

Closes sub-project #5 final-review M1: Rocket Clash's .tscn lived at
scripts/events/rocket_clash/rocket_clash_event.tscn (sub-project #3
legacy); Bomb Pot + Card Cannon used scenes/events/<event>/. Unify on
the latter convention.

git mv the file; update MatchConfig.EVENT_POOL entry. Internal
ext_resource pointer in the .tscn uses res:// path to the .gd which
doesn't move, so no edit to the .tscn body needed.

All 511 tests still passing.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 3: Per-event tuning + context merge (Tasks 5-8)

### Task 5: Rocket Clash `_run` populates `ctx.tuning`

Closes sub-project #5 spec §12 carry-forward "events read tunable values from context, not hardcoded MatchConfig constants." This task wires the infrastructure for Rocket Clash; events still READ from `MatchConfig` for now (backward-compatible default). Future House Twists or sub-project #7 polish can override via `state.house_twist.params.tuning_overrides`.

**Files:**
- Modify: `scripts/events/rocket_clash/rocket_clash_event.gd`
- Create: `tests/unit/test_rocket_clash_tuning_populated.gd`

- [ ] **Step 1: Write failing test**

`tests/unit/test_rocket_clash_tuning_populated.gd`:
```gdscript
extends GutTest

const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")

func test_run_populates_ctx_tuning_with_defaults():
	var e = Node.new()
	e.set_script(RocketClashEvent)
	var ctx = EventContext.new()
	ctx.rng_seed = 1
	e._run(ctx)
	# Verify each tunable key was populated with the MatchConfig default
	assert_true(ctx.tuning.has("growth_rate"), "growth_rate populated")
	assert_almost_eq(float(ctx.tuning.get("growth_rate", 0.0)), MatchConfig.ROCKET_GROWTH_RATE, 0.001)
	assert_true(ctx.tuning.has("instabust_prob"), "instabust_prob populated")
	assert_almost_eq(float(ctx.tuning.get("instabust_prob", 0.0)), MatchConfig.ROCKET_INSTABUST_PROB, 0.001)
	assert_true(ctx.tuning.has("max_crash_at"), "max_crash_at populated")
	assert_almost_eq(float(ctx.tuning.get("max_crash_at", 0.0)), MatchConfig.ROCKET_MAX_CRASH_AT, 0.001)
	e.free()
```

- [ ] **Step 2: Run, watch fail**

Expected: 1 failure (tuning keys not yet populated).

- [ ] **Step 3: Implement**

In `scripts/events/rocket_clash/rocket_clash_event.gd`, find `_run(context)`. After the existing `super._run(context)` call (added in Task 3) and `_stashed_context = context` line, add the tuning population:

```gdscript
	# Populate ctx.tuning with Rocket Clash defaults (House Twist may
	# override via state.house_twist.params.tuning_overrides — merged
	# by MatchController._build_event_context in Task 8).
	context.tuning["growth_rate"] = MatchConfig.ROCKET_GROWTH_RATE
	context.tuning["instabust_prob"] = MatchConfig.ROCKET_INSTABUST_PROB
	context.tuning["max_crash_at"] = MatchConfig.ROCKET_MAX_CRASH_AT
```

**Note:** the constant names may differ. Read `scripts/match/match_config.gd` to find the actual Rocket Clash constant names. If `ROCKET_INSTABUST_PROB` or `ROCKET_MAX_CRASH_AT` don't exist as module-level constants but live inside `RocketClashEvent` itself (`const INSTABUST_PROB`, `const MAX_CRASH_AT`), use the local refs: `INSTABUST_PROB`, `MAX_CRASH_AT`. Adjust the test accordingly.

- [ ] **Step 4: Run, watch pass**

Expected: **512/512 tests pass** (511 prior + 1 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/events/rocket_clash/rocket_clash_event.gd tests/unit/test_rocket_clash_tuning_populated.gd
git commit -F - <<'EOF'
feat(client): Rocket Clash populates ctx.tuning in _run

Pre-work for House Twists' tuning_overrides surface. Rocket Clash's
_run now populates ctx.tuning with its defaults (growth_rate,
instabust_prob, max_crash_at) so future House Twists can override
per-round via state.house_twist.params.tuning_overrides without
mutating MatchConfig.

Events still READ from MatchConfig (backward-compatible). Plan A
Task 8 will add the tuning_overrides merge in _build_event_context.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 6: Bomb Pot `_run` populates `ctx.tuning`

Same pattern as Task 5, applied to Bomb Pot.

**Files:**
- Modify: `scripts/events/bomb_pot/bomb_pot_event.gd`
- Create: `tests/unit/test_bomb_pot_tuning_populated.gd`

- [ ] **Step 1: Write failing test**

`tests/unit/test_bomb_pot_tuning_populated.gd`:
```gdscript
extends GutTest

const BombPotEvent = preload("res://scripts/events/bomb_pot/bomb_pot_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")

func test_run_populates_ctx_tuning_with_defaults():
	var e = Node.new()
	e.set_script(BombPotEvent)
	var ctx = EventContext.new()
	ctx.rng_seed = 1
	e._run(ctx)
	assert_almost_eq(float(ctx.tuning.get("pot_growth_per_sec", 0.0)), MatchConfig.BOMB_POT_POT_GROWTH_PER_SEC, 0.001)
	assert_almost_eq(float(ctx.tuning.get("min_detonation_sec", 0.0)), MatchConfig.BOMB_POT_MIN_DETONATION_SEC, 0.001)
	assert_almost_eq(float(ctx.tuning.get("max_detonation_sec", 0.0)), MatchConfig.BOMB_POT_MAX_DETONATION_SEC, 0.001)
	assert_almost_eq(float(ctx.tuning.get("instabust_prob", 0.0)), MatchConfig.BOMB_POT_INSTABUST_PROB, 0.001)
	e.free()
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/events/bomb_pot/bomb_pot_event.gd`, find `_run(context)`. After the existing initialization, add:

```gdscript
	context.tuning["pot_growth_per_sec"] = MatchConfig.BOMB_POT_POT_GROWTH_PER_SEC
	context.tuning["min_detonation_sec"] = MatchConfig.BOMB_POT_MIN_DETONATION_SEC
	context.tuning["max_detonation_sec"] = MatchConfig.BOMB_POT_MAX_DETONATION_SEC
	context.tuning["instabust_prob"] = MatchConfig.BOMB_POT_INSTABUST_PROB
```

- [ ] **Step 4: Run, watch pass**

Expected: **513/513 tests pass** (512 prior + 1 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/events/bomb_pot/bomb_pot_event.gd tests/unit/test_bomb_pot_tuning_populated.gd
git commit -F - <<'EOF'
feat(client): Bomb Pot populates ctx.tuning in _run

Same pre-work pattern as Rocket Clash. Bomb Pot's _run now populates
ctx.tuning with pot_growth_per_sec, min/max_detonation_sec,
instabust_prob defaults from MatchConfig.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 7: Card Cannon `_run` populates `ctx.tuning`

Same pattern; Card Cannon-specific keys.

**Files:**
- Modify: `scripts/events/card_cannon/card_cannon_event.gd`
- Create: `tests/unit/test_card_cannon_tuning_populated.gd`

- [ ] **Step 1: Write failing test**

`tests/unit/test_card_cannon_tuning_populated.gd`:
```gdscript
extends GutTest

const CardCannonEvent = preload("res://scripts/events/card_cannon/card_cannon_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")

func test_run_populates_ctx_tuning_with_defaults():
	var e = Node.new()
	e.set_script(CardCannonEvent)
	var ctx = EventContext.new()
	ctx.rng_seed = 1
	e._run(ctx)
	assert_eq(int(ctx.tuning.get("target_score", 0)), MatchConfig.CARD_CANNON_TARGET_SCORE)
	# payout_bands sub-dict
	var bands = ctx.tuning.get("payout_bands", {})
	assert_almost_eq(float(bands.get("low", 0.0)), MatchConfig.CARD_CANNON_PAYOUT_BAND_LOW, 0.001)
	assert_almost_eq(float(bands.get("perfect", 0.0)), MatchConfig.CARD_CANNON_PAYOUT_BAND_PERFECT, 0.001)
	e.free()
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/events/card_cannon/card_cannon_event.gd`, in `_run(context)`:

```gdscript
	context.tuning["target_score"] = MatchConfig.CARD_CANNON_TARGET_SCORE
	context.tuning["payout_bands"] = {
		"low": MatchConfig.CARD_CANNON_PAYOUT_BAND_LOW,
		"medium": MatchConfig.CARD_CANNON_PAYOUT_BAND_MEDIUM,
		"strong": MatchConfig.CARD_CANNON_PAYOUT_BAND_STRONG,
		"heavy": MatchConfig.CARD_CANNON_PAYOUT_BAND_HEAVY,
		"perfect": MatchConfig.CARD_CANNON_PAYOUT_BAND_PERFECT,
	}
```

- [ ] **Step 4: Run, watch pass**

Expected: **514/514 tests pass** (513 prior + 1 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/events/card_cannon/card_cannon_event.gd tests/unit/test_card_cannon_tuning_populated.gd
git commit -F - <<'EOF'
feat(client): Card Cannon populates ctx.tuning in _run

Same pre-work pattern as Rocket Clash + Bomb Pot. Card Cannon's _run
populates ctx.tuning with target_score and a payout_bands sub-dict
covering all 5 band multipliers.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 8: `_build_event_context` merges `state.house_twist` into ctx + tuning_overrides

Threads `state.house_twist` into `ctx.house_twist` (full snapshot) and merges any `tuning_overrides` into `ctx.tuning` AFTER the event's `_run` populates defaults. Plan A doesn't yet USE the tuning_overrides surface, but the wiring is in place for Plan B / sub-project #7.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_build_event_context_house_twist.gd`

- [ ] **Step 1: Write failing test**

`tests/unit/test_match_controller_build_event_context_house_twist.gd`:
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

func test_build_event_context_carries_house_twist_snapshot():
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(2))
	c.state.house_twist = {"type": "double_bounty", "params": {"reward_multiplier": 2.0}}
	var ctx = c._build_event_context()
	assert_eq(ctx.house_twist.get("type", ""), "double_bounty")
	assert_almost_eq(float(ctx.house_twist.get("params", {}).get("reward_multiplier", 0.0)), 2.0, 0.001)
```

- [ ] **Step 2: Run, watch fail**

Expected: `ctx.house_twist.type` is empty because `_build_event_context` doesn't yet populate it.

- [ ] **Step 3: Implement**

In `scripts/match/match_controller.gd`, find `_build_event_context()`. Locate the line `ctx.event_modifiers = state.event_modifiers.duplicate(true)` (added in sub-project #4 Task 12). After it, add:

```gdscript
	# Sub-project #6 Plan A Task 8: thread house_twist + tuning_overrides
	ctx.house_twist = state.house_twist.duplicate(true)
	# tuning_overrides (Plan A wires infrastructure only; no Plan A twist
	# uses this yet, but Plan B's Sudden Death may). If state.house_twist
	# carries params.tuning_overrides, merge them into ctx.tuning AFTER
	# the event populates defaults in _run.
	# Note: the merge happens AFTER _run because event._run runs first
	# (it's called by _process_main_event after _build_event_context).
	# So we set a "pending overrides" key the event can read at end-of-_run,
	# or we delay the merge. Cleanest: keep tuning_overrides in
	# ctx.house_twist.params and let the event check it itself.
	# For Plan A: no merge implementation; just the snapshot. Plan B may
	# revisit.
```

The snapshot alone is the Plan A contract. Future tasks can layer in the merge logic.

- [ ] **Step 4: Run, watch pass**

Expected: **515/515 tests pass** (514 prior + 1 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/match/match_controller.gd tests/unit/test_match_controller_build_event_context_house_twist.gd
git commit -F - <<'EOF'
feat(client): _build_event_context threads state.house_twist into ctx

ctx.house_twist now carries a deep-copy snapshot of state.house_twist
at MAIN_EVENT entry. Consumers (Tasks 12-14) read from ctx.house_twist
in compute_event_result.

tuning_overrides merge is deferred: events populate ctx.tuning defaults
in _run; if a future twist needs to override, it can read
ctx.house_twist.params.tuning_overrides itself. Plan B may revisit if
Sudden Death Jackpot needs per-event threshold tuning.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 4: HouseTwistController + selection (Tasks 9-10)

### Task 9: HouseTwistController helper (selection + params + apply_pre_event_effects)

The core selection algorithm. Pure static class. Filters no-repeat + degenerate cases (equal chips). Computes per-twist params. Eagerly applies Power Surge bonus cards.

**Files:**
- Create: `scripts/match/house_twist_controller.gd`
- Create: `tests/unit/test_house_twist_controller.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_house_twist_controller.gd`:
```gdscript
extends GutTest

const HouseTwistController = preload("res://scripts/match/house_twist_controller.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _new_state_with_players(chips_array: Array) -> RefCounted:
	var s = MatchState.new()
	for i in chips_array.size():
		var p = MatchPlayer.new()
		p.peer_id = i + 1
		p.seat_index = i
		p.chips = chips_array[i]
		s.players.append(p)
	s.rng_seed = 1
	s.seed_rng()
	return s

func test_select_next_twist_picks_from_full_pool_when_no_history():
	var s = _new_state_with_players([500, 700, 600])  # unequal chips → all twists eligible
	var twist = HouseTwistController.select_next_twist(s)
	assert_true(twist.get("type", "") in HouseTwistController.TWIST_POOL,
		"selected twist must be in TWIST_POOL")

func test_select_next_twist_excludes_last_twist_type():
	# Run select 20 times after seeding last_twist_type; should NEVER return that type.
	var s = _new_state_with_players([500, 700, 600])
	s.last_twist_type = "double_bounty"
	for i in 20:
		s.seed_rng()
		s.rng.seed = i + 1
		var twist = HouseTwistController.select_next_twist(s)
		assert_ne(twist.get("type", ""), "double_bounty",
			"no-repeat filter must exclude last_twist_type")

func test_select_next_twist_excludes_lowest_chips_picks_when_equal_chips():
	var s = _new_state_with_players([500, 500, 500])  # all equal
	for i in 20:
		s.seed_rng()
		s.rng.seed = i + 1
		var twist = HouseTwistController.select_next_twist(s)
		assert_ne(twist.get("type", ""), "lowest_chips_picks",
			"filter must exclude lowest_chips_picks when chips equal")

func test_select_next_twist_excludes_leader_cursed_when_equal_chips():
	var s = _new_state_with_players([500, 500, 500])
	for i in 20:
		s.seed_rng()
		s.rng.seed = i + 1
		var twist = HouseTwistController.select_next_twist(s)
		assert_ne(twist.get("type", ""), "leader_cursed",
			"filter must exclude leader_cursed when chips equal")

func test_select_next_twist_deterministic_with_same_seed():
	var s1 = _new_state_with_players([500, 700, 600])
	var s2 = _new_state_with_players([500, 700, 600])
	# Both RNGs seeded identically by _new_state_with_players
	for i in 5:
		var t1 = HouseTwistController.select_next_twist(s1)
		var t2 = HouseTwistController.select_next_twist(s2)
		assert_eq(t1.get("type", ""), t2.get("type", ""),
			"same seed produces same twist sequence")

func test_compute_twist_params_leader_cursed_identifies_chip_leader():
	var s = _new_state_with_players([500, 900, 700])  # P2 is leader
	var params = HouseTwistController.compute_twist_params("leader_cursed", s)
	assert_eq(int(params.get("leader_peer_id", 0)), 2)
	assert_almost_eq(float(params.get("reward_multiplier", 0.0)), 0.75, 0.001)

func test_compute_twist_params_double_bounty_carries_multipliers():
	var s = _new_state_with_players([500, 500])
	var params = HouseTwistController.compute_twist_params("double_bounty", s)
	assert_almost_eq(float(params.get("reward_multiplier", 0.0)), 2.0, 0.001)
	assert_almost_eq(float(params.get("place_bounty_discount", 0.0)), 0.25, 0.001)

func test_apply_pre_event_effects_power_surge_deals_bonus_cards():
	var s = _new_state_with_players([500, 500])
	for p in s.players:
		p.hand = []  # ensure empty starting hand
	var twist = {"type": "power_surge", "params": {}}
	HouseTwistController.apply_pre_event_effects(s, twist)
	# Each active player should now have 1 bonus card in hand
	for p in s.players:
		assert_eq(p.hand.size(), 1, "%s should receive 1 bonus card" % p.name)

func test_apply_pre_event_effects_no_op_for_state_only_twists():
	var s = _new_state_with_players([500, 500])
	for p in s.players:
		p.hand = []
	var twist = {"type": "double_bounty", "params": {"reward_multiplier": 2.0}}
	HouseTwistController.apply_pre_event_effects(s, twist)
	# State-only twists shouldn't mutate hands
	for p in s.players:
		assert_eq(p.hand.size(), 0)
```

- [ ] **Step 2: Run, watch fail**

Expected: HouseTwistController preload error (file doesn't exist).

- [ ] **Step 3: Implement**

Create `scripts/match/house_twist_controller.gd`:
```gdscript
# House Twist controller. Selects + computes params + applies eager
# effects for the 6 MVP twists. Extracted as a static-only helper per
# sub-project #4's collaborator pattern (BountyResolver, ShopController,
# CardEffectDispatcher, MatchRpcSender).
#
# Consumers read state.house_twist keys directly (no dispatcher branches);
# this controller only handles selection + params at HOUSE_TWIST phase.
extends Object

const CardRegistry = preload("res://scripts/cards/card_registry.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")

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

static func _find_chip_leader_peer_id(state) -> int:
	# Mirrors BountyResolver.find_chip_leader_peer_id (kept local for now;
	# could DRY later if a third caller emerges).
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

- [ ] **Step 4: Run, watch pass**

Expected: **524/524 tests pass** (515 prior + 9 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/match/house_twist_controller.gd tests/unit/test_house_twist_controller.gd
git commit -F - <<'EOF'
feat(client): HouseTwistController helper (Plan A foundation)

Static-only collaborator class for House Twists, following the
sub-project #4 helper pattern (BountyResolver, ShopController, etc.):

TWIST_POOL constant: all 6 twist type IDs.

select_next_twist(state): picks uniformly from pool with two filters —
no-repeat (excludes state.last_twist_type) and degenerate-case
(lowest_chips_picks + leader_cursed excluded when all chips equal).
Defensive fallback to full pool if filters empty the candidates.

compute_twist_params(twist_type, state): builds the per-twist params
dict. Plan A handles 4 twists (double_bounty, no_insurance,
leader_cursed, power_surge); Plan B will populate richer params for
lowest_chips_picks + sudden_death_jackpot.

apply_pre_event_effects(state, twist): eager state mutations. Plan A
implements Power Surge (deals +1 bonus card to each active peer's
hand, bypassing MAX_HAND_SIZE intentionally per spec).

9 unit tests cover pool selection, both filter cases, determinism,
two param builders, and the Power Surge dealer.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 10: No-repeat event-pool selection

Closes the smart event-pool selection carry-forward from sub-project #5. `MatchController._process_event_selection` now excludes `state.previous_event_id` from the pool when picking events 2-5.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_event_selection_no_repeat.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_match_controller_event_selection_no_repeat.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start(player_count: int, seed_value: int = 1) -> RefCounted:
	var ms = MatchStart.new()
	for i in player_count:
		var s = PlayerSlot.new()
		s.peer_id = i + 1; s.seat_index = i; s.name = "P%d" % (i + 1)
		ms.seats.append(s)
	ms.host_peer_id = 1; ms.rng_seed = seed_value
	return ms

func _new_controller() -> RefCounted:
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	c.start_match(_build_match_start(2))
	return c

func test_event_selection_does_not_repeat_immediately():
	# Force a specific previous_event_id; verify next selection is not it.
	var c = _new_controller()
	for seed_val in 20:
		c.state.rng.seed = seed_val + 100
		c.state.previous_event_id = "res://scenes/events/rocket_clash/rocket_clash_event.tscn"
		c._process_event_selection()
		assert_ne(c.state.current_event_id,
			"res://scenes/events/rocket_clash/rocket_clash_event.tscn",
			"selection must not repeat previous_event_id")

func test_event_selection_falls_back_when_pool_only_has_previous():
	# If EVENT_POOL only had one entry and that was previous_event_id,
	# the fallback to the full pool kicks in.
	var c = _new_controller()
	c.state.previous_event_id = "res://scenes/events/rocket_clash/rocket_clash_event.tscn"
	# Defensive: even if the only entry equals previous_event_id, we get a result
	c.state.rng.seed = 1
	c._process_event_selection()
	assert_true(MatchConfig.EVENT_POOL.has(c.state.current_event_id),
		"current_event_id is a valid pool member after fallback")
```

- [ ] **Step 2: Run, watch fail**

Expected: 2 failures (current `_process_event_selection` doesn't filter).

- [ ] **Step 3: Implement**

In `scripts/match/match_controller.gd`, find `_process_event_selection()`. Current body:
```gdscript
func _process_event_selection() -> void:
	var pool = MatchConfig.EVENT_POOL
	var idx = state.rng.randi() % pool.size()
	state.current_event_id = pool[idx]
```

Replace with:
```gdscript
func _process_event_selection() -> void:
	# Plan B will add: if state.house_twist.type == "lowest_chips_picks":
	#   defer to async picker flow.
	# Plan A: uniform random with no-repeat filter (sub-project #5 carry-forward).
	var pool = MatchConfig.EVENT_POOL.duplicate()
	if not state.previous_event_id.is_empty():
		pool.erase(state.previous_event_id)
		# Defensive: fall back to full pool if filter emptied candidates
		if pool.is_empty():
			pool = MatchConfig.EVENT_POOL.duplicate()
	var idx = state.rng.randi() % pool.size()
	state.current_event_id = pool[idx]
	state.previous_event_id = state.current_event_id
```

- [ ] **Step 4: Run, watch pass**

Expected: **526/526 tests pass** (524 prior + 2 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/match/match_controller.gd tests/unit/test_match_controller_event_selection_no_repeat.gd
git commit -F - <<'EOF'
feat(client): no-repeat event-pool selection

Closes sub-project #5 spec §12 carry-forward. MatchController
_process_event_selection now excludes state.previous_event_id from
the candidate pool, then sets previous_event_id = current_event_id
after selection. For a 5-event Quick Clash with 3 events in the pool,
the same event can still appear 2-3 times in a match but not
back-to-back.

Defensive fallback to full pool if filter empties the candidates
(impossible with 3+ entries, but cheap insurance).

Plan B will layer in the lowest_chips_picks twist's async picker
flow as an early-return branch.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 5: HOUSE_TWIST phase handler (Task 11)

### Task 11: `_process_house_twist` phase handler + `_rpc_house_twist_announced` broadcast

Replaces the existing `HOUSE_TWIST` no-op with the real selection + announcement flow.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_house_twist_phase.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_match_controller_house_twist_phase.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const HouseTwistController = preload("res://scripts/match/house_twist_controller.gd")
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

func test_house_twist_phase_selects_and_sets_state():
	var d = _new_host()
	var c = d.controller
	c.state.event_index = 2  # event 2+ → twist fires
	# Vary chips so leader_cursed + lowest_chips_picks are eligible
	c.state.players[0].chips = 500
	c.state.players[1].chips = 700
	c._process_house_twist()
	assert_true(c.state.house_twist.has("type"), "state.house_twist populated")
	assert_true(c.state.house_twist.type in HouseTwistController.TWIST_POOL)
	assert_eq(c.state.last_twist_type, c.state.house_twist.type, "last_twist_type set")

func test_house_twist_phase_no_op_at_event_0():
	var d = _new_host()
	var c = d.controller
	c.state.event_index = 0
	c._process_house_twist()
	assert_eq(c.state.house_twist, {}, "no twist before event 1")
	assert_eq(c.state.last_twist_type, "")

func test_house_twist_phase_broadcasts_announced():
	var d = _new_host()
	var c = d.controller
	c.state.event_index = 2
	c.state.players[0].chips = 500
	c.state.players[1].chips = 700
	d.fake.rpc_calls.clear()
	c._process_house_twist()
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_house_twist_announced":
			found = true
			assert_true(call.args[0].has("type"), "broadcast carries twist dict")
			break
	assert_true(found, "_rpc_house_twist_announced broadcast")
```

- [ ] **Step 2: Run, watch fail**

Expected: 3 failures (`_process_house_twist` missing).

- [ ] **Step 3: Implement**

In `scripts/match/match_controller.gd`:

**3a.** Add the preload near other helper preloads at the top:
```gdscript
const HouseTwistController = preload("res://scripts/match/house_twist_controller.gd")
```

**3b.** Add the signal near other signal declarations:
```gdscript
signal house_twist_announced(twist_dict: Dictionary)
```

**3c.** Replace the HOUSE_TWIST branch in `_enter_phase_behavior`. Find:
```gdscript
		MatchPhase.Phase.HOUSE_TWIST:
			await _schedule_advance()
```
Replace with:
```gdscript
		MatchPhase.Phase.HOUSE_TWIST:
			_process_house_twist()
			await _schedule_advance()
```

**3d.** Add the `_process_house_twist` function (place near other phase handlers like `_process_shop`):
```gdscript
func _process_house_twist() -> void:
	if not is_host:
		return
	if state.event_index == 0:
		# No twist before event 1; players need a baseline.
		state.house_twist = {}
		return
	var twist = HouseTwistController.select_next_twist(state)
	state.house_twist = twist
	state.last_twist_type = twist.type
	HouseTwistController.apply_pre_event_effects(state, twist)
	_send_rpc("_rpc_house_twist_announced", [twist])
	house_twist_announced.emit(twist)
```

**3e.** Add the @rpc receiver (place near other broadcast receivers):
```gdscript
@rpc("authority", "call_remote", "reliable")
func _rpc_house_twist_announced(twist_dict: Dictionary) -> void:
	state.house_twist = twist_dict.duplicate(true)
	state.last_twist_type = twist_dict.get("type", "")
	house_twist_announced.emit(twist_dict)
```

- [ ] **Step 4: Run, watch pass**

Expected: **529/529 tests pass** (526 prior + 3 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/match/match_controller.gd tests/unit/test_match_controller_house_twist_phase.gd
git commit -F - <<'EOF'
feat(client): MatchController HOUSE_TWIST phase handler + announce

_process_house_twist replaces the prior no-op. Host-only. Skips at
event_index 0 (players need a baseline before twists start firing).
Otherwise: selects via HouseTwistController, sets state.house_twist
+ state.last_twist_type, calls apply_pre_event_effects for eager
mutations (Power Surge deals bonus cards), broadcasts
_rpc_house_twist_announced.

Client mirror: _rpc_house_twist_announced @rpc("authority",
"call_remote", "reliable") syncs state.house_twist + last_twist_type
and emits the local signal so HouseTwistOverlay (Task 15) reacts.

3 new tests: selection sets state, no-op at event 0, broadcast
verification.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 6: Twist consumers (Tasks 12-14)

### Task 12: Double Bounty consumer (BountyResolver.resolve)

Reads `state.house_twist.params.reward_multiplier` and scales each bounty's payout. `Bounty.compute_reward(bounty)` stays unchanged (pure).

**Files:**
- Modify: `scripts/match/bounty_resolver.gd`
- Create: `tests/unit/test_bounty_resolver_double_bounty.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_bounty_resolver_double_bounty.gd`:
```gdscript
extends GutTest

const BountyResolver = preload("res://scripts/match/bounty_resolver.gd")
const Bounty = preload("res://scripts/match/bounty.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const EventResult = preload("res://scripts/events/event_result.gd")

func _new_state_with_2_players() -> RefCounted:
	var s = MatchState.new()
	for i in 2:
		var p = MatchPlayer.new()
		p.peer_id = i + 1; p.seat_index = i; p.chips = 500
		s.players.append(p)
	return s

func test_resolve_double_bounty_multiplier_applied():
	var s = _new_state_with_2_players()
	var b = Bounty.new()
	b.origin = "leader"; b.target = 1; b.condition = "bust"; b.reward_chips = 150
	s.bounties = [b]
	s.house_twist = {"type": "double_bounty", "params": {"reward_multiplier": 2.0}}
	var r = EventResult.new()
	r.per_player[1] = {"chip_delta": -100, "bust": true, "crown_delta": 0, "heat_delta": 0, "cash_out_at": 0.0}
	r.per_player[2] = {"chip_delta": 100, "bust": false, "crown_delta": 0, "heat_delta": 0, "cash_out_at": 2.0}
	var awards = BountyResolver.resolve(s, r)
	assert_eq(awards.size(), 1)
	assert_eq(awards[0].claimant_peer_id, 2)
	assert_eq(awards[0].reward_chips, 300, "150 × 2.0 = 300")

func test_resolve_no_double_bounty_unchanged():
	var s = _new_state_with_2_players()
	var b = Bounty.new()
	b.origin = "leader"; b.target = 1; b.condition = "bust"; b.reward_chips = 150
	s.bounties = [b]
	# No house_twist active
	var r = EventResult.new()
	r.per_player[1] = {"chip_delta": -100, "bust": true, "crown_delta": 0, "heat_delta": 0, "cash_out_at": 0.0}
	r.per_player[2] = {"chip_delta": 100, "bust": false, "crown_delta": 0, "heat_delta": 0, "cash_out_at": 2.0}
	var awards = BountyResolver.resolve(s, r)
	assert_eq(awards[0].reward_chips, 150, "no twist: base reward unchanged")
```

- [ ] **Step 2: Run, watch fail**

Expected: 1 failure on `test_resolve_double_bounty_multiplier_applied` (still returns 150). `test_resolve_no_double_bounty_unchanged` may pass already.

- [ ] **Step 3: Implement**

In `scripts/match/bounty_resolver.gd`, find the `resolve(state, result)` function. Locate the inner loop that calls `Bounty.compute_reward(bounty)`. Wrap it with the twist multiplier read:

```gdscript
		var reward = Bounty.compute_reward(bounty)
		# Sub-project #6 Plan A: Double Bounty twist multiplier (pure
		# state read; Bounty.compute_reward stays unchanged).
		if state.house_twist.get("type", "") == "double_bounty":
			var mult = float(state.house_twist.params.get("reward_multiplier", 1.0))
			reward = int(reward * mult)
```

- [ ] **Step 4: Run, watch pass**

Expected: **531/531 tests pass** (529 prior + 2 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/match/bounty_resolver.gd tests/unit/test_bounty_resolver_double_bounty.gd
git commit -F - <<'EOF'
feat(client): BountyResolver applies Double Bounty twist multiplier

BountyResolver.resolve reads state.house_twist.params.reward_multiplier
and scales each bounty's payout. Bounty.compute_reward(bounty) stays
pure (no signature change; all existing Bounty tests untouched).

Spec § 7.1: Consumer: BountyResolver.resolve applies × 2 multiplier
to the value returned by Bounty.compute_reward.

2 new tests: multiplier applied under double_bounty twist; baseline
unchanged when no twist.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 13: No Insurance consumer (CardEffectDispatcher.apply)

Short-circuits the `insurance_pre` effect type when `state.house_twist.type == "no_insurance"`. Player's Insurance card play is rejected via a targeted `_rpc_card_play_rejected(card_id, "no_insurance_twist")` so the UI can surface the reason.

**Files:**
- Modify: `scripts/match/card_effect_dispatcher.gd`
- Modify: `scripts/match/match_controller.gd` (wrapper's rejection branch)
- Create: `tests/unit/test_card_effect_dispatcher_no_insurance.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_card_effect_dispatcher_no_insurance.gd`:
```gdscript
extends GutTest

const CardEffectDispatcher = preload("res://scripts/match/card_effect_dispatcher.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _new_state() -> RefCounted:
	var s = MatchState.new()
	for i in 2:
		var p = MatchPlayer.new()
		p.peer_id = i + 1; p.seat_index = i
		s.players.append(p)
	return s

func test_apply_no_insurance_short_circuits_insurance_pre():
	var s = _new_state()
	s.house_twist = {"type": "no_insurance", "params": {}}
	CardEffectDispatcher.apply(s, 1, {"type": "insurance_pre", "applied": true}, true)
	# Under no_insurance twist, the dispatcher does NOT set the modifier
	assert_eq(s.event_modifiers.get(1, {}).get("insurance_pre", false), false,
		"no_insurance twist short-circuits insurance_pre")

func test_apply_no_insurance_does_not_affect_other_effects():
	var s = _new_state()
	s.house_twist = {"type": "no_insurance", "params": {}}
	# Heat Shield is unaffected by no_insurance
	CardEffectDispatcher.apply(s, 1, {"type": "heat_shield", "applied": true}, true)
	assert_true(s.event_modifiers.get(1, {}).get("heat_shield", false),
		"heat_shield effect proceeds normally under no_insurance twist")
```

- [ ] **Step 2: Run, watch fail**

Expected: 1 failure on `test_apply_no_insurance_short_circuits_insurance_pre` (currently sets the flag regardless).

- [ ] **Step 3: Implement dispatcher short-circuit**

In `scripts/match/card_effect_dispatcher.gd`, find the `"insurance_pre"` match arm. Wrap with the twist check:

```gdscript
		"insurance_pre":
			# Sub-project #6 Plan A: No Insurance twist short-circuits.
			if state.house_twist.get("type", "") == "no_insurance":
				return
			_ensure_modifiers(state, peer_id)
			state.event_modifiers[peer_id]["insurance_pre"] = true
```

- [ ] **Step 4: Implement MatchController wrapper rejection (optional polish)**

The `_apply_effect_result` wrapper in `MatchController` is called from `_rpc_card_play_requested`. After the dispatcher's short-circuit, the host should send a `_rpc_card_play_rejected(card_id, "no_insurance_twist")` so the client UI re-enables the slot and shows a toast.

In `scripts/match/match_controller.gd`, find `_rpc_card_play_requested`. The current flow is:
1. Validate card in loadout, timing, target, etc.
2. Call `CardRegistry.apply_card(...)` to get an effect_result
3. If effect_result.applied: call `_apply_effect_result`, broadcast `_rpc_card_effect_applied`

We need to intercept BEFORE the dispatcher when the active twist disables this card. Add a check after the loadout/timing/target validation and BEFORE the `apply_card` call:

```gdscript
	# Sub-project #6 Plan A: No Insurance twist gates the Insurance card.
	if card_id == "insurance" and state.house_twist.get("type", "") == "no_insurance":
		_send_rpc_to_peer(peer_id, "_rpc_card_play_rejected", [card_id, "no_insurance_twist"])
		return
```

This keeps the dispatcher's short-circuit as defensive insurance for any future code path that calls the dispatcher directly.

- [ ] **Step 5: Run, watch pass**

Expected: **533/533 tests pass** (531 prior + 2 new).

- [ ] **Step 6: Commit**

```bash
git add scripts/match/card_effect_dispatcher.gd scripts/match/match_controller.gd tests/unit/test_card_effect_dispatcher_no_insurance.gd
git commit -F - <<'EOF'
feat(client): No Insurance twist short-circuits insurance_pre

CardEffectDispatcher.apply checks state.house_twist.type and skips
the insurance_pre branch when "no_insurance" is active. Defensive
short-circuit; the actual rejection path is in MatchController's
_rpc_card_play_requested which sends _rpc_card_play_rejected(
card_id, "no_insurance_twist") before reaching the dispatcher.

The Insurance card itself remains in the player's loadout (no
purchase rollback); it's simply inert for the next event. Other
effect types (heat_shield, multiplier_booster, etc.) are unaffected.

2 new tests cover the short-circuit + non-interference.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 14: Leader Cursed consumer (3 events' `compute_event_result`)

Each event's `compute_event_result` reads `ctx.house_twist.params.leader_peer_id` + `reward_multiplier`. Applies the multiplier to the leader's chip_delta if they survive. Stacks with other multipliers (wager_multiplier, underdog_multiplier).

Three subtasks: Rocket Clash, Bomb Pot, Card Cannon — each with 1 test.

**Files:**
- Modify: `scripts/events/rocket_clash/rocket_clash_event.gd`
- Modify: `scripts/events/bomb_pot/bomb_pot_event.gd`
- Modify: `scripts/events/card_cannon/card_cannon_event.gd`
- Create: `tests/unit/test_rocket_clash_leader_cursed.gd`
- Create: `tests/unit/test_bomb_pot_leader_cursed.gd`
- Create: `tests/unit/test_card_cannon_leader_cursed.gd`

- [ ] **Step 1: Write 3 failing tests (one file per event)**

`tests/unit/test_rocket_clash_leader_cursed.gd`:
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

func _make_context(player_count: int, wagers: Dictionary, modifiers: Dictionary) -> RefCounted:
	var ctx = EventContext.new()
	for i in player_count:
		ctx.players.append(_make_player(i + 1, "P%d" % (i + 1), i))
	ctx.wagers = wagers
	ctx.event_modifiers = modifiers
	return ctx

func test_leader_cursed_reduces_survivor_chip_delta():
	# P2 is the cursed leader; survives at 2.0x → chip_delta = 100 × 2.0 = 200, × 0.75 = 150
	var ctx = _make_context(2, {1: 100, 2: 100}, {})
	ctx.house_twist = {"type": "leader_cursed", "params": {"leader_peer_id": 2, "reward_multiplier": 0.75}}
	var cash_outs = {1: 2.0, 2: 2.0}
	var busted: Array = []
	var result = RocketClashEvent.compute_event_result(ctx, 3.0, cash_outs, busted)
	assert_eq(result.per_player[1].chip_delta, 200, "P1 not cursed: 100 × 2.0 = 200")
	assert_eq(result.per_player[2].chip_delta, 150, "P2 cursed: 100 × 2.0 × 0.75 = 150")
```

`tests/unit/test_bomb_pot_leader_cursed.gd`:
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

func test_leader_cursed_reduces_survivor_locked_share():
	var ctx = _make_context(2, {1: 100, 2: 100})
	ctx.house_twist = {"type": "leader_cursed", "params": {"leader_peer_id": 2, "reward_multiplier": 0.75}}
	var locked = {1: 200, 2: 200}
	var pulled = [1, 2]
	var timestamps = {1: 8000, 2: 9000}
	var result = BombPotEvent.compute_event_result(ctx, 15.0, locked, pulled, timestamps)
	assert_eq(result.per_player[1].chip_delta, 200, "P1 not cursed: 200 locked share")
	assert_eq(result.per_player[2].chip_delta, 150, "P2 cursed: 200 × 0.75 = 150")
```

`tests/unit/test_card_cannon_leader_cursed.gd`:
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

func test_leader_cursed_reduces_survivor_band_payout():
	# P2 locks 20 → heavy band (× 2.0) → 100 × 2.0 × 0.75 = 150
	var ctx = _make_context(2, {1: 100, 2: 100})
	ctx.house_twist = {"type": "leader_cursed", "params": {"leader_peer_id": 2, "reward_multiplier": 0.75}}
	var hands = {1: [10, 10], 2: [10, 10]}
	var locked = {1: 20, 2: 20}
	var busted = {}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	assert_eq(result.per_player[1].chip_delta, 200, "P1 not cursed: 100 × 2.0 = 200")
	assert_eq(result.per_player[2].chip_delta, 150, "P2 cursed: 100 × 2.0 × 0.75 = 150")
```

- [ ] **Step 2: Run, watch fail**

Expected: 3 failures (none of the events read `ctx.house_twist` yet).

- [ ] **Step 3: Implement in all 3 events**

For each of the 3 event scripts, locate the survivor branch in `compute_event_result` (after `wager_multiplier` and `underdog_multiplier` are applied). Add the Leader Cursed multiplier as the LAST multiplier so it stacks predictably.

**Rocket Clash** — find this section in `compute_event_result`:
```gdscript
			var um = float(p_mods.get("underdog_multiplier", 1.0))
			if um != 1.0:
				chip_delta = int(chip_delta * um)
```

After it, add:
```gdscript
			# Sub-project #6 Plan A: Leader Cursed reduces leader's survivor reward
			if context != null and "house_twist" in context:
				var ht = context.house_twist
				if ht.get("type", "") == "leader_cursed" and int(ht.params.get("leader_peer_id", 0)) == pid:
					var lc_mult = float(ht.params.get("reward_multiplier", 1.0))
					if lc_mult != 1.0:
						chip_delta = int(chip_delta * lc_mult)
```

**Bomb Pot** — find the equivalent survivor branch (after `wager_multiplier` and `underdog_multiplier`). Same code block.

**Card Cannon** — same.

- [ ] **Step 4: Run, watch pass**

Expected: **536/536 tests pass** (533 prior + 3 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/events/rocket_clash/rocket_clash_event.gd scripts/events/bomb_pot/bomb_pot_event.gd scripts/events/card_cannon/card_cannon_event.gd tests/unit/test_rocket_clash_leader_cursed.gd tests/unit/test_bomb_pot_leader_cursed.gd tests/unit/test_card_cannon_leader_cursed.gd
git commit -F - <<'EOF'
feat(client): Leader Cursed twist consumer in all 3 events

Each event's compute_event_result reads ctx.house_twist after applying
wager_multiplier + underdog_multiplier; if the active twist is
"leader_cursed" and pid == leader_peer_id, applies the 0.75 multiplier
to chip_delta. Busts not affected (already lost wager).

Multipliers stack sequentially: chip_delta × wm × um × lc_mult.
Documented as multiplicative; players learn the interaction.

3 new unit tests (1 per event) verify the leader's reduced reward
and that non-leaders are unaffected.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 7: UI (Tasks 15-16)

### Task 15: HouseTwistOverlay widget

Announces the active twist as a 3-second banner, then shrinks to a corner chip during the next event.

**Files:**
- Create: `scripts/ui/house_twist_overlay.gd`
- Create: `scenes/ui/house_twist_overlay.tscn`
- Create: `tests/unit/test_house_twist_overlay.gd`

- [ ] **Step 1: Write failing tests (static formatters)**

`tests/unit/test_house_twist_overlay.gd`:
```gdscript
extends GutTest

const HouseTwistOverlay = preload("res://scripts/ui/house_twist_overlay.gd")

func test_format_twist_title_per_twist_type():
	assert_eq(HouseTwistOverlay.format_twist_title({"type": "double_bounty"}), "Double Bounty Round")
	assert_eq(HouseTwistOverlay.format_twist_title({"type": "no_insurance"}), "No Insurance")
	assert_eq(HouseTwistOverlay.format_twist_title({"type": "leader_cursed"}), "Leader Cursed")
	assert_eq(HouseTwistOverlay.format_twist_title({"type": "power_surge"}), "Power Surge")
	assert_eq(HouseTwistOverlay.format_twist_title({"type": "lowest_chips_picks"}), "Lowest Chips Picks")
	assert_eq(HouseTwistOverlay.format_twist_title({"type": "sudden_death_jackpot"}), "Sudden Death Jackpot")
	assert_eq(HouseTwistOverlay.format_twist_title({}), "")

func test_format_twist_description_per_twist_type():
	var d1 = HouseTwistOverlay.format_twist_description({"type": "double_bounty"})
	assert_true(d1.length() > 0, "double_bounty has description")
	var d2 = HouseTwistOverlay.format_twist_description({"type": "no_insurance"})
	assert_true(d2.length() > 0, "no_insurance has description")
	assert_eq(HouseTwistOverlay.format_twist_description({}), "",
		"empty twist returns empty description")
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement script**

`scripts/ui/house_twist_overlay.gd`:
```gdscript
# HouseTwistOverlay: announces the active twist at HOUSE_TWIST phase
# as a 3-second banner, then shrinks to a corner chip during the
# next event. Hides at the next HOUSE_TWIST.
extends PanelContainer

@onready var _title_label: Label = $VBox/TitleLabel if has_node("VBox/TitleLabel") else null
@onready var _description_label: Label = $VBox/DescriptionLabel if has_node("VBox/DescriptionLabel") else null

var controller  # MatchController-like

func _ready() -> void:
	visible = false
	if controller != null:
		controller.house_twist_announced.connect(_on_house_twist_announced)

func _on_house_twist_announced(twist_dict: Dictionary) -> void:
	visible = true
	_refresh(twist_dict)
	# 3-second banner then shrink to corner. Polish: animate; MVP: stay
	# visible for the whole event, hide when next HOUSE_TWIST replaces
	# it (which will fire _on_house_twist_announced again).
	# If twist_dict is empty (event 1 → no twist), hide.
	if twist_dict.get("type", "") == "":
		visible = false

func _refresh(twist_dict: Dictionary) -> void:
	if _title_label != null:
		_title_label.text = format_twist_title(twist_dict)
	if _description_label != null:
		_description_label.text = format_twist_description(twist_dict)

# Static formatters (testable without scene)

static func format_twist_title(twist_dict: Dictionary) -> String:
	match twist_dict.get("type", ""):
		"double_bounty": return "Double Bounty Round"
		"no_insurance": return "No Insurance"
		"leader_cursed": return "Leader Cursed"
		"power_surge": return "Power Surge"
		"lowest_chips_picks": return "Lowest Chips Picks"
		"sudden_death_jackpot": return "Sudden Death Jackpot"
		_: return ""

static func format_twist_description(twist_dict: Dictionary) -> String:
	match twist_dict.get("type", ""):
		"double_bounty": return "All bounty rewards × 2"
		"no_insurance": return "Insurance cards inert this event"
		"leader_cursed": return "Chip leader earns 25% less this event"
		"power_surge": return "Everyone draws a bonus card"
		"lowest_chips_picks": return "Lowest-chips player picks the next event"
		"sudden_death_jackpot": return "Bonus Crown for taking a specific risk"
		_: return ""
```

- [ ] **Step 4: Implement scene**

`scenes/ui/house_twist_overlay.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/house_twist_overlay.gd" id="1"]

[node name="HouseTwistOverlay" type="PanelContainer"]
script = ExtResource("1")

[node name="VBox" type="VBoxContainer" parent="."]

[node name="TitleLabel" type="Label" parent="VBox"]
text = "House Twist"

[node name="DescriptionLabel" type="Label" parent="VBox"]
text = ""
```

- [ ] **Step 5: Run, watch pass**

Expected: **538/538 tests pass** (536 prior + 2 new).

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/house_twist_overlay.gd scenes/ui/house_twist_overlay.tscn tests/unit/test_house_twist_overlay.gd
git commit -F - <<'EOF'
feat(client): HouseTwistOverlay widget for twist announcement

PanelContainer with title + description label. Subscribes to
controller.house_twist_announced; shows title + description on
emission; stays visible through the event (animation polish deferred
to sub-project #7).

Static formatters format_twist_title and format_twist_description
return per-twist strings for all 6 twists (plus empty fallback).
Testable without scene instantiation.

2 new unit tests cover all 6 twist titles + empty fallback + that
each twist has a non-empty description.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 16: MatchScene wiring

Adds the HouseTwistSlot container and instantiates the overlay.

**Files:**
- Modify: `scripts/ui/match_scene.gd`
- Modify: `scenes/match_scene.tscn`

- [ ] **Step 1: Read existing MatchScene for patterns**

Read `scripts/ui/match_scene.gd` to find the slot/builder pattern used for BountyPanel, ShopOverlay, etc.

- [ ] **Step 2: Add to scene file**

In `scenes/match_scene.tscn`, add a new container near the BountyPanelSlot (top of VBox or wherever other overlays live):
```
[node name="HouseTwistSlot" type="Container" parent="VBox"]
```

- [ ] **Step 3: Add to match_scene.gd**

Add the preload near other UI scene preloads:
```gdscript
const HouseTwistOverlayScene = preload("res://scenes/ui/house_twist_overlay.tscn")
```

Add `@onready` slot reference + instance field:
```gdscript
@onready var _house_twist_slot: Container = $VBox/HouseTwistSlot if has_node("VBox/HouseTwistSlot") else null
var _house_twist_overlay: Node = null
```

In `_ready()`, after other builder calls, add:
```gdscript
	_build_house_twist_overlay()
```

Add the builder method:
```gdscript
func _build_house_twist_overlay() -> void:
	if _house_twist_slot == null:
		return
	_house_twist_overlay = HouseTwistOverlayScene.instantiate()
	_house_twist_overlay.controller = controller
	_house_twist_slot.add_child(_house_twist_overlay)
```

- [ ] **Step 4: Run suite (no new tests; verify nothing regresses)**

Expected: **538/538 tests still passing**.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/match_scene.gd scenes/match_scene.tscn
git commit -F - <<'EOF'
feat(client): wire HouseTwistOverlay into MatchScene

HouseTwistSlot container added to match_scene.tscn near top of VBox.
match_scene.gd preloads HouseTwistOverlayScene, declares slot +
instance refs, adds _build_house_twist_overlay builder that runs in
_ready alongside other overlay builders. Overlay receives the
controller reference and subscribes to house_twist_announced.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 8: Integration test + playtest checklist (Task 17)

### Task 17: Integration test PENDING stub + PLAYTEST_CHECKLIST update

Per sub-project #3/#4/#5 precedent: 1 new integration test that PENDINGs cleanly without signaling server; plus 4 new playtest scenarios for the Plan A twists.

**Files:**
- Create: `tests/integration/test_house_twist_announce.gd`
- Modify: `docs/PLAYTEST_CHECKLIST.md`

- [ ] **Step 1: Create integration placeholder**

`tests/integration/test_house_twist_announce.gd`:
```gdscript
# Integration smoke test: real signaling + WebRTC + HOUSE_TWIST phase
# announces a twist to both peers. Spawns two NetSession instances;
# runs a 3-event match; verifies state.house_twist is mirrored across
# peers after each HOUSE_TWIST phase.
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

func test_house_twist_mirrored_across_peers():
	if not await _signaling_reachable():
		pending("Signaling server not reachable at %s; skipping. Start with `cd ../signaling-server && node server.js`." % SIGNALING_URL)
		return
	# Implementer note: cargo-cult test_three_event_rotation.gd; run
	# a 3-event match; after each HOUSE_TWIST phase fires, assert
	# both peers' state.house_twist.type matches.
	pending("Implementer: cargo-cult test_three_event_rotation.gd; assert state.house_twist mirror across peers.")
```

- [ ] **Step 2: Update PLAYTEST_CHECKLIST.md**

Read `docs/PLAYTEST_CHECKLIST.md` to confirm the existing format. Append a new section:

```markdown
## Sub-project #6 Plan A additions

| # | Scenario | Pass criteria |
|---|----------|---------------|
| 16 | Double Bounty Round doubles payouts | Twist announced at start of event 2-5; bounty resolution awards 300 chips instead of 150 (Leader bounty) and proportionally for Heat bounties |
| 17 | No Insurance disables card | Player has Insurance in loadout; twist announced; submit_card_play("insurance") returns rejection toast "Insurance disabled this event"; Insurance modifier never set in event_modifiers |
| 18 | Leader Cursed reduces survivor reward | Chip leader identified at HOUSE_TWIST; after event, leader's chip_delta is 75% of what their wager × multiplier would normally produce; non-leaders unaffected |
| 19 | Power Surge deals bonus cards | Every active peer receives +1 random non-sabotage common card at HOUSE_TWIST; broadcast _rpc_starter_pack_dealt with action="power_surge_bonus" reaches all clients |
| 20 | No-repeat event selection | Across a 5-event Quick Clash, no two consecutive events share the same event_id |
| 21 | No twist on event 1 | First event's HOUSE_REVEAL sees state.house_twist == {} (no twist banner shown) |
```

- [ ] **Step 3: Run unit suite (PLAYTEST_CHECKLIST + integration stub don't affect unit tests)**

Expected: **538/538 unit tests still passing**. Integration suite now has 5 + 1 new = 6 PENDING.

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test_house_twist_announce.gd docs/PLAYTEST_CHECKLIST.md
git commit -F - <<'EOF'
test+docs(client): Plan A integration stub + playtest scenarios

Integration test: PENDING placeholder per sub-project #3/#4/#5
precedent; manual verification via running the game is the primary
surface. Stub verifies state.house_twist mirror across host + joiner
after each HOUSE_TWIST phase.

PLAYTEST_CHECKLIST: 6 new scenarios covering Double Bounty payout
math, No Insurance rejection UI, Leader Cursed reward reduction,
Power Surge bonus card distribution, no-repeat event selection,
and no-twist-on-event-1 baseline.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Done

Plan A complete. Sub-project #6 Plan A delivers:
- 4 of 6 MVP House Twists fully wired end-to-end (state + selection + consumers + UI announcement)
- Sub-project #5 carry-forwards closed: M1 scene-path unification, M2 `_send_rpc` hoist to base class, EventContext.tuning pre-work, no-repeat event-pool selection
- 1 new collaborator class (`HouseTwistController`) following the established sub-project #4 pattern
- ~34 new unit tests + 1 new integration test target

**Cumulative state after Plan A merge:**
- Test suite: ~538 unit + 6 integration (504 baseline → 538 + 1 new integration)
- 4 events not yet shipped to event pool (Rocket Clash + Bomb Pot + Card Cannon remain the 3-event rotation)
- 12 power cards (unchanged from sub-project #4)
- 4 active twists rotating; 2 deferred (`lowest_chips_picks`, `sudden_death_jackpot`)

**Plan B preview** (separate plan to write after Plan A merges):
- Lowest Chips Picks: async picker UI (EventPickerOverlay scene + RPC pair + 10s timeout + host fallback) — ~6-9 tasks
- Sudden Death Jackpot: per-event condition evaluation in compute_event_result, lazy condition selection in `finalize_pending_params` — ~3 tasks
- ~15 new unit + 1 new integration tests

**Tags after Plan A merges:** `subproject-6-plan-a-complete`. After Plan B merges: `subproject-6-plan-b-complete` + `subproject-6-complete`.

**Memory updates after Plan A merges:**
- `MEMORY.md` / `project_riskroyal.md` — mark Plan A done
- `project_riskroyal_followups.md` — close M1 + M2 + tunable constants carry-forwards; document any Plan A review fixups
