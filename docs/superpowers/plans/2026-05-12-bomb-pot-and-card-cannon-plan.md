# Bomb Pot + Card Cannon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship two new events (Bomb Pot and Card Cannon) extending sub-project #2's `EventNode` contract so the match rotation has variety beyond Rocket Clash.

**Architecture:** Both events follow Rocket Clash's pattern (sub-project #3): a Godot `Node`-extending script with static math helpers (`compute_*`) + instance `_run`/`_process` + `@rpc` send/receiver pairs + a `compute_event_result` static that builds an `EventResult`. Each event ships with its own scene. Both events read `EventContext.event_modifiers` for the 10 universal Plan A/B cards; three event-specific cards (Late Cash, Cash-Out Jammer, Emergency Eject) silently no-op per the compatibility matrix in the spec.

**Tech Stack:** Godot 4.6, GDScript with tabs (no `class_name`), GUT testing framework, host-authoritative RPC pattern with `@rpc("any_peer", "call_local", "reliable")` for requests and `@rpc("authority", "call_remote", "reliable")` for broadcasts. `FakeMultiplayerNode` injection for RPC testing.

**Baseline (post sub-project #4 merge):** 453 unit + 4 integration tests passing. **Target after Task 15:** 504 unit + 5 integration (+51 new unit + 1 new integration).

---

## File Structure

**New files:**
- `scripts/events/bomb_pot/bomb_pot_event.gd` — Bomb Pot event script (extends `event_node.gd`)
- `scenes/events/bomb_pot/bomb_pot_event.tscn` — Bomb Pot scene
- `scripts/events/card_cannon/card_cannon_event.gd` — Card Cannon event script
- `scenes/events/card_cannon/card_cannon_event.tscn` — Card Cannon scene

**New test files (7):**
- `tests/unit/test_match_config_event_constants.gd` — 10 constant tests (4 Bomb Pot + 6 Card Cannon)
- `tests/unit/test_bomb_pot_event.gd` — 10 event tests (Tier 1 pure-math)
- `tests/unit/test_card_cannon_event.gd` — 12 event tests
- `tests/unit/test_match_controller_bomb_pot_pull_out.gd` — 3 controller integration tests
- `tests/unit/test_match_controller_card_cannon_draw.gd` — 4 controller integration tests
- `tests/integration/test_three_event_rotation.gd` — 1 integration test (PENDING placeholder)

**Modified files:**
- `scripts/match/match_config.gd` — 10 new constants (4 Bomb Pot + 6 Card Cannon) + 2 EVENT_POOL entries
- `docs/PLAYTEST_CHECKLIST.md` — append sub-project #5 scenarios

---

## Phase 1: Constants (Task 1)

### Task 1: MatchConfig constants for both events

Adds 10 new constants to `MatchConfig` and 10 corresponding tests. Append-only; doesn't touch EVENT_POOL yet (Task 16).

**Files:**
- Modify: `scripts/match/match_config.gd`
- Create: `tests/unit/test_match_config_event_constants.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_config_event_constants.gd`:
```gdscript
extends GutTest

const MatchConfig = preload("res://scripts/match/match_config.gd")

# Bomb Pot constants

func test_bomb_pot_pot_growth_per_sec():
	assert_almost_eq(MatchConfig.BOMB_POT_POT_GROWTH_PER_SEC, 50.0, 0.001)

func test_bomb_pot_min_detonation_sec():
	assert_almost_eq(MatchConfig.BOMB_POT_MIN_DETONATION_SEC, 5.0, 0.001)

func test_bomb_pot_max_detonation_sec():
	assert_almost_eq(MatchConfig.BOMB_POT_MAX_DETONATION_SEC, 25.0, 0.001)

func test_bomb_pot_instabust_prob():
	assert_almost_eq(MatchConfig.BOMB_POT_INSTABUST_PROB, 0.05, 0.001)

# Card Cannon constants

func test_card_cannon_target_score():
	assert_eq(MatchConfig.CARD_CANNON_TARGET_SCORE, 21)

func test_card_cannon_payout_band_low():
	assert_almost_eq(MatchConfig.CARD_CANNON_PAYOUT_BAND_LOW, 0.5, 0.001)

func test_card_cannon_payout_band_medium():
	assert_almost_eq(MatchConfig.CARD_CANNON_PAYOUT_BAND_MEDIUM, 1.0, 0.001)

func test_card_cannon_payout_band_strong():
	assert_almost_eq(MatchConfig.CARD_CANNON_PAYOUT_BAND_STRONG, 1.5, 0.001)

func test_card_cannon_payout_band_heavy():
	assert_almost_eq(MatchConfig.CARD_CANNON_PAYOUT_BAND_HEAVY, 2.0, 0.001)

func test_card_cannon_payout_band_perfect():
	assert_almost_eq(MatchConfig.CARD_CANNON_PAYOUT_BAND_PERFECT, 3.0, 0.001)
```

- [ ] **Step 2: Run, watch fail**

```
godot --headless --path c:/Users/whann/Desktop/Games/RocketMan -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
```
Expected: 10 failures (missing constants).

- [ ] **Step 3: Implement**

In `scripts/match/match_config.gd`, append before the existing `static func` block (constants-first convention from Plan A Task 1 review):

```gdscript
# Sub-project #5 (Bomb Pot + Card Cannon)
# Bomb Pot
const BOMB_POT_POT_GROWTH_PER_SEC: float = 50.0   # chips/sec total distributed
const BOMB_POT_MIN_DETONATION_SEC: float = 5.0
const BOMB_POT_MAX_DETONATION_SEC: float = 25.0
const BOMB_POT_INSTABUST_PROB: float = 0.05       # 5% chance bomb fires at MIN
# Card Cannon
const CARD_CANNON_TARGET_SCORE: int = 21
const CARD_CANNON_PAYOUT_BAND_LOW: float = 0.5    # scores 1-10
const CARD_CANNON_PAYOUT_BAND_MEDIUM: float = 1.0 # scores 11-15
const CARD_CANNON_PAYOUT_BAND_STRONG: float = 1.5 # scores 16-18
const CARD_CANNON_PAYOUT_BAND_HEAVY: float = 2.0  # scores 19-20
const CARD_CANNON_PAYOUT_BAND_PERFECT: float = 3.0 # score 21
```

- [ ] **Step 4: Run, watch pass**

Expected: **463/463 tests pass** (453 prior + 10 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/match/match_config.gd tests/unit/test_match_config_event_constants.gd
git commit -F - <<'EOF'
feat(client): sub-project #5 constants for Bomb Pot + Card Cannon

MatchConfig: 4 Bomb Pot constants (pot growth rate, min/max detonation,
instabust prob) + 6 Card Cannon constants (target score 21 + 5 payout
band multipliers).

10 unit tests in test_match_config_event_constants.gd verify each
constant's value matches the spec.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 2: Bomb Pot (Tasks 2-7)

### Task 2: Bomb Pot event script skeleton + `compute_bomb_at`

Creates the script with all field declarations, `extends`, `get_event_id`, `_run` skeleton, and the static `compute_bomb_at`. Lifecycle behavior (RPCs, `_process`, `_finish`) lands in subsequent tasks.

**Files:**
- Create: `scripts/events/bomb_pot/bomb_pot_event.gd`
- Create: `tests/unit/test_bomb_pot_event.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_bomb_pot_event.gd`:
```gdscript
extends GutTest

const BombPotEvent = preload("res://scripts/events/bomb_pot/bomb_pot_event.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")

func _new_rng(seed_value: int) -> RandomNumberGenerator:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

func test_compute_bomb_at_within_window():
	# 1000 samples; every result must be in [MIN, MAX].
	var rng = _new_rng(1)
	for i in 1000:
		var t = BombPotEvent.compute_bomb_at(rng)
		assert_true(t >= MatchConfig.BOMB_POT_MIN_DETONATION_SEC, "got %f" % t)
		assert_true(t <= MatchConfig.BOMB_POT_MAX_DETONATION_SEC, "got %f" % t)

func test_compute_bomb_at_deterministic_with_same_seed():
	var rng1 = _new_rng(42)
	var rng2 = _new_rng(42)
	for i in 10:
		assert_almost_eq(BombPotEvent.compute_bomb_at(rng1), BombPotEvent.compute_bomb_at(rng2), 0.001)

func test_compute_bomb_at_instabust_probability():
	# ~5% should equal MIN_DETONATION (5.0). Allow 3-7% range.
	var rng = _new_rng(99)
	var instabust_count = 0
	var samples = 10000
	for i in samples:
		var t = BombPotEvent.compute_bomb_at(rng)
		if abs(t - MatchConfig.BOMB_POT_MIN_DETONATION_SEC) < 0.001:
			instabust_count += 1
	var ratio = float(instabust_count) / float(samples)
	assert_true(ratio >= 0.03 and ratio <= 0.07, "instabust ratio out of range: %f" % ratio)
```

- [ ] **Step 2: Run, watch fail**

Expected: `BombPotEvent` preload error — file doesn't exist.

- [ ] **Step 3: Implement**

Create `scripts/events/bomb_pot/bomb_pot_event.gd`:
```gdscript
# Bomb Pot event. Ante-locked timed survival. Hidden bomb timer (5-25s
# window with 5% instabust at 5s). Shared Pot Drain: per-tick share rate
# scales with active grabber count. Single player action: pull out to
# lock current share.
#
# Extends EventNode (sub-project #2 contract). compute_bomb_at +
# compute_event_result are testable without scene instantiation.
extends "res://scripts/events/event_node.gd"

const MatchConfig = preload("res://scripts/match/match_config.gd")
const EventResult = preload("res://scripts/events/event_result.gd")

# Per-round state (host populates; clients mirror per-RPC).
var _bomb_at_sec: float = 0.0             # hidden; set in _run via compute_bomb_at
var _start_time_ms: int = 0
var _pulled_out_peers: Array = []         # peer_ids who pulled out
var _pull_out_timestamps: Dictionary = {} # peer_id -> int elapsed_ms at pull-out
var _locked_shares: Dictionary = {}       # peer_id -> int chips locked at pull-out
var _shares_accumulator: Dictionary = {}  # peer_id -> float fractional chips (host-only)
var _active_peers: Array = []             # peer_ids active at launch
var _is_host: bool = false
var _finished: bool = false
var _stashed_context = null

# RPC routing (mirror of MatchController + RocketClashEvent pattern).
var _multiplayer_node = null

# Test seams
var _force_bomb_at_override: float = -1.0      # negative = use RNG
var _pot_growth_rate_override: float = -1.0    # negative = use MatchConfig

# Scene-tree refs (resolved in _ready; null in detached tests).
@onready var _pot_label: Label = $VBox/PotLabel if has_node("VBox/PotLabel") else null
@onready var _ticker_label: Label = $VBox/TickerLabel if has_node("VBox/TickerLabel") else null
@onready var _pull_out_button: Button = $VBox/PullOutButton if has_node("VBox/PullOutButton") else null

func get_event_id() -> String:
	return "bomb_pot"

func _ready() -> void:
	if _pull_out_button != null:
		_pull_out_button.pressed.connect(_on_pull_out_button_pressed)

func _on_pull_out_button_pressed() -> void:
	if _start_time_ms == 0 or _finished:
		return
	submit_pull_out()

func submit_pull_out() -> void:
	var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
	_send_rpc("_rpc_pull_out_requested", [my_peer_id])

# Override EventNode._run
func _run(context) -> void:
	_stashed_context = context
	_is_host = context.is_host
	_active_peers = []
	for p in context.players:
		if p.is_active_this_event:
			_active_peers.append(p.peer_id)
	if _is_host:
		if _force_bomb_at_override >= 0.0:
			_bomb_at_sec = _force_bomb_at_override
		else:
			# EventContext exposes rng_seed (not rng); derive a fresh RNG per
			# event from the seed for determinism. Same pattern as
			# RocketClashEvent._on_rocket_launched_local.
			var rng = RandomNumberGenerator.new()
			rng.seed = context.rng_seed
			_bomb_at_sec = compute_bomb_at(rng)
		_start_time_ms = Time.get_ticks_msec()
		_send_rpc("_rpc_bomb_pot_started", [_start_time_ms])
	set_process(true)

# Host broadcast → clients sync start time
@rpc("authority", "call_remote", "reliable")
func _rpc_bomb_pot_started(start_time_ms: int) -> void:
	_start_time_ms = start_time_ms

func _send_rpc(method_name: String, args: Array = []) -> void:
	if _multiplayer_node == null:
		return
	match args.size():
		0: _multiplayer_node.rpc(method_name)
		1: _multiplayer_node.rpc(method_name, args[0])
		2: _multiplayer_node.rpc(method_name, args[0], args[1])
		3: _multiplayer_node.rpc(method_name, args[0], args[1], args[2])
		_:
			push_error("BombPotEvent._send_rpc: unsupported arity %d" % args.size())

func _send_rpc_to_peer(peer_id: int, method_name: String, args: Array = []) -> void:
	if _multiplayer_node == null:
		return
	match args.size():
		0: _multiplayer_node.rpc_id(peer_id, method_name)
		1: _multiplayer_node.rpc_id(peer_id, method_name, args[0])
		2: _multiplayer_node.rpc_id(peer_id, method_name, args[0], args[1])
		_:
			push_error("BombPotEvent._send_rpc_to_peer: unsupported arity %d" % args.size())

# ----- Static helpers (testable without scene) -----

# Returns a bomb detonation time in seconds, in [MIN, MAX]. ~5% chance
# of "instabust" at exactly MIN_DETONATION_SEC; otherwise uniform over
# the full window.
static func compute_bomb_at(rng: RandomNumberGenerator) -> float:
	var instabust_roll = rng.randf()
	if instabust_roll < MatchConfig.BOMB_POT_INSTABUST_PROB:
		return MatchConfig.BOMB_POT_MIN_DETONATION_SEC
	var r = rng.randf()
	var span = MatchConfig.BOMB_POT_MAX_DETONATION_SEC - MatchConfig.BOMB_POT_MIN_DETONATION_SEC
	var t = MatchConfig.BOMB_POT_MIN_DETONATION_SEC + span * r
	return clamp(t, MatchConfig.BOMB_POT_MIN_DETONATION_SEC, MatchConfig.BOMB_POT_MAX_DETONATION_SEC)
```

- [ ] **Step 4: Run, watch pass**

Expected: **466/466 tests pass** (463 prior + 3 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/events/bomb_pot/bomb_pot_event.gd tests/unit/test_bomb_pot_event.gd
git commit -F - <<'EOF'
feat(client): Bomb Pot event skeleton + compute_bomb_at static

BombPotEvent extends event_node.gd. Fields for bomb time, start ms,
pulled-out peers + timestamps + locked shares + shares accumulator,
active peers, finished flag, stashed context. Test seams:
_force_bomb_at_override, _pot_growth_rate_override.

compute_bomb_at(rng) static: 5% instabust at MIN_DETONATION (5.0s),
otherwise uniform over [5.0, 25.0]. Determinism via seeded RNG.

get_event_id returns "bomb_pot". _run captures active peers, rolls
bomb_at_sec on host, broadcasts start_time_ms. Pull-out RPCs +
_process land in subsequent tasks.

3 unit tests cover within-window distribution, determinism, instabust
probability ratio.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 3: Bomb Pot pull-out RPC pipeline

Adds `_rpc_pull_out_requested` host handler + `_rpc_pull_out_confirmed` client mirror + tests.

**Files:**
- Modify: `scripts/events/bomb_pot/bomb_pot_event.gd`
- Modify: `tests/unit/test_bomb_pot_event.gd`

- [ ] **Step 1: Write failing tests**

Append to `tests/unit/test_bomb_pot_event.gd`:
```gdscript
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func _new_host_event_with_fake() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var e = Node.new()
	e.set_script(BombPotEvent)
	e._is_host = true
	e._multiplayer_node = fake
	e._start_time_ms = Time.get_ticks_msec()
	e._active_peers = [1, 2]
	e._shares_accumulator = {1: 120.0, 2: 80.0}
	return {"event": e, "fake": fake}

func test_pull_out_locks_share_and_records_timestamp():
	var d = _new_host_event_with_fake()
	var e = d.event
	e._rpc_pull_out_requested(1)
	assert_eq(e._locked_shares.get(1, 0), 120, "P1 locked accumulator at int 120")
	assert_true(1 in e._pulled_out_peers)
	assert_true(e._pull_out_timestamps.has(1), "host recorded timestamp")
	e.free()

func test_pull_out_broadcasts_confirmed():
	var d = _new_host_event_with_fake()
	var e = d.event
	e._rpc_pull_out_requested(1)
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_pull_out_confirmed":
			found = true
			assert_eq(call.args[0], 1, "peer_id")
			assert_eq(call.args[1], 120, "locked_share")
			break
	assert_true(found, "_rpc_pull_out_confirmed broadcast")
	e.free()

func test_pull_out_double_tap_silently_dropped():
	var d = _new_host_event_with_fake()
	var e = d.event
	e._rpc_pull_out_requested(1)
	d.fake.rpc_calls.clear()
	e._rpc_pull_out_requested(1)
	var ack_count = 0
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_pull_out_confirmed":
			ack_count += 1
	assert_eq(ack_count, 0, "second pull-out silently dropped")
	e.free()

func test_pull_out_after_finished_rejected():
	var d = _new_host_event_with_fake()
	var e = d.event
	e._finished = true
	e._rpc_pull_out_requested(1)
	assert_false(e._locked_shares.has(1))
	e.free()
```

- [ ] **Step 2: Run, watch fail**

Expected: 4 new failures — `_rpc_pull_out_requested` missing.

- [ ] **Step 3: Implement**

In `scripts/events/bomb_pot/bomb_pot_event.gd`, add after `_send_rpc_to_peer`:

```gdscript
@rpc("any_peer", "call_local", "reliable")
func _rpc_pull_out_requested(peer_id: int) -> void:
	if not _is_host:
		return
	if _finished or _start_time_ms == 0:
		return
	if peer_id in _pulled_out_peers:
		return  # silent double-tap drop
	if not (peer_id in _active_peers):
		return  # peer not in this event
	var elapsed_ms = Time.get_ticks_msec() - _start_time_ms
	_locked_shares[peer_id] = int(_shares_accumulator.get(peer_id, 0.0))
	_pull_out_timestamps[peer_id] = elapsed_ms
	_pulled_out_peers.append(peer_id)
	_send_rpc("_rpc_pull_out_confirmed", [peer_id, _locked_shares[peer_id], elapsed_ms])

@rpc("authority", "call_remote", "reliable")
func _rpc_pull_out_confirmed(peer_id: int, locked_share: int, pull_out_time_ms: int) -> void:
	if not (peer_id in _pulled_out_peers):
		_pulled_out_peers.append(peer_id)
	_locked_shares[peer_id] = locked_share
	_pull_out_timestamps[peer_id] = pull_out_time_ms
```

- [ ] **Step 4: Run, watch pass**

Expected: **470/470 tests pass** (466 prior + 4 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/events/bomb_pot/bomb_pot_event.gd tests/unit/test_bomb_pot_event.gd
git commit -F - <<'EOF'
feat(client): Bomb Pot pull-out RPC pipeline

_rpc_pull_out_requested @rpc("any_peer", "call_local", "reliable")
host receiver: validates is_host + not finished + not double-tap +
peer active; computes elapsed_ms; locks share from accumulator;
records timestamp; broadcasts _rpc_pull_out_confirmed.

_rpc_pull_out_confirmed @rpc("authority", "call_remote", "reliable")
client mirror: appends to _pulled_out_peers; sets locked_shares +
timestamp.

4 new tests: happy-path lock + timestamp, broadcast verification,
double-tap silent drop, finished-state reject.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 4: Bomb Pot per-frame share accumulator + bomb timer

Implements `_process` host-side per-tick share distribution + bomb-time check + early-finish-when-all-pulled. Adds a testable static helper `compute_per_tick_share` so the per-frame math is unit-testable without SceneTree.

**Files:**
- Modify: `scripts/events/bomb_pot/bomb_pot_event.gd`
- Modify: `tests/unit/test_bomb_pot_event.gd`

- [ ] **Step 1: Write failing tests**

Append to `tests/unit/test_bomb_pot_event.gd`:
```gdscript
func test_compute_per_tick_share_distributes_across_active_grabbers():
	# 50 chips/sec, 0.5 sec delta, 2 grabbers → each gets 12.5
	var share = BombPotEvent.compute_per_tick_share(0.5, 50.0, 2)
	assert_almost_eq(share, 12.5, 0.001)

func test_compute_per_tick_share_zero_when_no_active_grabbers():
	var share = BombPotEvent.compute_per_tick_share(0.5, 50.0, 0)
	assert_almost_eq(share, 0.0, 0.001)

func test_compute_per_tick_share_solo_grabber_gets_full_rate():
	var share = BombPotEvent.compute_per_tick_share(1.0, 50.0, 1)
	assert_almost_eq(share, 50.0, 0.001)
```

- [ ] **Step 2: Run, watch fail**

Expected: 3 new failures — `compute_per_tick_share` missing.

- [ ] **Step 3: Implement**

In `scripts/events/bomb_pot/bomb_pot_event.gd`, add static at the bottom (near `compute_bomb_at`):

```gdscript
# Per-tick share each active grabber accrues. Returns 0 when no active
# grabbers (no one to draw from the pot). delta in seconds.
static func compute_per_tick_share(delta: float, pot_growth_per_sec: float, active_grabbers: int) -> float:
	if active_grabbers <= 0:
		return 0.0
	return delta * pot_growth_per_sec / float(active_grabbers)
```

Replace the existing `_run` body to enable `_process` and add `_process(delta)`:

Find the existing `_run` (currently ending with `set_process(true)`) and verify it does set `set_process(true)`. Then add the `_process` method:

```gdscript
func _process(delta: float) -> void:
	if _finished or _start_time_ms == 0:
		return
	# UI: pot growth label (clients estimate from local elapsed; host-authoritative
	# at finish via locked_shares broadcast).
	if _pot_label != null:
		var elapsed = (Time.get_ticks_msec() - _start_time_ms) / 1000.0
		var growth = _pot_growth_rate_override if _pot_growth_rate_override >= 0.0 else MatchConfig.BOMB_POT_POT_GROWTH_PER_SEC
		_pot_label.text = "Pot: %d chips" % int(elapsed * growth)
	if _ticker_label != null:
		_ticker_label.text = "Ticking..."
	# Host-only per-frame logic
	if not _is_host:
		return
	# Per-tick share accumulation
	var active_count = _active_peers.size() - _pulled_out_peers.size()
	var growth_rate = _pot_growth_rate_override if _pot_growth_rate_override >= 0.0 else MatchConfig.BOMB_POT_POT_GROWTH_PER_SEC
	var per_tick = compute_per_tick_share(delta, growth_rate, active_count)
	if per_tick > 0.0:
		for pid in _active_peers:
			if not (pid in _pulled_out_peers):
				_shares_accumulator[pid] = _shares_accumulator.get(pid, 0.0) + per_tick
	# Bomb timer check
	var elapsed_sec = (Time.get_ticks_msec() - _start_time_ms) / 1000.0
	if elapsed_sec >= _bomb_at_sec:
		_finish()
		return
	# Early finish: all active peers pulled out
	if active_count == 0:
		_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	set_process(false)
	var result = compute_event_result(_stashed_context, _bomb_at_sec, _locked_shares, _pulled_out_peers, _pull_out_timestamps)
	event_complete.emit(result)
```

Note: `compute_event_result` is the next task. For Task 4, add a stub:

```gdscript
static func compute_event_result(context, bomb_at_sec: float, locked_shares: Dictionary,
								 pulled_out_peers: Array, pull_out_timestamps: Dictionary) -> RefCounted:
	# Stub — full implementation in Task 5.
	var result = EventResult.new()
	result.event_id = "bomb_pot"
	return result
```

- [ ] **Step 4: Run, watch pass**

Expected: **473/473 tests pass** (470 prior + 3 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/events/bomb_pot/bomb_pot_event.gd tests/unit/test_bomb_pot_event.gd
git commit -F - <<'EOF'
feat(client): Bomb Pot _process per-tick shares + bomb timer

compute_per_tick_share(delta, pot_growth_per_sec, active_grabbers) static:
returns delta * pot_growth_per_sec / active_grabbers; 0 when no grabbers.
Testable without SceneTree.

_process(delta): updates pot label estimate (clients local); ticker
label; host-only: accumulates per-tick share to each non-pulled-out
active peer; checks elapsed >= bomb_at_sec → _finish(); early-finish
when all active peers pulled out.

_finish() guards against re-entry, calls set_process(false), emits
event_complete with a result built by compute_event_result (stub
returning event_id only; full math in Task 5).

3 new unit tests for compute_per_tick_share (distribution, zero
guard, solo grabber).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 5: Bomb Pot `compute_event_result` full math + tests

Replaces the stub with full result computation: survivor chip_delta, bust loss, Crown to last-puller (with seat-index tie-break), insurance/multiplier/heat_shield modifier reads.

**Files:**
- Modify: `scripts/events/bomb_pot/bomb_pot_event.gd`
- Modify: `tests/unit/test_bomb_pot_event.gd`

- [ ] **Step 1: Write failing tests**

Append to `tests/unit/test_bomb_pot_event.gd`:
```gdscript
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(peer_id: int, name: String, seat_index: int = -1) -> RefCounted:
	var p = MatchPlayer.new()
	p.peer_id = peer_id
	p.name = name
	p.is_active_this_event = true
	p.seat_index = seat_index if seat_index >= 0 else peer_id
	return p

func _make_context(player_count: int, wagers: Dictionary, modifiers: Dictionary) -> RefCounted:
	var ctx = EventContext.new()
	for i in player_count:
		ctx.players.append(_make_player(i + 1, "P%d" % (i + 1), i))
	ctx.wagers = wagers
	ctx.event_modifiers = modifiers
	return ctx

func test_compute_event_result_survivor_locks_share():
	var ctx = _make_context(2, {1: 100, 2: 100}, {})
	var locked = {1: 200}  # P1 pulled out with 200 chips locked
	var pulled = [1]
	var timestamps = {1: 8000}  # 8 seconds elapsed
	var result = BombPotEvent.compute_event_result(ctx, 15.0, locked, pulled, timestamps)
	assert_eq(result.per_player[1].chip_delta, 200, "survivor gets locked share")
	assert_false(result.per_player[1].bust)

func test_compute_event_result_busted_grabber_loses_wager():
	var ctx = _make_context(2, {1: 100, 2: 150}, {})
	var locked = {}
	var pulled = []  # nobody pulled out
	var timestamps = {}
	var result = BombPotEvent.compute_event_result(ctx, 10.0, locked, pulled, timestamps)
	assert_eq(result.per_player[1].chip_delta, -100, "P1 lost wager")
	assert_eq(result.per_player[2].chip_delta, -150, "P2 lost wager")
	assert_true(result.per_player[1].bust)
	assert_true(result.per_player[2].bust)

func test_compute_event_result_crown_to_last_puller():
	var ctx = _make_context(3, {1: 100, 2: 100, 3: 100}, {})
	var locked = {1: 150, 2: 200, 3: 100}
	var pulled = [1, 2, 3]
	# P2 pulled out last
	var timestamps = {1: 5000, 2: 12000, 3: 8000}
	var result = BombPotEvent.compute_event_result(ctx, 15.0, locked, pulled, timestamps)
	assert_eq(result.per_player[2].crown_delta, 1, "P2 last-puller wins Crown")
	assert_eq(result.per_player[1].crown_delta, 0)
	assert_eq(result.per_player[3].crown_delta, 0)
	assert_eq(result.per_player[2].heat_delta, 1, "Crown winner gets +1 heat")

func test_compute_event_result_crown_tie_breaks_by_seat_index():
	var ctx = _make_context(2, {1: 100, 2: 100}, {})
	var locked = {1: 150, 2: 150}
	var pulled = [1, 2]
	# Same timestamps (impossible-but-defensive scenario)
	var timestamps = {1: 8000, 2: 8000}
	var result = BombPotEvent.compute_event_result(ctx, 15.0, locked, pulled, timestamps)
	# P1 has seat_index=0 (lower); should win the tie
	assert_eq(result.per_player[1].crown_delta, 1, "lower seat_index wins tie")
	assert_eq(result.per_player[2].crown_delta, 0)

func test_compute_event_result_insurance_halves_bust_penalty():
	var ctx = _make_context(2, {1: 200, 2: 200}, {1: {"insurance_pre": true}})
	var locked = {}
	var pulled = []
	var timestamps = {}
	var result = BombPotEvent.compute_event_result(ctx, 8.0, locked, pulled, timestamps)
	assert_eq(result.per_player[1].chip_delta, -100, "Insurance halves P1 bust")
	assert_eq(result.per_player[2].chip_delta, -200, "P2 no insurance, full loss")

func test_compute_event_result_wager_multiplier_boosts_survivor():
	var ctx = _make_context(2, {1: 100, 2: 100}, {1: {"wager_multiplier": 1.25}})
	var locked = {1: 200, 2: 200}
	var pulled = [1, 2]
	var timestamps = {1: 9000, 2: 8000}
	var result = BombPotEvent.compute_event_result(ctx, 15.0, locked, pulled, timestamps)
	assert_eq(result.per_player[1].chip_delta, 250, "200 * 1.25")
	assert_eq(result.per_player[2].chip_delta, 200)

func test_compute_event_result_heat_shield_halves_winner_heat():
	var ctx = _make_context(2, {1: 100, 2: 100}, {1: {"heat_shield": true}})
	var locked = {1: 200, 2: 100}
	var pulled = [1, 2]
	var timestamps = {1: 9000, 2: 7000}  # P1 last puller
	var result = BombPotEvent.compute_event_result(ctx, 15.0, locked, pulled, timestamps)
	assert_eq(result.per_player[1].crown_delta, 1, "P1 wins Crown")
	assert_eq(result.per_player[1].heat_delta, 0, "Heat Shield halves 1 -> 0")
```

- [ ] **Step 2: Run, watch fail**

Expected: 7 new failures — stub returns empty `per_player`.

- [ ] **Step 3: Implement**

Replace the stub `compute_event_result` at the bottom of `bomb_pot_event.gd` with the full implementation:

```gdscript
static func compute_event_result(context, bomb_at_sec: float, locked_shares: Dictionary,
								 pulled_out_peers: Array, pull_out_timestamps: Dictionary) -> RefCounted:
	var result = EventResult.new()
	result.event_id = "bomb_pot"
	var summary: Array = []
	var winner_peer_id = 0
	var winner_pull_out_ms = -1
	var winner_seat = INF
	var modifiers = {}
	if context != null and "event_modifiers" in context:
		modifiers = context.event_modifiers
	for player in context.players:
		var pid = player.peer_id
		var wager = int(context.wagers.get(pid, 0))
		var p_mods = modifiers.get(pid, {})
		if pid in pulled_out_peers:
			# Survivor
			var chip_delta = int(locked_shares.get(pid, 0))
			var wm = float(p_mods.get("wager_multiplier", 1.0))
			if wm != 1.0:
				chip_delta = int(chip_delta * wm)
			var um = float(p_mods.get("underdog_multiplier", 1.0))
			if um != 1.0:
				chip_delta = int(chip_delta * um)
			result.per_player[pid] = {
				"chip_delta": chip_delta,
				"crown_delta": 0,
				"heat_delta": 0,
				"bust": false,
				"cash_out_at": 0.0,
			}
			summary.append({
				"peer_id": pid, "name": player.name,
				"locked_share": locked_shares.get(pid, 0),
				"pull_out_ms": pull_out_timestamps.get(pid, 0),
				"chip_delta": chip_delta, "busted": false, "wager": wager,
			})
			# Track latest puller (with seat_index tie-break)
			var ts = int(pull_out_timestamps.get(pid, 0))
			if ts > winner_pull_out_ms or (ts == winner_pull_out_ms and player.seat_index < winner_seat):
				winner_pull_out_ms = ts
				winner_peer_id = pid
				winner_seat = player.seat_index
		else:
			# Bust
			var bust_loss = wager
			if p_mods.get("insurance_pre", false):
				bust_loss = int(wager / 2)
			result.per_player[pid] = {
				"chip_delta": -bust_loss,
				"crown_delta": 0,
				"heat_delta": 0,
				"bust": true,
				"cash_out_at": 0.0,
			}
			summary.append({
				"peer_id": pid, "name": player.name,
				"locked_share": 0, "pull_out_ms": 0,
				"chip_delta": -bust_loss, "busted": true, "wager": wager,
			})
	# Crown + heat to last puller
	if winner_peer_id != 0:
		result.per_player[winner_peer_id]["crown_delta"] = 1
		var winner_mods = modifiers.get(winner_peer_id, {})
		var heat_delta = 1
		if winner_mods.get("heat_shield", false):
			heat_delta = int(heat_delta / 2)
		result.per_player[winner_peer_id]["heat_delta"] = heat_delta
	result.painful_reveal = {
		"bomb_at_sec": bomb_at_sec,
		"winner_peer_id": winner_peer_id,
		"winner_pull_out_ms": winner_pull_out_ms,
		"pulls_summary": summary,
	}
	return result
```

- [ ] **Step 4: Run, watch pass**

Expected: **480/480 tests pass** (473 prior + 7 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/events/bomb_pot/bomb_pot_event.gd tests/unit/test_bomb_pot_event.gd
git commit -F - <<'EOF'
feat(client): Bomb Pot compute_event_result full math

Survivor: chip_delta = locked_shares[pid], with wager_multiplier and
underdog_multiplier from event_modifiers applied sequentially. Bust:
chip_delta = -wager, halved to -wager/2 by insurance_pre. Crown +1
to the latest-pulled peer, with seat_index tie-break for the
defensive equal-timestamp case. Heat Shield halves Crown winner's
heat_delta (1 -> 0). painful_reveal carries bomb_at_sec, winner peer +
timestamp, pulls_summary array.

7 unit tests cover survivor, bust, crown selection, tie-break,
insurance halve, wager multiplier, heat shield interactions.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 6: Bomb Pot scene file

Creates the `.tscn` for the runtime UI: pot label, ticker label, pull-out button.

**Files:**
- Create: `scenes/events/bomb_pot/bomb_pot_event.tscn`

- [ ] **Step 1: Create scene**

`scenes/events/bomb_pot/bomb_pot_event.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/events/bomb_pot/bomb_pot_event.gd" id="1"]

[node name="BombPotEvent" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="VBox" type="VBoxContainer" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0

[node name="Title" type="Label" parent="VBox"]
text = "Bomb Pot"

[node name="PotLabel" type="Label" parent="VBox"]
text = "Pot: 0 chips"

[node name="TickerLabel" type="Label" parent="VBox"]
text = "Waiting..."

[node name="PullOutButton" type="Button" parent="VBox"]
text = "Pull Out"
```

- [ ] **Step 2: Run test suite to verify nothing broke**

Expected: **480/480 tests still pass** (no new tests; scene file doesn't affect unit tests).

- [ ] **Step 3: Commit**

```bash
git add scenes/events/bomb_pot/bomb_pot_event.tscn
git commit -F - <<'EOF'
feat(client): Bomb Pot scene file

Control root → VBox → Title + PotLabel + TickerLabel + PullOutButton.
PotLabel updates per-frame via _process; PullOutButton.pressed
connects to _on_pull_out_button_pressed → submit_pull_out.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 7: MatchController integration tests for Bomb Pot

Verifies Bomb Pot pull-out wires correctly when driven through `MatchController` with a `FakeMultiplayerNode`.

**Files:**
- Create: `tests/unit/test_match_controller_bomb_pot_pull_out.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_match_controller_bomb_pot_pull_out.gd`:
```gdscript
extends GutTest

const BombPotEvent = preload("res://scripts/events/bomb_pot/bomb_pot_event.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func _new_bomb_pot_event_at_main_event() -> Dictionary:
	# Construct a Bomb Pot event in the running state (post-_run).
	# Bypasses MatchController setup; tests focus on event-level RPC validation.
	var fake = FakeMultiplayerNode.new()
	var e = Node.new()
	e.set_script(BombPotEvent)
	e._is_host = true
	e._multiplayer_node = fake
	e._start_time_ms = Time.get_ticks_msec()
	e._active_peers = [1, 2]
	e._shares_accumulator = {1: 50.0, 2: 80.0}
	return {"event": e, "fake": fake}

func test_pull_out_during_main_event_locks_share():
	var d = _new_bomb_pot_event_at_main_event()
	var e = d.event
	e._rpc_pull_out_requested(1)
	assert_eq(e._locked_shares.get(1, 0), 50)
	assert_true(1 in e._pulled_out_peers)
	e.free()

func test_pull_out_outside_main_event_rejected():
	# Simulate "main event hasn't started" via _start_time_ms == 0
	var fake = FakeMultiplayerNode.new()
	var e = Node.new()
	e.set_script(BombPotEvent)
	e._is_host = true
	e._multiplayer_node = fake
	e._start_time_ms = 0  # not yet started
	e._active_peers = [1, 2]
	e._rpc_pull_out_requested(1)
	assert_eq(e._locked_shares.get(1, 0), 0)
	assert_false(1 in e._pulled_out_peers)
	e.free()

func test_double_pull_out_silently_dropped():
	var d = _new_bomb_pot_event_at_main_event()
	var e = d.event
	e._rpc_pull_out_requested(1)
	d.fake.rpc_calls.clear()
	e._rpc_pull_out_requested(1)
	var ack_count = 0
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_pull_out_confirmed":
			ack_count += 1
	assert_eq(ack_count, 0)
	e.free()
```

- [ ] **Step 2: Run, watch pass**

These tests exercise the existing RPC handler implemented in Task 3. Expected: **483/483 tests pass** (480 prior + 3 new).

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_match_controller_bomb_pot_pull_out.gd
git commit -F - <<'EOF'
test(client): Bomb Pot pull-out RPC validation tests

3 controller-style integration tests against FakeMultiplayerNode:
- Pull-out during MAIN_EVENT locks the share + appends to pulled_out_peers
- Pull-out before MAIN_EVENT (start_time_ms == 0) silently rejected
- Double-tap pull-out emits only one _rpc_pull_out_confirmed

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 3: Card Cannon (Tasks 8-13)

### Task 8: Card Cannon event script skeleton + `compute_next_rank` + `compute_score`

Creates the script with fields, `extends`, `_run`, `get_event_id`, and both static helpers (`compute_next_rank`, `compute_score`). Same pattern as Bomb Pot Task 2.

**Files:**
- Create: `scripts/events/card_cannon/card_cannon_event.gd`
- Create: `tests/unit/test_card_cannon_event.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_card_cannon_event.gd`:
```gdscript
extends GutTest

const CardCannonEvent = preload("res://scripts/events/card_cannon/card_cannon_event.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")

func _new_rng(seed_value: int) -> RandomNumberGenerator:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

func test_compute_next_rank_distribution_within_range():
	var rng = _new_rng(1)
	for i in 1000:
		var rank = CardCannonEvent.compute_next_rank(rng)
		assert_true(rank >= 2 and rank <= 11, "rank out of range: %d" % rank)

func test_compute_next_rank_deterministic_with_same_seed():
	var rng1 = _new_rng(42)
	var rng2 = _new_rng(42)
	for i in 10:
		assert_eq(CardCannonEvent.compute_next_rank(rng1), CardCannonEvent.compute_next_rank(rng2))

func test_compute_score_basic_sum():
	assert_eq(CardCannonEvent.compute_score([5, 7]), 12)
	assert_eq(CardCannonEvent.compute_score([10, 10]), 20)

func test_compute_score_ace_counts_high_when_safe():
	# Ace (11) + 9 = 20 (safe under 21)
	assert_eq(CardCannonEvent.compute_score([11, 9]), 20)

func test_compute_score_ace_demotes_to_low_to_avoid_bust():
	# Ace (11) + 10 + 5 = 26 → bust → Ace becomes 1 → 16
	assert_eq(CardCannonEvent.compute_score([11, 10, 5]), 16)

func test_compute_score_multiple_aces():
	# Ace + Ace + 9 = 21 (one Ace high, one low)
	assert_eq(CardCannonEvent.compute_score([11, 11, 9]), 21)
	# Ace + Ace + Ace + 10 = 13 (one high, two low: 11+1+1+10=23 → 1+1+1+10=13)
	assert_eq(CardCannonEvent.compute_score([11, 11, 11, 10]), 13)
```

- [ ] **Step 2: Run, watch fail**

Expected: `CardCannonEvent` preload error.

- [ ] **Step 3: Implement**

Create `scripts/events/card_cannon/card_cannon_event.gd`:
```gdscript
# Card Cannon event. Async blackjack-to-21. Per-player independent
# draws from a number-cards + Ace deck (infinite-deck distribution).
# Lock at any time; bust at score > 21. Score-band payout tiers.
#
# Extends EventNode. compute_next_rank, compute_score, and
# compute_event_result are testable without scene instantiation.
extends "res://scripts/events/event_node.gd"

const MatchConfig = preload("res://scripts/match/match_config.gd")
const EventResult = preload("res://scripts/events/event_result.gd")

# Per-round state
var _hands: Dictionary = {}             # peer_id -> Array[int] ranks drawn
var _scores: Dictionary = {}            # peer_id -> int running score
var _locked_scores: Dictionary = {}     # peer_id -> int score at lock
var _busted: Dictionary = {}            # peer_id -> bool
var _active_peers: Array = []
var _is_host: bool = false
var _finished: bool = false
var _stashed_context = null
var _rng: RandomNumberGenerator = null  # seeded from context.rng_seed in _run

# RPC routing
var _multiplayer_node = null

# Test seams
var _force_next_rank_override: int = -1   # negative = use RNG

# Scene-tree refs
@onready var _score_label: Label = $VBox/ScoreLabel if has_node("VBox/ScoreLabel") else null
@onready var _hand_row: HBoxContainer = $VBox/HandRow if has_node("VBox/HandRow") else null
@onready var _draw_button: Button = $VBox/DrawButton if has_node("VBox/DrawButton") else null
@onready var _lock_button: Button = $VBox/LockButton if has_node("VBox/LockButton") else null

func get_event_id() -> String:
	return "card_cannon"

func _ready() -> void:
	if _draw_button != null:
		_draw_button.pressed.connect(_on_draw_button_pressed)
	if _lock_button != null:
		_lock_button.pressed.connect(_on_lock_button_pressed)

func _on_draw_button_pressed() -> void:
	if _finished:
		return
	submit_draw()

func _on_lock_button_pressed() -> void:
	if _finished:
		return
	submit_lock()

func submit_draw() -> void:
	var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
	_send_rpc("_rpc_draw_requested", [my_peer_id])

func submit_lock() -> void:
	var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
	_send_rpc("_rpc_lock_requested", [my_peer_id])

func _run(context) -> void:
	_stashed_context = context
	_is_host = context.is_host
	# Derive a per-event RNG from context.rng_seed (EventContext exposes
	# rng_seed, not rng). Storing as an instance field so successive draws
	# advance the same sequence — same pattern as RocketClashEvent.
	_rng = RandomNumberGenerator.new()
	_rng.seed = context.rng_seed
	_active_peers = []
	for p in context.players:
		if p.is_active_this_event:
			_active_peers.append(p.peer_id)
			_hands[p.peer_id] = []
			_scores[p.peer_id] = 0
			_busted[p.peer_id] = false
	if _is_host:
		_send_rpc("_rpc_card_cannon_started", [])

@rpc("authority", "call_remote", "reliable")
func _rpc_card_cannon_started() -> void:
	pass  # clients render the scene; no time sync needed

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
			push_error("CardCannonEvent._send_rpc: unsupported arity %d" % args.size())

func _send_rpc_to_peer(peer_id: int, method_name: String, args: Array = []) -> void:
	if _multiplayer_node == null:
		return
	match args.size():
		0: _multiplayer_node.rpc_id(peer_id, method_name)
		1: _multiplayer_node.rpc_id(peer_id, method_name, args[0])
		2: _multiplayer_node.rpc_id(peer_id, method_name, args[0], args[1])
		_:
			push_error("CardCannonEvent._send_rpc_to_peer: unsupported arity %d" % args.size())

# ----- Static helpers -----

# Returns a single card rank in [2, 11]. 11 is the Ace (high value; the
# score computation will demote to 1 if needed to avoid bust). Uniform
# distribution; infinite-deck simplification.
static func compute_next_rank(rng: RandomNumberGenerator) -> int:
	return 2 + int(rng.randf() * 10)

# Computes the score from a hand. Aces (rank 11) auto-demote to 1 if
# the total exceeds 21 and an Ace can still be demoted.
static func compute_score(hand: Array) -> int:
	var total = 0
	var aces = 0
	for rank in hand:
		if rank == 11:
			aces += 1
		total += rank
	while total > 21 and aces > 0:
		total -= 10  # demote one Ace from 11 to 1
		aces -= 1
	return total
```

- [ ] **Step 4: Run, watch pass**

Expected: **489/489 tests pass** (483 prior + 6 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/events/card_cannon/card_cannon_event.gd tests/unit/test_card_cannon_event.gd
git commit -F - <<'EOF'
feat(client): Card Cannon event skeleton + compute_next_rank + compute_score

CardCannonEvent extends event_node.gd. Fields for hands, scores,
locked_scores, busted, active peers, finished flag, stashed context.
Test seam: _force_next_rank_override.

compute_next_rank(rng): uniform draw from {2..11} (infinite-deck
simplification; 11 = Ace). compute_score(hand): sums ranks; demotes
each high Ace (11→1) one at a time while total > 21 and any Ace
can still be demoted.

get_event_id returns "card_cannon". _run initializes per-peer hands/
scores/busted. RPCs land in subsequent tasks.

6 unit tests: rank distribution + determinism, basic score sum, Ace
high when safe, Ace demote on bust, multiple Aces with cascading
demotion.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 9: Card Cannon draw/lock RPCs

Adds `_rpc_draw_requested`, `_rpc_card_drawn`, `_rpc_lock_requested`, `_rpc_locked`, `_all_active_settled`, and `_finish` (stub `compute_event_result` for now).

**Files:**
- Modify: `scripts/events/card_cannon/card_cannon_event.gd`
- Modify: `tests/unit/test_card_cannon_event.gd`

- [ ] **Step 1: Write failing tests**

Append to `tests/unit/test_card_cannon_event.gd`:
```gdscript
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func _new_host_card_cannon_at_main() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var e = Node.new()
	e.set_script(CardCannonEvent)
	e._is_host = true
	e._multiplayer_node = fake
	e._active_peers = [1, 2]
	e._hands = {1: [], 2: []}
	e._scores = {1: 0, 2: 0}
	e._busted = {1: false, 2: false}
	# Stash a minimal context with an RNG for compute_next_rank
	var EventContext = load("res://scripts/events/event_context.gd")
	var ctx = EventContext.new()
	ctx.rng_seed = 1
	# Stub: event needs context.rng for compute_next_rank. Set it directly.
	# Use force_next_rank_override to bypass.
	e._stashed_context = ctx
	return {"event": e, "fake": fake}

func test_draw_appends_to_hand_and_updates_score():
	var d = _new_host_card_cannon_at_main()
	var e = d.event
	e._force_next_rank_override = 7
	e._rpc_draw_requested(1)
	assert_eq(e._hands[1], [7])
	assert_eq(e._scores[1], 7)
	e.free()

func test_draw_busts_at_22_or_higher():
	var d = _new_host_card_cannon_at_main()
	var e = d.event
	e._hands[1] = [10, 7]
	e._scores[1] = 17
	e._force_next_rank_override = 6  # 17 + 6 = 23 → bust
	e._rpc_draw_requested(1)
	assert_eq(e._scores[1], 23)
	assert_true(e._busted[1])
	e.free()

func test_lock_freezes_score():
	var d = _new_host_card_cannon_at_main()
	var e = d.event
	e._hands[1] = [10, 8]
	e._scores[1] = 18
	e._rpc_lock_requested(1)
	assert_eq(e._locked_scores.get(1, -1), 18)
	e.free()

func test_draw_after_lock_rejected():
	var d = _new_host_card_cannon_at_main()
	var e = d.event
	e._locked_scores[1] = 17
	e._force_next_rank_override = 10
	e._rpc_draw_requested(1)
	# Should not have drawn anything (no hand mutation)
	assert_eq(e._hands.get(1, []), [])
	e.free()

func test_draw_after_bust_rejected():
	var d = _new_host_card_cannon_at_main()
	var e = d.event
	e._busted[1] = true
	e._hands[1] = [10, 10, 5]  # already busted at 25
	e._scores[1] = 25
	e._force_next_rank_override = 5
	e._rpc_draw_requested(1)
	# Hand should not have grown
	assert_eq(e._hands[1], [10, 10, 5])
	e.free()
```

- [ ] **Step 2: Run, watch fail**

Expected: 5 new failures — RPC methods missing.

- [ ] **Step 3: Implement**

Add after `_send_rpc_to_peer` in `card_cannon_event.gd`:

```gdscript
@rpc("any_peer", "call_local", "reliable")
func _rpc_draw_requested(peer_id: int) -> void:
	if not _is_host:
		return
	if _finished:
		return
	if peer_id in _locked_scores:
		return  # already locked
	if _busted.get(peer_id, false):
		return  # already busted
	if not (peer_id in _active_peers):
		return  # peer not active
	var rank = _draw_next_rank()
	if not _hands.has(peer_id):
		_hands[peer_id] = []
	_hands[peer_id].append(rank)
	var new_score = compute_score(_hands[peer_id])
	_scores[peer_id] = new_score
	var is_busted = new_score > 21
	if is_busted:
		_busted[peer_id] = true
	_send_rpc("_rpc_card_drawn", [peer_id, rank, new_score, is_busted])
	if _all_active_settled():
		_finish()

@rpc("authority", "call_remote", "reliable")
func _rpc_card_drawn(peer_id: int, rank: int, new_score: int, is_busted: bool) -> void:
	if not _hands.has(peer_id):
		_hands[peer_id] = []
	_hands[peer_id].append(rank)
	_scores[peer_id] = new_score
	_busted[peer_id] = is_busted

@rpc("any_peer", "call_local", "reliable")
func _rpc_lock_requested(peer_id: int) -> void:
	if not _is_host:
		return
	if _finished:
		return
	if peer_id in _locked_scores:
		return
	if _busted.get(peer_id, false):
		return
	if not (peer_id in _active_peers):
		return
	_locked_scores[peer_id] = _scores.get(peer_id, 0)
	_send_rpc("_rpc_locked", [peer_id, _locked_scores[peer_id]])
	if _all_active_settled():
		_finish()

@rpc("authority", "call_remote", "reliable")
func _rpc_locked(peer_id: int, locked_score: int) -> void:
	_locked_scores[peer_id] = locked_score

func _draw_next_rank() -> int:
	if _force_next_rank_override >= 0:
		return _force_next_rank_override
	# _rng is set by _run from context.rng_seed; defensive fallback for tests
	# that bypass _run (they set _force_next_rank_override instead).
	if _rng == null:
		_rng = RandomNumberGenerator.new()
	return compute_next_rank(_rng)

func _all_active_settled() -> bool:
	for pid in _active_peers:
		if (pid in _locked_scores) or _busted.get(pid, false):
			continue
		return false
	return true

func _finish() -> void:
	if _finished:
		return
	_finished = true
	var result = compute_event_result(_stashed_context, _hands, _locked_scores, _busted)
	event_complete.emit(result)
```

Add stub `compute_event_result` at the bottom (full implementation in Task 10):
```gdscript
static func compute_event_result(context, hands: Dictionary, locked_scores: Dictionary, busted: Dictionary) -> RefCounted:
	var result = EventResult.new()
	result.event_id = "card_cannon"
	return result
```

- [ ] **Step 4: Run, watch pass**

Expected: **494/494 tests pass** (489 prior + 5 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/events/card_cannon/card_cannon_event.gd tests/unit/test_card_cannon_event.gd
git commit -F - <<'EOF'
feat(client): Card Cannon draw/lock RPC pipeline

_rpc_draw_requested @rpc("any_peer", "call_local", "reliable") host:
validates is_host + not finished + not locked + not busted + active;
draws next rank (via _draw_next_rank with override fallback); appends
to hand; recomputes score via compute_score; sets busted flag if > 21;
broadcasts _rpc_card_drawn.

_rpc_lock_requested similar; sets locked_scores[peer_id] = current
score; broadcasts _rpc_locked.

_rpc_card_drawn / _rpc_locked @rpc("authority", "call_remote", "reliable")
client mirrors.

_all_active_settled() returns true when every active peer is either
locked or busted. _finish() calls compute_event_result (stub for now;
full math in Task 10) and emits event_complete.

5 unit tests: draw updates hand+score, draw busts at 22+, lock freezes
score, draw after lock rejected, draw after bust rejected.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 10: Card Cannon `compute_event_result` full math + tests

Full payout-band math with bust handling, Crown to highest locked_score (seat-index tie-break), Insurance/Multiplier/Heat Shield modifier reads.

**Files:**
- Modify: `scripts/events/card_cannon/card_cannon_event.gd`
- Modify: `tests/unit/test_card_cannon_event.gd`

- [ ] **Step 1: Write failing tests**

Append to `tests/unit/test_card_cannon_event.gd`:
```gdscript
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player_cc(peer_id: int, name: String, seat_index: int = -1) -> RefCounted:
	var p = MatchPlayer.new()
	p.peer_id = peer_id
	p.name = name
	p.is_active_this_event = true
	p.seat_index = seat_index if seat_index >= 0 else peer_id
	return p

func _make_context_cc(player_count: int, wagers: Dictionary, modifiers: Dictionary) -> RefCounted:
	var ctx = EventContext.new()
	for i in player_count:
		ctx.players.append(_make_player_cc(i + 1, "P%d" % (i + 1), i))
	ctx.wagers = wagers
	ctx.event_modifiers = modifiers
	return ctx

func test_compute_event_result_score_band_payouts():
	# Five band assertions in one test.
	var ctx = _make_context_cc(5, {1: 100, 2: 100, 3: 100, 4: 100, 5: 100}, {})
	var hands = {1: [10], 2: [10, 3], 3: [10, 7], 4: [10, 9], 5: [10, 11]}
	var locked = {1: 10, 2: 13, 3: 17, 4: 19, 5: 21}
	var busted = {}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	assert_eq(result.per_player[1].chip_delta, 50, "band low: 100 * 0.5")
	assert_eq(result.per_player[2].chip_delta, 100, "band medium: 100 * 1.0")
	assert_eq(result.per_player[3].chip_delta, 150, "band strong: 100 * 1.5")
	assert_eq(result.per_player[4].chip_delta, 200, "band heavy: 100 * 2.0")
	assert_eq(result.per_player[5].chip_delta, 300, "band perfect: 100 * 3.0")

func test_compute_event_result_busted_player_loses_wager():
	var ctx = _make_context_cc(2, {1: 100, 2: 100}, {})
	var hands = {1: [10, 10, 5], 2: [10, 5]}
	var locked = {2: 15}
	var busted = {1: true}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	assert_eq(result.per_player[1].chip_delta, -100)
	assert_true(result.per_player[1].bust)
	assert_eq(result.per_player[2].chip_delta, 100, "band medium")

func test_compute_event_result_crown_to_highest_locked_score():
	var ctx = _make_context_cc(3, {1: 100, 2: 100, 3: 100}, {})
	var hands = {1: [10, 7], 2: [10, 9], 3: [10, 5]}
	var locked = {1: 17, 2: 19, 3: 15}
	var busted = {}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	assert_eq(result.per_player[2].crown_delta, 1, "P2 highest")
	assert_eq(result.per_player[1].crown_delta, 0)
	assert_eq(result.per_player[3].crown_delta, 0)

func test_compute_event_result_crown_tie_breaks_by_seat_index():
	var ctx = _make_context_cc(2, {1: 100, 2: 100}, {})
	# seat_index for P1 = 0, P2 = 1 (per _make_player_cc default)
	var hands = {1: [10, 8], 2: [10, 8]}
	var locked = {1: 18, 2: 18}
	var busted = {}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	assert_eq(result.per_player[1].crown_delta, 1, "lower seat_index wins tie")
	assert_eq(result.per_player[2].crown_delta, 0)

func test_compute_event_result_insurance_halves_bust_penalty():
	var ctx = _make_context_cc(2, {1: 200, 2: 200}, {1: {"insurance_pre": true}})
	var hands = {1: [10, 10, 5], 2: [10, 10, 5]}
	var locked = {}
	var busted = {1: true, 2: true}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	assert_eq(result.per_player[1].chip_delta, -100, "P1 Insurance halves")
	assert_eq(result.per_player[2].chip_delta, -200, "P2 no Insurance")

func test_compute_event_result_underdog_odds_boosts_survivor():
	var ctx = _make_context_cc(2, {1: 100, 2: 100}, {1: {"underdog_multiplier": 1.5}})
	var hands = {1: [10, 9], 2: [10, 8]}
	var locked = {1: 19, 2: 18}
	var busted = {}
	var result = CardCannonEvent.compute_event_result(ctx, hands, locked, busted)
	# P1: 100 * 2.0 (heavy band) * 1.5 = 300
	assert_eq(result.per_player[1].chip_delta, 300)
	# P2: 100 * 1.5 (strong band) = 150
	assert_eq(result.per_player[2].chip_delta, 150)
```

- [ ] **Step 2: Run, watch fail**

Expected: 6 new failures — stub returns empty per_player.

- [ ] **Step 3: Implement**

Replace the stub at the bottom of `card_cannon_event.gd`:

```gdscript
static func compute_event_result(context, hands: Dictionary, locked_scores: Dictionary, busted: Dictionary) -> RefCounted:
	var result = EventResult.new()
	result.event_id = "card_cannon"
	var summary: Array = []
	var winner_peer_id = 0
	var winner_score = 0
	var winner_seat = INF
	var modifiers = {}
	if context != null and "event_modifiers" in context:
		modifiers = context.event_modifiers
	for player in context.players:
		var pid = player.peer_id
		var wager = int(context.wagers.get(pid, 0))
		var p_mods = modifiers.get(pid, {})
		if busted.get(pid, false):
			var bust_loss = wager
			if p_mods.get("insurance_pre", false):
				bust_loss = int(wager / 2)
			result.per_player[pid] = {
				"chip_delta": -bust_loss, "crown_delta": 0, "heat_delta": 0,
				"bust": true, "cash_out_at": 0.0,
			}
			summary.append({
				"peer_id": pid, "name": player.name,
				"score": compute_score(hands.get(pid, [])),
				"locked_score": 0, "chip_delta": -bust_loss, "busted": true, "wager": wager,
			})
		else:
			var locked = int(locked_scores.get(pid, 0))
			var band_mult = _band_multiplier(locked)
			var chip_delta = int(wager * band_mult)
			var wm = float(p_mods.get("wager_multiplier", 1.0))
			if wm != 1.0:
				chip_delta = int(chip_delta * wm)
			var um = float(p_mods.get("underdog_multiplier", 1.0))
			if um != 1.0:
				chip_delta = int(chip_delta * um)
			result.per_player[pid] = {
				"chip_delta": chip_delta, "crown_delta": 0, "heat_delta": 0,
				"bust": false, "cash_out_at": 0.0,
			}
			summary.append({
				"peer_id": pid, "name": player.name,
				"score": locked, "locked_score": locked,
				"chip_delta": chip_delta, "busted": false, "wager": wager,
			})
			# Track winner (seat_index tie-break)
			if locked > winner_score or (locked == winner_score and player.seat_index < winner_seat):
				winner_score = locked
				winner_peer_id = pid
				winner_seat = player.seat_index
	# Crown + heat
	if winner_peer_id != 0 and winner_score > 0:
		result.per_player[winner_peer_id]["crown_delta"] = 1
		var winner_mods = modifiers.get(winner_peer_id, {})
		var heat_delta = 1
		if winner_mods.get("heat_shield", false):
			heat_delta = int(heat_delta / 2)
		result.per_player[winner_peer_id]["heat_delta"] = heat_delta
	result.painful_reveal = {
		"winner_peer_id": winner_peer_id,
		"winner_score": winner_score,
		"scores_summary": summary,
	}
	return result

static func _band_multiplier(score: int) -> float:
	if score == 21:
		return MatchConfig.CARD_CANNON_PAYOUT_BAND_PERFECT
	if score >= 19:
		return MatchConfig.CARD_CANNON_PAYOUT_BAND_HEAVY
	if score >= 16:
		return MatchConfig.CARD_CANNON_PAYOUT_BAND_STRONG
	if score >= 11:
		return MatchConfig.CARD_CANNON_PAYOUT_BAND_MEDIUM
	return MatchConfig.CARD_CANNON_PAYOUT_BAND_LOW
```

- [ ] **Step 4: Run, watch pass**

Expected: **500/500 tests pass** (494 prior + 6 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/events/card_cannon/card_cannon_event.gd tests/unit/test_card_cannon_event.gd
git commit -F - <<'EOF'
feat(client): Card Cannon compute_event_result full math

Survivor: chip_delta = wager * _band_multiplier(locked_score), with
wager_multiplier + underdog_multiplier applied sequentially.
_band_multiplier returns 0.5/1.0/1.5/2.0/3.0 for score ranges
1-10/11-15/16-18/19-20/21. Bust: chip_delta = -wager, halved by
insurance_pre. Crown +1 to highest non-zero locked_score; ties break
by lowest seat_index. Heat Shield halves Crown winner's heat_delta.

painful_reveal carries winner_peer_id, winner_score, scores_summary
array with per-player score/locked/chip_delta entries.

6 unit tests: 5-band payouts in one test (all assertions), busted
loses wager + insurance halve, Crown highest, Crown tie-break, Insurance
halve isolated, Underdog Odds stacks with band multiplier.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 11: Card Cannon scene file

**Files:**
- Create: `scenes/events/card_cannon/card_cannon_event.tscn`

- [ ] **Step 1: Create scene**

`scenes/events/card_cannon/card_cannon_event.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/events/card_cannon/card_cannon_event.gd" id="1"]

[node name="CardCannonEvent" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="VBox" type="VBoxContainer" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0

[node name="Title" type="Label" parent="VBox"]
text = "Card Cannon"

[node name="ScoreLabel" type="Label" parent="VBox"]
text = "Score: 0"

[node name="HandRow" type="HBoxContainer" parent="VBox"]

[node name="DrawButton" type="Button" parent="VBox"]
text = "Draw"

[node name="LockButton" type="Button" parent="VBox"]
text = "Lock"
```

- [ ] **Step 2: Run suite**

Expected: **500/500 tests still pass**.

- [ ] **Step 3: Commit**

```bash
git add scenes/events/card_cannon/card_cannon_event.tscn
git commit -F - <<'EOF'
feat(client): Card Cannon scene file

Control root → VBox → Title + ScoreLabel + HandRow + DrawButton +
LockButton. DrawButton.pressed → submit_draw; LockButton.pressed →
submit_lock.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 12: MatchController integration tests for Card Cannon

**Files:**
- Create: `tests/unit/test_match_controller_card_cannon_draw.gd`

- [ ] **Step 1: Write tests** (already covered functionally by Task 9 tests; this task adds 4 more end-to-end tests through the full event lifecycle)

`tests/unit/test_match_controller_card_cannon_draw.gd`:
```gdscript
extends GutTest

const CardCannonEvent = preload("res://scripts/events/card_cannon/card_cannon_event.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func _new_card_cannon_at_main() -> Dictionary:
	var fake = FakeMultiplayerNode.new()
	var e = Node.new()
	e.set_script(CardCannonEvent)
	e._is_host = true
	e._multiplayer_node = fake
	e._active_peers = [1, 2]
	e._hands = {1: [], 2: []}
	e._scores = {1: 0, 2: 0}
	e._busted = {1: false, 2: false}
	var EventContext = load("res://scripts/events/event_context.gd")
	var ctx = EventContext.new()
	ctx.rng_seed = 1
	e._stashed_context = ctx
	return {"event": e, "fake": fake}

func test_draw_during_main_event_updates_score():
	var d = _new_card_cannon_at_main()
	var e = d.event
	e._force_next_rank_override = 7
	e._rpc_draw_requested(1)
	assert_eq(e._scores[1], 7)
	# Verify broadcast
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_card_drawn":
			found = true
			break
	assert_true(found, "_rpc_card_drawn broadcast")
	e.free()

func test_lock_during_main_event_freezes_score():
	var d = _new_card_cannon_at_main()
	var e = d.event
	e._hands[1] = [10, 8]
	e._scores[1] = 18
	e._rpc_lock_requested(1)
	assert_eq(e._locked_scores.get(1, -1), 18)
	# Verify broadcast
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_locked":
			found = true
			break
	assert_true(found)
	e.free()

func test_draw_after_lock_rejected():
	var d = _new_card_cannon_at_main()
	var e = d.event
	e._locked_scores[1] = 17
	e._force_next_rank_override = 10
	d.fake.rpc_calls.clear()
	e._rpc_draw_requested(1)
	# Hand should not have grown; no _rpc_card_drawn broadcast
	assert_eq(e._hands.get(1, []), [])
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_card_drawn":
			found = true
			break
	assert_false(found)
	e.free()

func test_draw_after_bust_rejected():
	var d = _new_card_cannon_at_main()
	var e = d.event
	e._busted[1] = true
	e._hands[1] = [10, 10, 5]
	e._scores[1] = 25
	e._force_next_rank_override = 5
	d.fake.rpc_calls.clear()
	e._rpc_draw_requested(1)
	assert_eq(e._hands[1], [10, 10, 5])
	var found = false
	for call in d.fake.rpc_calls:
		if call.method == "_rpc_card_drawn":
			found = true
			break
	assert_false(found)
	e.free()
```

- [ ] **Step 2: Run, watch pass**

These reuse the RPC handlers from Task 9. Expected: **504/504 tests pass** (500 prior + 4 new).

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_match_controller_card_cannon_draw.gd
git commit -F - <<'EOF'
test(client): Card Cannon draw/lock RPC validation tests

4 controller-style integration tests against FakeMultiplayerNode:
- Draw during MAIN_EVENT updates score + broadcasts _rpc_card_drawn
- Lock during MAIN_EVENT freezes score + broadcasts _rpc_locked
- Draw after lock rejected (no hand mutation, no broadcast)
- Draw after bust rejected

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 4: Integration (Tasks 13-15)

### Task 13: Append events to MatchConfig.EVENT_POOL

Wires the two new event scenes into the rotation. Selection logic unchanged (uniform random in MatchController).

**Files:**
- Modify: `scripts/match/match_config.gd`

- [ ] **Step 1: Locate the existing EVENT_POOL**

In `scripts/match/match_config.gd`, find:
```gdscript
const EVENT_POOL: Array = [
	"res://scripts/events/rocket_clash/rocket_clash_event.tscn",
]
```

- [ ] **Step 2: Replace with the 3-event pool**

```gdscript
const EVENT_POOL: Array = [
	"res://scripts/events/rocket_clash/rocket_clash_event.tscn",
	"res://scenes/events/bomb_pot/bomb_pot_event.tscn",
	"res://scenes/events/card_cannon/card_cannon_event.tscn",
]
```

**Note:** Rocket Clash's scene path uses `scripts/events/...` (legacy from sub-project #3) but Bomb Pot and Card Cannon use `scenes/events/...` per the new file-structure convention. Don't normalize Rocket Clash's path — that's an unrelated cleanup.

- [ ] **Step 3: Run suite**

Expected: **504/504 tests still pass** (no test changes; existing tests don't assert specific EVENT_POOL contents).

- [ ] **Step 4: Commit**

```bash
git add scripts/match/match_config.gd
git commit -F - <<'EOF'
feat(client): EVENT_POOL gains Bomb Pot + Card Cannon scenes

MatchConfig.EVENT_POOL goes from 1 entry (Rocket Clash) to 3. Selection
logic in MatchController._process_event_selection unchanged: uniform
random via state.rng.randi() % pool.size().

A 5-event Quick Clash match now picks 5 times from 3 events; same event
may repeat 2-3 times. No-repeat / weighted selection is sub-project #6
territory.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 14: Integration test stub (PENDING placeholder)

Per sub-project #3/#4 precedent: an integration test that PENDINGs cleanly when the signaling server isn't running.

**Files:**
- Create: `tests/integration/test_three_event_rotation.gd`

- [ ] **Step 1: Create the placeholder**

`tests/integration/test_three_event_rotation.gd`:
```gdscript
# Integration smoke test: real signaling + WebRTC + 3-event rotation.
# Spawns two NetSession instances; runs a Quick Clash; verifies all
# three event_id values appear across the painful_reveal stream
# (probabilistic: with 3 events and 5 rounds, the probability of NOT
# seeing all 3 = 3 * (2/3)^5 ≈ 39.5%; this test is best-effort and
# may need re-runs).
#
# Skips if signaling server is not reachable on ws://localhost:8080.
extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const WebRTCTransport = preload("res://scripts/net/web_rtc_transport.gd")
const SignalingClient = preload("res://scripts/net/signaling_client.gd")

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

func test_three_event_rotation():
	if not await _signaling_reachable():
		pending("Signaling server not reachable at %s; skipping. Start with `cd ../signaling-server && node server.js`." % SIGNALING_URL)
		return
	# Implementer note: full implementation should cargo-cult the host/
	# joiner NetSession setup from test_rocket_clash_runs.gd. Drive a
	# 5-event Quick Clash; collect event_ids from each painful_reveal;
	# assert at least 2 distinct event_ids appear (probabilistically all 3
	# but realistically 2+).
	#
	# Manual verification (running the game) is the primary surface for
	# the 3-event rotation behavior, per sub-project #3 precedent.
	pending("Implementer: cargo-cult test_rocket_clash_runs.gd; drive 5-event match; assert 2+ distinct event_ids.")
```

- [ ] **Step 2: Run integration suite**

```
godot --headless --path c:/Users/whann/Desktop/Games/RocketMan -s addons/gut/gut_cmdln.gd -gdir=tests/integration -gexit
```

Expected: 4 PENDING (existing 3 + 1 new); 0 failures.

- [ ] **Step 3: Commit**

```bash
git add tests/integration/test_three_event_rotation.gd
git commit -F - <<'EOF'
test(client): 3-event rotation integration test stub

End-to-end smoke test placeholder: host + joiner run a 5-event Quick
Clash and verify multiple event_ids appear in the painful_reveal stream.
Currently PENDINGs cleanly when signaling server isn't running; full
implementation deferred per sub-project #3/#4 integration test precedent
— manual verification via running the game is the primary surface.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 15: Playtest checklist update

**Files:**
- Modify: `docs/PLAYTEST_CHECKLIST.md`

- [ ] **Step 1: Read existing checklist**

Read `docs/PLAYTEST_CHECKLIST.md` to confirm structure.

- [ ] **Step 2: Append sub-project #5 scenarios**

Append to the end of the file:

```
## Sub-project #5 additions

| # | Scenario | Pass criteria |
|---|----------|---------------|
| 9 | Bomb Pot: pull out before bomb | All players see consistent pot growth; player pulls out at ~8s; locked share visible in painful_reveal; bomb fires at hidden time; remaining players bust |
| 10 | Bomb Pot: last-puller wins Crown | 3 players; 2 pull out at 6s and 9s; 3rd at 12s; 3rd player receives crown_delta=1 + heat_delta=1 (or 0 with Heat Shield) |
| 11 | Bomb Pot: instabust at 5s | Run match repeatedly; ~5% of Bomb Pot rounds detonate at exactly the 5s window; nobody can pull out in time → all bust |
| 12 | Card Cannon: lock at 21 wins triple payout | Player draws and locks at exactly 21; chip_delta = wager × 3.0; crown_delta=1 if highest |
| 13 | Card Cannon: bust at 22+ loses wager | Player draws past 21; chip_delta = -wager; no Crown |
| 14 | Card Cannon: Insurance halves bust | Player loads Insurance in BET_LOADOUT; busts in Card Cannon; chip_delta = -wager/2 |
| 15 | 3-event rotation produces variety | 5-event Quick Clash visits at least 2 of the 3 events (uniform random; ~60% probability of all 3) |
```

- [ ] **Step 3: Commit**

```bash
git add docs/PLAYTEST_CHECKLIST.md
git commit -F - <<'EOF'
docs: append sub-project #5 playtest scenarios

7 new manual playtest scenarios covering Bomb Pot (pull-out + Crown +
instabust), Card Cannon (perfect 21 + bust + Insurance interop), and
3-event rotation variety.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Done

Sub-project #5 complete. Risk Royal MVP now has 3 events:

**Cumulative state after merge:**
- 12 power cards (sub-project #4), full bounty system, SHOP phase, 6 HUD widgets, 4-collaborator MatchController split
- 3 events: Rocket Clash (#3), Bomb Pot (#5), Card Cannon (#5)
- Test suite: 504 unit + 5 integration (453 baseline + 51 new unit + 1 new integration)

**Tag after Plan merges:** `subproject-5-complete`.

**Memory updates after merge:**
- Update `MEMORY.md` / `project_riskroyal.md` to reflect sub-project #5 fully shipped.
- Update `project_riskroyal_followups.md` to record any new carry-forwards (none anticipated — the spec's "Open Questions" are tuning concerns, not bugs).

**Carry-forwards / future sub-projects:**
- Sub-project #6 (House Twists): per-round overrides of `BOMB_POT_POT_GROWTH_PER_SEC`, `CARD_CANNON_TARGET_SCORE`, payout multipliers; smart event-pool selection (no-repeat / weighted).
- Sub-project #7 (Polish): Bomb Pot ticking audio + sparks, Card Cannon card-flip animations, deeper painful_reveal presentation.
- Face cards (J/Q/K) for Card Cannon: deferred per scope decision; would add intra-event sabotage mechanics.
- Bomb Pot danger band UI hints (cold/warm/critical from design doc §11.5): polish-pass item.
