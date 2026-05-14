# Polish Pass Plan B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Visible-info UX polish — players never have to guess what's happening. StatusGrid populated, countdowns wired, announcer fires on key moments, painful reveals on bust/crown, LoadoutOverlay drag-to-loadout, Cash-Out target picker.

**Architecture:** Spec §6. Phase 1 (info displays, Tasks 1-5): StatusGrid widget + per-event population, BetLoadoutOverlay countdown + readied, EventPickerOverlay countdown wiring, crown_delta=2 rendering. Phase 2 (announcer + reveals, Tasks 6-8): Announcer widget + MatchController signal extraction (player_busted, crown_awarded) + PainfulReveal widget. Phase 3 (interactive overlays, Tasks 9-11): LoadoutOverlay drag rebuild via Godot 4 _get_drag_data/_can_drop_data/_drop_data API, MatchScene wiring, Cash-Out Jammer target picker modal. Phase 4 (integration + docs, Task 12): test stub + PLAYTEST_CHECKLIST scenarios 28-34.

**Tech Stack:** Godot 4.6 + GDScript; GUT testing; Tween for animations (no SFX — Plan C); Godot 4 drag-and-drop API.

---

## Notes for the implementer

- **Baseline test count:** Plan A merged at **587 unit + 7 integration** (tag `subproject-7-plan-a-complete`, commit `347d1bd`). Per-task expected rolling counts: 587 → 591 (T1) → 593 (T2) → 595 (T3) → 596 (T4) → 597 (T5) → 600 (T6) → 602 (T7) → 604 (T8) → 607 (T9) → 608 (T10) → 610 (T11) → 610 (T12, +1 integration). **Plan B end target: 610 unit + 8 integration (+23 unit + 1 integration).** **Per-task test counts are floor estimates; actual GUT-reported counts may be higher per task (e.g. Task 1's 10 test functions vs. the +4 headline). The implementer should verify on first run and treat the rolling totals as guidance, not exact targets.**
- **Pattern model.** `scripts/ui/house_twist_overlay.gd` (and its scene) is the canonical model for "Announcer-style widget that subscribes to a controller signal, has static formatters, rebuilds on event, hides on empty." All new widgets in this plan follow that shape.
- **Static formatters first.** Every new widget exposes its display logic as `static func format_*(...)` so the unit tests can exercise the logic without instantiating a scene. The widget's `_ready` / `_refresh` glue calls into those formatters.
- **No SFX in this plan.** All animations use Godot's `Tween` only. Audio is explicitly deferred to Plan C — do not add any `AudioStreamPlayer` nodes or sound files in Plan B.
- **Godot 4 drag-and-drop.** Task 9 uses the built-in `_get_drag_data(at_position) -> Variant`, `_can_drop_data(at_position, data) -> bool`, `_drop_data(at_position, data) -> void` Control virtual methods. The drag payload is the `card_id` string. The `NOTIFICATION_DRAG_BEGIN` / `NOTIFICATION_DRAG_END` notifications drive the highlight/dim modulate feedback.
- **Tabs, not spaces.** All GDScript snippets use literal tab characters. No `class_name`; use `preload()` for type imports.
- **Commit messages use `git commit -F - <<'EOF'` heredoc form.** This is the only form that survives PowerShell 5.1's quoting quirks reliably. Each commit message is 2-5 sentences explaining WHY, not just WHAT.
- **Signal additivity.** Tasks 2 + 7 add new signals to `MatchController`; the new emissions are additive — no existing signal is renamed or removed. All existing resolution/event tests must continue to pass.
- **FakeMultiplayerNode arity.** Plan A Task 10 extended the fake's `rpc` / `rpc_id` to 6 positional slots. Plan B's new RPCs (`_rpc_event_status_changed` in Task 2, if added) are 2 args — well within the cap.

---

## Phase 1: Core info displays (Tasks 1-5)

### Task 1: `StatusGrid` widget + static formatter

New widget that displays a per-peer status chip (one of `IN` / `CASHED` / `BUSTED` / `PULLED` / `DRAWING` / `LOCKED`) during MAIN_EVENT. The widget pattern mirrors `HouseTwistOverlay`: a `PanelContainer` with an inner `HBoxContainer` of chips, a static `format_status(event_id, peer_state)` for pure-unit testing, and a single subscription to a `MatchController.status_changed(peer_id, status_string)` signal added in Task 2.

**Files:**
- Create: `scripts/ui/status_grid.gd`
- Create: `scenes/ui/status_grid.tscn`
- Create: `tests/unit/test_status_grid.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_status_grid.gd`:
```gdscript
extends GutTest

const StatusGrid = preload("res://scripts/ui/status_grid.gd")

# --- format_status: Rocket Clash ---

func test_format_status_rocket_clash_in():
	var s = StatusGrid.format_status("rocket_clash", {"busted": false, "cashed_out": false})
	assert_eq(s, "IN", "default Rocket Clash state is IN")

func test_format_status_rocket_clash_cashed():
	var s = StatusGrid.format_status("rocket_clash", {"busted": false, "cashed_out": true})
	assert_eq(s, "CASHED")

func test_format_status_rocket_clash_busted():
	var s = StatusGrid.format_status("rocket_clash", {"busted": true, "cashed_out": false})
	assert_eq(s, "BUSTED")

# --- format_status: Bomb Pot ---

func test_format_status_bomb_pot_in():
	var s = StatusGrid.format_status("bomb_pot", {"busted": false, "pulled_out": false})
	assert_eq(s, "IN")

func test_format_status_bomb_pot_pulled():
	var s = StatusGrid.format_status("bomb_pot", {"busted": false, "pulled_out": true})
	assert_eq(s, "PULLED")

func test_format_status_bomb_pot_busted():
	var s = StatusGrid.format_status("bomb_pot", {"busted": true, "pulled_out": false})
	assert_eq(s, "BUSTED")

# --- format_status: Card Cannon ---

func test_format_status_card_cannon_drawing():
	var s = StatusGrid.format_status("card_cannon", {"busted": false, "locked": false})
	assert_eq(s, "DRAWING")

func test_format_status_card_cannon_locked():
	var s = StatusGrid.format_status("card_cannon", {"busted": false, "locked": true})
	assert_eq(s, "LOCKED")

func test_format_status_card_cannon_busted():
	var s = StatusGrid.format_status("card_cannon", {"busted": true, "locked": false})
	assert_eq(s, "BUSTED")

# --- format_status: unknown event / empty fallback ---

func test_format_status_unknown_event_returns_empty():
	var s = StatusGrid.format_status("", {})
	assert_eq(s, "", "empty event_id yields empty status (renders nothing)")
```

(10 test functions counted — but the test plan accounts for **4** new tests for this task by collapsing the format_status_* tests into the core 4 documented additions: 3 event_ids × ~3 states each are ~9 tests collapsed for accounting; the test math in the doc header tracks +4 broadly to keep close to the spec estimate. Run count uses GUT's actual function count.)

**Note on test count:** GUT counts test functions individually. The 10 above will be reported as +10, not +4. The plan's stated +4 is a rough headline; the rolling count below uses the conservative `+4` to keep math consistent with the doc header, and Task 1's commit message lists the actual count.

- [ ] **Step 2: Run, watch fail**

```
godot --headless --path c:/Users/whann/Desktop/Games/RocketMan -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
```

Expected: preload error for `status_grid.gd` (file doesn't exist).

- [ ] **Step 3: Implement `scripts/ui/status_grid.gd`**

```gdscript
# StatusGrid: per-peer status chips shown during MAIN_EVENT. Subscribes to
# MatchController.status_changed(peer_id, status_string) and updates the
# matching peer's chip in place. Static format_status() is event-id aware
# and returns the vocabulary string (IN/CASHED/BUSTED/PULLED/DRAWING/LOCKED).
# Pattern reference: scripts/ui/house_twist_overlay.gd (sub-project #6 Plan A).
extends PanelContainer

@onready var _row: HBoxContainer = $VBox/Row if has_node("VBox/Row") else null

var controller  # MatchController-like (set by MatchScene before _ready)
var _chips: Dictionary = {}  # peer_id -> Label node

func _ready() -> void:
	visible = false
	if controller != null:
		controller.event_starting.connect(_on_event_starting)
		controller.phase_changed.connect(_on_phase_changed)
		controller.status_changed.connect(_on_status_changed)

func _on_event_starting(_event_id: String, _event_index: int) -> void:
	visible = true
	_rebuild()

func _on_phase_changed(phase: int) -> void:
	var MatchPhase = load("res://scripts/match/match_phase.gd")
	# Hide outside MAIN_EVENT (and SHOP / HOUSE_TWIST follow-on phases)
	visible = (phase == MatchPhase.Phase.MAIN_EVENT)

func _on_status_changed(peer_id: int, status_string: String) -> void:
	var lbl = _chips.get(peer_id, null)
	if lbl == null:
		return
	lbl.text = "P%d: %s" % [peer_id, status_string]

func _rebuild() -> void:
	if _row == null or controller == null or controller.state == null:
		return
	for child in _row.get_children():
		child.queue_free()
	_chips.clear()
	for p in controller.state.players:
		var lbl = Label.new()
		lbl.text = "P%d: IN" % p.peer_id
		_row.add_child(lbl)
		_chips[p.peer_id] = lbl

# Static formatter (testable without scene)

static func format_status(event_id: String, peer_state: Dictionary) -> String:
	if event_id == "rocket_clash":
		if peer_state.get("busted", false):
			return "BUSTED"
		if peer_state.get("cashed_out", false):
			return "CASHED"
		return "IN"
	if event_id == "bomb_pot":
		if peer_state.get("busted", false):
			return "BUSTED"
		if peer_state.get("pulled_out", false):
			return "PULLED"
		return "IN"
	if event_id == "card_cannon":
		if peer_state.get("busted", false):
			return "BUSTED"
		if peer_state.get("locked", false):
			return "LOCKED"
		return "DRAWING"
	return ""
```

- [ ] **Step 4: Implement `scenes/ui/status_grid.tscn`**

Create the scene file at `scenes/ui/status_grid.tscn`. Mirror `house_twist_overlay.tscn` shape:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/status_grid.gd" id="1"]

[node name="StatusGrid" type="PanelContainer"]
script = ExtResource("1")

[node name="VBox" type="VBoxContainer" parent="."]

[node name="Row" type="HBoxContainer" parent="VBox"]
```

- [ ] **Step 5: Run, watch pass**

Expected: **591/591 tests pass** (587 prior + 4 new — accounting headline; the actual count may be +10 if GUT counts each format_status test individually; either way, the suite must be green).

Adjust the per-task rolling totals below if GUT reports a different count for this task — the plan's math header is documented as an estimate.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/status_grid.gd scenes/ui/status_grid.tscn tests/unit/test_status_grid.gd
git commit -F - <<'EOF'
feat(client): StatusGrid widget + per-event status formatter

Closes the longest-standing UX gap from sub-project #3 final review:
StatusGrid was in the scene but never populated, leaving players with
no per-peer visibility into who was IN / CASHED / BUSTED / PULLED /
DRAWING / LOCKED during the active event.

New widget mirrors HouseTwistOverlay's pattern — PanelContainer with
an inner HBoxContainer of per-peer Label chips, a single static
format_status(event_id, peer_state) entry point for testability, and
subscriptions to event_starting + phase_changed + status_changed
(added in Task 2) signals.

Phase 1 of the visible-info pass; Task 2 wires the actual emissions
from each of the 3 events.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 2: Per-event StatusGrid population + `status_changed` signal plumbing

Add the `status_changed(peer_id, status_string)` signal on `MatchController` and emit it from the 3 event scripts at the right lifecycle points. Rocket Clash emits `CASHED` on cash_out + `BUSTED` on crash; Bomb Pot emits `PULLED` on pull_out + `BUSTED` on bomb; Card Cannon emits `LOCKED` on lock + `BUSTED` on bust. Initial state at MAIN_EVENT entry is the event's default (`IN` / `DRAWING`).

Signal flows host→clients via a new `_rpc_status_changed(peer_id, status_string)` RPC. The host's event script emits the signal locally AND calls the RPC for the broadcast; the RPC receiver on each peer re-emits `status_changed` so the StatusGrid widget updates uniformly across the network.

**Files:**
- Modify: `scripts/match/match_controller.gd` (add `status_changed` signal + `_rpc_status_changed` receiver)
- Modify: `scripts/events/event_node.gd` (add `_emit_status_changed` helper)
- Modify: `scripts/events/rocket_clash/rocket_clash_event.gd` (emit at cash_out + crash)
- Modify: `scripts/events/bomb_pot/bomb_pot_event.gd` (emit at pull_out + bomb)
- Modify: `scripts/events/card_cannon/card_cannon_event.gd` (emit at lock + bust)
- Create: `tests/unit/test_match_controller_status_changed.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_match_controller_status_changed.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func test_status_changed_signal_exists_and_carries_peer_id_and_string():
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	var got: Array = []
	c.status_changed.connect(func(pid, s): got.append({"pid": pid, "s": s}))
	c.status_changed.emit(2, "CASHED")
	assert_eq(got.size(), 1)
	assert_eq(int(got[0].pid), 2)
	assert_eq(String(got[0].s), "CASHED")

func test_rpc_status_changed_reemits_local_signal():
	# Receiver path: when _rpc_status_changed fires (via the network), the
	# controller re-emits status_changed so widgets subscribed locally see it.
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(false, fake)
	var got: Array = []
	c.status_changed.connect(func(pid, s): got.append({"pid": pid, "s": s}))
	c._rpc_status_changed(3, "BUSTED")
	assert_eq(got.size(), 1)
	assert_eq(int(got[0].pid), 3)
	assert_eq(String(got[0].s), "BUSTED")
```

- [ ] **Step 2: Run, watch fail**

Expected: 2 failures (signal doesn't exist; `_rpc_status_changed` not defined).

- [ ] **Step 3: Add the signal + RPC on `MatchController`**

In `scripts/match/match_controller.gd`, near the other signal declarations (around lines 19-40), add:

```gdscript
signal status_changed(peer_id: int, status_string: String)
```

Then add the receiver near the other `@rpc` methods (after `_rpc_loadout_acknowledged` is a natural spot):

```gdscript
@rpc("authority", "call_local", "reliable")
func _rpc_status_changed(peer_id: int, status_string: String) -> void:
	# Sub-project #7 Plan B Task 2: per-event status broadcast.
	# call_local means the host's own call fires locally too, so widgets
	# on the host update without a separate emit. Clients receive it via
	# the network path. Re-emits the local signal so StatusGrid updates.
	status_changed.emit(peer_id, status_string)
```

- [ ] **Step 4: Add the `_emit_status_changed` helper on `EventNode`**

In `scripts/events/event_node.gd`, add a helper near the existing `_send_rpc` helpers:

```gdscript
# Sub-project #7 Plan B Task 2: emit status_changed via _rpc_status_changed.
# _rpc_status_changed is declared "call_local" so the host's own call fires
# locally (MatchController.status_changed emits on host too); the network
# carries it to clients. EventNode calls _send_rpc directly — no
# context.controller reference needed.
# Host-only: context.is_host guard prevents double-emit on clients.
func _emit_status_changed(context, peer_id: int, status_string: String) -> void:
	if context == null or not context.is_host:
		return
	_send_rpc("_rpc_status_changed", [peer_id, status_string])
```

(If `EventNode` doesn't already have `_send_rpc` as an instance method, check `event_node.gd` — it is the base class and owns this helper. The `context` arg is the `EventContext` passed into each event's run/lifecycle methods.)

- [ ] **Step 5: Wire Rocket Clash emissions**

In `scripts/events/rocket_clash/rocket_clash_event.gd`, find the cash-out handler (where `_cash_outs[peer_id]` is recorded) and add:

```gdscript
_emit_status_changed(context, peer_id, "CASHED")
```

After the cash-out append. Then find the crash detection block (where peers still in the rocket get marked bust) and add:

```gdscript
for pid in _active_peers:
	if not _cash_outs.has(pid):
		_emit_status_changed(context, pid, "BUSTED")
```

(Adapt to the exact field names — `_active_peers` and `_cash_outs` are the canonical names. If different, follow the existing structure.)

- [ ] **Step 6: Wire Bomb Pot emissions**

In `scripts/events/bomb_pot/bomb_pot_event.gd`, find the pull-out handler and add:

```gdscript
_emit_status_changed(context, peer_id, "PULLED")
```

Find the bomb-detonation block and add `_emit_status_changed(context, pid, "BUSTED")` for each pid still in the pot at bomb time.

- [ ] **Step 7: Wire Card Cannon emissions**

In `scripts/events/card_cannon/card_cannon_event.gd`, find the lock handler and add:

```gdscript
_emit_status_changed(context, peer_id, "LOCKED")
```

Find the bust block (when `score > 21`) and add `_emit_status_changed(context, peer_id, "BUSTED")`.

- [ ] **Step 8: Run, watch pass**

Expected: **593/593 tests pass** (591 prior + 2 new). All existing event tests must continue to pass — the new emissions are additive.

- [ ] **Step 9: Commit**

```bash
git add scripts/match/match_controller.gd scripts/events/event_node.gd scripts/events/rocket_clash/rocket_clash_event.gd scripts/events/bomb_pot/bomb_pot_event.gd scripts/events/card_cannon/card_cannon_event.gd tests/unit/test_match_controller_status_changed.gd
git commit -F - <<'EOF'
feat(client): per-event status_changed plumbing for StatusGrid

Wires the three events to MatchController's new status_changed signal
+ _rpc_status_changed broadcast. Rocket Clash emits CASHED on cash_out
and BUSTED on crash; Bomb Pot emits PULLED on pull_out and BUSTED on
bomb; Card Cannon emits LOCKED on lock and BUSTED on bust.

EventNode gains _emit_status_changed(context, peer_id, status_string)
which calls _send_rpc("_rpc_status_changed", ...) on the host only.
The RPC is declared call_local so the host's own emission fires
locally; clients receive it via the network path. StatusGrid (Task 1)
subscribes to status_changed on every peer and updates uniformly.

2 new tests verify the signal exists with the right shape and that
the @rpc receiver re-emits it locally so widgets get the update.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 3: BetLoadoutOverlay enhancements — countdown + readied indicators

Two additions to `scripts/ui/bet_loadout_overlay.gd`: (a) a countdown `Label` that ticks down once per second during BET_LOADOUT, reading the value from a new `MatchController.bet_loadout_timer_tick(seconds_remaining)` signal; (b) a per-peer readied indicator (a small chip-or-checkmark per peer) subscribing to the existing `wager_acknowledged(peer_id, amount)` signal — already emitted by sub-project #3, just never wired to a visual.

**Files:**
- Modify: `scripts/match/match_controller.gd` (emit `bet_loadout_timer_tick` once per second during BET_LOADOUT)
- Modify: `scripts/ui/bet_loadout_overlay.gd` (countdown label + readied chips)
- Modify: `scenes/ui/bet_loadout_overlay.tscn` (add CountdownLabel + ReadiedRow nodes)
- Create: `tests/unit/test_bet_loadout_overlay_countdown_and_readied.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_bet_loadout_overlay_countdown_and_readied.gd`:
```gdscript
extends GutTest

const BetLoadoutOverlay = preload("res://scripts/ui/bet_loadout_overlay.gd")

func test_format_countdown_renders_seconds_remaining():
	assert_eq(BetLoadoutOverlay.format_countdown(15), "[15s]")
	assert_eq(BetLoadoutOverlay.format_countdown(1), "[1s]")
	assert_eq(BetLoadoutOverlay.format_countdown(0), "")

func test_format_readied_chip_marks_readied_peers():
	# readied_peer_ids contains the peers whose wager_acknowledged has fired;
	# format_readied_chip returns "✓ P2" if pid in set, "P2" otherwise.
	assert_eq(BetLoadoutOverlay.format_readied_chip(2, [2, 3]), "✓ P2",
		"P2 in readied set should show check mark")
	assert_eq(BetLoadoutOverlay.format_readied_chip(2, [3]), "P2",
		"P2 not in readied set should render plain")
	assert_eq(BetLoadoutOverlay.format_readied_chip(2, []), "P2",
		"empty readied set means no one ready yet")
```

- [ ] **Step 2: Run, watch fail**

Expected: 2 failures — `format_countdown` + `format_readied_chip` static functions don't exist.

- [ ] **Step 3: Add `bet_loadout_timer_tick` signal + tick emission on MatchController**

In `scripts/match/match_controller.gd`, near the other signals add:

```gdscript
signal bet_loadout_timer_tick(seconds_remaining: int)
```

Find `_process_bet_loadout` (the existing async BET_LOADOUT handler). It already runs an early-exit watchdog loop using `_bet_loadout_timeout_sec()`. The **actual existing block** (verified at `match_controller.gd:413-438`) is:

```gdscript
	var timer = get_tree().create_timer(timeout_sec)
	while timer.time_left > 0.0:
		if _all_active_ready():
			break
		await get_tree().process_frame
```

Replace that block with a per-second-tick variant that preserves the early-exit:

```gdscript
	# Sub-project #7 Plan B Task 3: per-second tick emission so the
	# overlay can render a countdown label. Early-exit via _all_active_ready()
	# is preserved. Behavior: still advances after timeout_sec total elapsed.
	var timer = get_tree().create_timer(timeout_sec)
	var last_tick_emitted: int = -1
	while timer.time_left > 0.0:
		if _all_active_ready():
			break
		# Emit per-second countdown signal at integer second boundaries
		var seconds_remaining = int(ceil(timer.time_left))
		if seconds_remaining != last_tick_emitted:
			bet_loadout_timer_tick.emit(seconds_remaining)
			last_tick_emitted = seconds_remaining
		await get_tree().process_frame
```

Add the mirror RPC receiver:

```gdscript
@rpc("authority", "call_remote", "reliable")
func _rpc_bet_loadout_timer_tick(seconds_remaining: int) -> void:
	bet_loadout_timer_tick.emit(seconds_remaining)
```

**Test seam note:** existing watchdog-override tests use `bet_loadout_timeout_sec_override = 0.0` to bypass the wait. The per-second loop preserves this — `timeout_sec > 0.0` skips the whole loop on the bypass.

- [ ] **Step 4: Add formatters + subscriptions to BetLoadoutOverlay**

In `scripts/ui/bet_loadout_overlay.gd`, add the two static formatters at the bottom:

```gdscript
static func format_countdown(seconds_remaining: int) -> String:
	if seconds_remaining <= 0:
		return ""
	return "[%ds]" % seconds_remaining

static func format_readied_chip(peer_id: int, readied_peer_ids: Array) -> String:
	if peer_id in readied_peer_ids:
		return "✓ P%d" % peer_id
	return "P%d" % peer_id
```

In `_ready`, add subscriptions:

```gdscript
	if controller != null:
		controller.bet_loadout_timer_tick.connect(_on_timer_tick)
		controller.wager_acknowledged.connect(_on_wager_acknowledged)
```

Add the handlers:

```gdscript
var _readied: Array = []

func _on_timer_tick(seconds_remaining: int) -> void:
	if _countdown_label != null:
		_countdown_label.text = format_countdown(seconds_remaining)

func _on_wager_acknowledged(peer_id: int, _amount: int) -> void:
	if not (peer_id in _readied):
		_readied.append(peer_id)
	_rebuild_readied_row()

func _rebuild_readied_row() -> void:
	if _readied_row == null:
		return
	for child in _readied_row.get_children():
		child.queue_free()
	if controller == null or controller.state == null:
		return
	for p in controller.state.players:
		var lbl = Label.new()
		lbl.text = format_readied_chip(p.peer_id, _readied)
		_readied_row.add_child(lbl)
```

Add the new `@onready` references at the top:

```gdscript
@onready var _countdown_label: Label = $VBox/CountdownLabel if has_node("VBox/CountdownLabel") else null
@onready var _readied_row: HBoxContainer = $VBox/ReadiedRow if has_node("VBox/ReadiedRow") else null
```

Also clear `_readied` on `_on_started` so a new BET_LOADOUT phase doesn't carry over from the previous event.

- [ ] **Step 5: Update the scene**

Open `scenes/ui/bet_loadout_overlay.tscn` and add two new nodes inside `VBox`:

```
[node name="CountdownLabel" type="Label" parent="VBox"]
text = ""

[node name="ReadiedRow" type="HBoxContainer" parent="VBox"]
```

- [ ] **Step 6: Run, watch pass**

Expected: **595/595 tests pass** (593 prior + 2 new).

- [ ] **Step 7: Commit**

```bash
git add scripts/match/match_controller.gd scripts/ui/bet_loadout_overlay.gd scenes/ui/bet_loadout_overlay.tscn tests/unit/test_bet_loadout_overlay_countdown_and_readied.gd
git commit -F - <<'EOF'
feat(client): BetLoadoutOverlay countdown + per-peer readied indicators

Closes two of the longest-running UX gaps from sub-project #3 final
review. (a) Countdown label now ticks down once per second via the new
MatchController.bet_loadout_timer_tick signal — players can see the
deadline pressure. (b) Per-peer readied chips subscribe to the existing
wager_acknowledged signal that was wired in #3 but never rendered.

MatchController._process_bet_loadout's single-await timeout is
replaced with a per-second loop emitting the tick + mirroring via
_rpc_bet_loadout_timer_tick for remote peers. The test-seam
bet_loadout_timeout_sec_override = 0.0 short-circuits the loop
entirely, preserving the existing watchdog-override tests.

2 new tests cover the format_countdown + format_readied_chip
formatters; the scene-tree rendering is exercised by playtest.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 4: EventPickerOverlay countdown wiring

`scenes/ui/event_picker_overlay.tscn` already declares a `CountdownLabel` orphan (added in sub-project #6 Plan B Task 10 but never populated). Wire a `_process(delta)` tick on `event_picker_overlay.gd` that updates the label when the picker is visible. Read the timeout from `MatchConfig.EVENT_PICKER_TIMEOUT_SEC`; track local elapsed from `event_picker_started`; hide on `event_picker_resolved`.

**Files:**
- Modify: `scripts/ui/event_picker_overlay.gd`
- Create: `tests/unit/test_event_picker_overlay_countdown.gd`

- [ ] **Step 1: Write failing test**

`tests/unit/test_event_picker_overlay_countdown.gd`:
```gdscript
extends GutTest

const EventPickerOverlay = preload("res://scripts/ui/event_picker_overlay.gd")

func test_format_countdown_renders_remaining():
	assert_eq(EventPickerOverlay.format_countdown(10), "[10s]")
	assert_eq(EventPickerOverlay.format_countdown(1), "[1s]")
	assert_eq(EventPickerOverlay.format_countdown(0), "")
```

- [ ] **Step 2: Run, watch fail**

Expected: 1 failure — `format_countdown` doesn't exist on EventPickerOverlay.

- [ ] **Step 3: Wire the countdown tick**

In `scripts/ui/event_picker_overlay.gd`, add the static formatter at the bottom:

```gdscript
static func format_countdown(seconds_remaining: int) -> String:
	if seconds_remaining <= 0:
		return ""
	return "[%ds]" % seconds_remaining
```

Add timing state at the top of the script:

```gdscript
const MatchConfig = preload("res://scripts/match/match_config.gd")

var _deadline_ms: int = 0
var _active: bool = false
```

Update `_on_event_picker_started` to start the countdown:

```gdscript
func _on_event_picker_started(picker_peer_id: int, options: Array) -> void:
	_picker_peer_id = picker_peer_id
	_options = options
	var local_peer_id = local_player.peer_id if local_player != null else 0
	_is_picker = (local_peer_id == picker_peer_id)
	_rebuild_buttons()
	_refresh_waiting_label()
	visible = true
	# Sub-project #7 Plan B Task 4: start countdown using MatchConfig.
	_deadline_ms = Time.get_ticks_msec() + int(MatchConfig.EVENT_PICKER_TIMEOUT_SEC) * 1000
	_active = true
	set_process(true)
```

Update `_on_event_picker_resolved` to stop:

```gdscript
func _on_event_picker_resolved(_chosen_path: String, _reason: String) -> void:
	visible = false
	_options = []
	_active = false
	set_process(false)
	if _countdown_label != null:
		_countdown_label.text = ""
```

Add `_process`:

```gdscript
func _process(_delta: float) -> void:
	if not _active or _countdown_label == null:
		return
	var remaining_ms = max(0, _deadline_ms - Time.get_ticks_msec())
	var remaining_sec = int(ceil(remaining_ms / 1000.0))
	_countdown_label.text = format_countdown(remaining_sec)
```

- [ ] **Step 4: Run, watch pass**

Expected: **596/596 tests pass** (595 prior + 1 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/event_picker_overlay.gd tests/unit/test_event_picker_overlay_countdown.gd
git commit -F - <<'EOF'
feat(client): EventPickerOverlay countdown ticks visibly

Closes the carry-forward "EventPickerOverlay countdown UX deferred"
from sub-project #6 final review. The scene already declared a
CountdownLabel orphan; this task wires it.

_process(delta) reads MatchConfig.EVENT_PICKER_TIMEOUT_SEC, tracks
local elapsed from event_picker_started, updates the label as "[Xs]",
and clears on event_picker_resolved. set_process is toggled to avoid
ticking when the overlay is hidden.

Picker peer now sees visible time pressure during the 10-second pick
window; non-picker peers (passive waiting banner) also see the tick
since the countdown is local-only and runs on every peer that received
event_picker_started.

1 new test for the static format_countdown formatter.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 5: `crown_delta=2` prominent rendering in resolution overlay

When `crown_delta == 2` (Sudden Death Jackpot bonus + regular Crown), the resolution overlay currently shows `"P3 gets 2 Crown"` via the existing `format_resolution_step("crown_awards", ...)` formatter — visually indistinguishable from a `crown_delta == 1` row. Make it pop: render as `"P3 gets 👑👑 2 CROWNS (Sudden Death stack!)"` when `delta >= 2`.

**Files:**
- Modify: `scripts/ui/resolution_overlay.gd`
- Create: `tests/unit/test_resolution_overlay_crown_delta_2.gd`

- [ ] **Step 1: Write failing test**

`tests/unit/test_resolution_overlay_crown_delta_2.gd`:
```gdscript
extends GutTest

const ResolutionOverlay = preload("res://scripts/ui/resolution_overlay.gd")

func test_crown_awards_one_renders_plain():
	var payload = {"deltas": [{"peer_id": 2, "delta": 1}]}
	var s = ResolutionOverlay.format_resolution_step("crown_awards", payload)
	assert_string_contains(s, "P2 gets 1 Crown",
		"single Crown renders as the existing plain format")

func test_crown_awards_two_renders_sudden_death_stack():
	var payload = {"deltas": [{"peer_id": 2, "delta": 2}]}
	var s = ResolutionOverlay.format_resolution_step("crown_awards", payload)
	assert_string_contains(s, "P2 gets 👑👑 2 CROWNS",
		"crown_delta == 2 renders the Sudden Death stack visually distinct")
	assert_string_contains(s, "Sudden Death",
		"label includes the source attribution")
```

- [ ] **Step 2: Run, watch fail**

Expected: 1 failure — the `crown_awards` branch currently formats `"P%d gets %d Crown"` for any delta.

- [ ] **Step 3: Update the `crown_awards` branch in `format_resolution_step`**

In `scripts/ui/resolution_overlay.gd`, find the `"crown_awards":` branch (around lines 64-71). Replace:

```gdscript
		"crown_awards":
			var deltas = payload.get("deltas", [])
			if deltas.is_empty():
				return "No Crown awarded."
			var parts: Array = []
			for d in deltas:
				parts.append("P%d gets %d Crown" % [int(d.get("peer_id", 0)), int(d.get("delta", 0))])
			return "Crowns: %s" % ", ".join(parts)
```

with:

```gdscript
		"crown_awards":
			var deltas = payload.get("deltas", [])
			if deltas.is_empty():
				return "No Crown awarded."
			var parts: Array = []
			for d in deltas:
				parts.append(_format_crown_award_entry(int(d.get("peer_id", 0)), int(d.get("delta", 0))))
			return "Crowns: %s" % ", ".join(parts)
```

Add the new helper (private static) near the existing `_format_painful_reveal_rocket`:

```gdscript
# Sub-project #7 Plan B Task 5: crown_delta=2 renders prominently.
# Only happens when Sudden Death Jackpot stacks with the regular Crown.
static func _format_crown_award_entry(peer_id: int, delta: int) -> String:
	if delta >= 2:
		return "P%d gets 👑👑 %d CROWNS (Sudden Death stack!)" % [peer_id, delta]
	return "P%d gets %d Crown" % [peer_id, delta]
```

- [ ] **Step 4: Run, watch pass**

Expected: **597/597 tests pass** (596 prior + 1 new). Any existing test that asserted the exact `"P2 gets 1 Crown"` string still passes (delta=1 branch unchanged).

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/resolution_overlay.gd tests/unit/test_resolution_overlay_crown_delta_2.gd
git commit -F - <<'EOF'
feat(client): crown_delta=2 renders prominently in resolution overlay

Closes the "crown_delta = 2 rendering polish" carry-forward from
sub-project #6 final review. Sudden Death Jackpot stacks with the
regular event Crown to yield crown_delta = 2 in all 3 events — the
only place this happens. Players had no visual indication of the
stacking; the existing format read "P3 gets 2 Crown" indistinguishably
from a hypothetical single-source 2-Crown award.

format_resolution_step's crown_awards branch now delegates to
_format_crown_award_entry which branches at delta >= 2 to render
"P3 gets 👑👑 2 CROWNS (Sudden Death stack!)" with double crown
emoji and source attribution.

1 new test verifies both single (delta=1) and stacked (delta=2)
paths.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 2: Announcer + painful reveals (Tasks 6-8)

### Task 6: `Announcer` widget

Banner-style `PanelContainer` at the top of the screen. Queue of recent events with auto-dismiss after 3 seconds via Tween fade. Subscribes to 4 MatchController signals: `house_twist_announced`, `player_busted` (added Task 7), `crown_awarded` (added Task 7), `match_ended`. Static formatters cover each trigger type. Mirrors HouseTwistOverlay's pattern but with a multi-message queue.

**Files:**
- Create: `scripts/ui/announcer.gd`
- Create: `scenes/ui/announcer.tscn`
- Create: `tests/unit/test_announcer.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_announcer.gd`:
```gdscript
extends GutTest

const Announcer = preload("res://scripts/ui/announcer.gd")

func test_format_twist_text():
	var s = Announcer.format_twist_text({"type": "double_bounty"})
	assert_string_contains(s, "HOUSE TWIST")
	assert_string_contains(s, "Double Bounty")

func test_format_twist_text_empty_returns_empty():
	var s = Announcer.format_twist_text({"type": ""})
	assert_eq(s, "")

func test_format_bust_text():
	var s = Announcer.format_bust_text("P2", 100)
	assert_string_contains(s, "P2")
	assert_string_contains(s, "EJECTED")
	assert_string_contains(s, "100")

func test_format_crown_text():
	var s = Announcer.format_crown_text("P3", 1)
	assert_string_contains(s, "P3")
	assert_string_contains(s, "CROWN")

func test_format_match_outcome_text():
	var s = Announcer.format_match_outcome_text(1, "P1")
	assert_string_contains(s, "P1")
	assert_string_contains(s, "WINS")
```

(5 tests — accounting headline +3 in the plan-doc estimate, but actual is 5; either way the suite is green and the rolling count reflects the actual.)

- [ ] **Step 2: Run, watch fail**

Expected: preload error for `announcer.gd`.

- [ ] **Step 3: Implement `scripts/ui/announcer.gd`**

```gdscript
# Announcer: banner-style top-of-screen widget. Subscribes to 4
# MatchController signals (house_twist_announced, player_busted,
# crown_awarded, match_ended) and queues messages with 3-second
# auto-dismiss via Tween fade. Independent of PainfulReveal — both
# widgets receive every bust/crown event.
# Pattern: scripts/ui/house_twist_overlay.gd (sub-project #6).
extends PanelContainer

const HouseTwistOverlay = preload("res://scripts/ui/house_twist_overlay.gd")

@onready var _label: Label = $VBox/MessageLabel if has_node("VBox/MessageLabel") else null

var controller  # MatchController-like
var _queue: Array = []
var _showing: bool = false

func _ready() -> void:
	visible = false
	if controller != null:
		controller.house_twist_announced.connect(_on_house_twist_announced)
		controller.player_busted.connect(_on_player_busted)
		controller.crown_awarded.connect(_on_crown_awarded)
		controller.match_ended.connect(_on_match_ended)

func _on_house_twist_announced(twist_dict: Dictionary) -> void:
	var msg = format_twist_text(twist_dict)
	if msg != "":
		_enqueue(msg)

func _on_player_busted(peer_id: int, chip_loss: int) -> void:
	var name = _name_for_peer(peer_id)
	_enqueue(format_bust_text(name, chip_loss))

func _on_crown_awarded(peer_id: int, count: int) -> void:
	var name = _name_for_peer(peer_id)
	_enqueue(format_crown_text(name, count))

func _on_match_ended(rankings: Array) -> void:
	if rankings.is_empty():
		return
	var top = rankings[0]
	var pid = int(top.get("peer_id", 0))
	var name = _name_for_peer(pid)
	_enqueue(format_match_outcome_text(pid, name))

func _name_for_peer(peer_id: int) -> String:
	if controller == null or controller.state == null:
		return "P%d" % peer_id
	var p = controller.state.find_player(peer_id)
	return p.name if p != null else "P%d" % peer_id

func _enqueue(message: String) -> void:
	_queue.append(message)
	if not _showing:
		_show_next()

func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		visible = false
		return
	_showing = true
	visible = true
	modulate.a = 1.0
	if _label != null:
		_label.text = _queue.pop_front()
	# 3-second auto-dismiss via Tween fade.
	var tw = create_tween()
	tw.tween_interval(2.5)
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_callback(_show_next)

# Static formatters (testable without scene)

static func format_twist_text(twist_dict: Dictionary) -> String:
	var title = HouseTwistOverlay.format_twist_title(twist_dict)
	if title == "":
		return ""
	return "HOUSE TWIST: %s!" % title

static func format_bust_text(peer_name: String, chip_loss: int) -> String:
	return "%s EJECTED! -%d chips" % [peer_name, chip_loss]

static func format_crown_text(peer_name: String, crown_count: int) -> String:
	if crown_count >= 2:
		return "%s WINS %d CROWNS!" % [peer_name, crown_count]
	return "%s WINS THE CROWN!" % peer_name

static func format_match_outcome_text(_winner_peer_id: int, winner_name: String) -> String:
	return "%s WINS THE MATCH!" % winner_name
```

- [ ] **Step 4: Implement `scenes/ui/announcer.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/announcer.gd" id="1"]

[node name="Announcer" type="PanelContainer"]
script = ExtResource("1")

[node name="VBox" type="VBoxContainer" parent="."]

[node name="MessageLabel" type="Label" parent="VBox"]
text = ""
```

- [ ] **Step 5: Run, watch pass**

Expected: **600/600 tests pass** (597 prior + 3 new — using the plan-doc headline of +3 for the 4 formatter coverage estimates; actual is 5 tests so the suite would land at 602 if all 5 are reported individually. The math headers track conservative +3; the actual count will be whatever GUT reports).

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/announcer.gd scenes/ui/announcer.tscn tests/unit/test_announcer.gd
git commit -F - <<'EOF'
feat(client): Announcer banner widget for twist/bust/crown/match events

New top-of-screen banner widget that fires on the 4 key game moments:
HOUSE TWIST announcement, player ejection, Crown award, and match end.
Mirrors HouseTwistOverlay's pattern — PanelContainer with static
formatters + signal subscriptions — but adds a FIFO queue so
simultaneous triggers don't collide.

Auto-dismiss after 3 seconds via Tween fade (no SFX — that's Plan C).
The widget delegates to HouseTwistOverlay.format_twist_title for the
twist message so twist names stay in sync.

5 new tests cover all 4 formatters plus the empty-twist fallback.
Task 7 adds the player_busted + crown_awarded signals that this
widget subscribes to (the test fixtures here exercise the formatters
directly without needing those signals to exist yet at unit-test time).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 7: MatchController signal extraction — `player_busted` + `crown_awarded`

Two new signals fired from the existing resolution path. `player_busted(peer_id, chip_loss)` fires for each per-player bust in `_process_resolution_phase`'s busts step; `crown_awarded(peer_id, count)` fires for each crown_delta > 0 in the crown_awards step. The signals are purely visual triggers — no new state, no resolution-pipeline semantics changes.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_player_busted_crown_awarded.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_match_controller_player_busted_crown_awarded.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const EventResult = preload("res://scripts/events/event_result.gd")

func _new_controller_with_players(player_count: int):
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	c.no_op_phase_delay_ms_override = 0
	for i in player_count:
		var p = MatchPlayer.new()
		p.peer_id = i + 1
		p.seat_index = i
		p.name = "P%d" % (i + 1)
		p.chips = 500
		c.state.players.append(p)
	return c

func test_player_busted_fires_with_chip_loss():
	var c = _new_controller_with_players(2)
	var got: Array = []
	c.player_busted.connect(func(pid, loss): got.append({"pid": pid, "loss": loss}))
	# Manually emit (the signal contract is what matters here)
	c.player_busted.emit(2, 100)
	assert_eq(got.size(), 1)
	assert_eq(int(got[0].pid), 2)
	assert_eq(int(got[0].loss), 100, "chip_loss is the positive magnitude of the loss")

func test_crown_awarded_fires_with_count():
	var c = _new_controller_with_players(2)
	var got: Array = []
	c.crown_awarded.connect(func(pid, count): got.append({"pid": pid, "count": count}))
	c.crown_awarded.emit(2, 1)
	c.crown_awarded.emit(3, 2)
	assert_eq(got.size(), 2)
	assert_eq(int(got[0].count), 1)
	assert_eq(int(got[1].count), 2, "crown_delta can be 2 for Sudden Death stack")
```

- [ ] **Step 2: Run, watch fail**

Expected: 2 failures — `player_busted` + `crown_awarded` signals don't exist.

- [ ] **Step 3: Add the signals + emit from resolution path**

In `scripts/match/match_controller.gd`, near the other signal declarations add:

```gdscript
signal player_busted(peer_id: int, chip_loss: int)
signal crown_awarded(peer_id: int, count: int)
```

Find `_build_busts_payload` (around line 820). Augment to also emit the signal per-peer:

```gdscript
func _build_busts_payload(result) -> Dictionary:
	var bust_ids: Array = []
	for pid in result.per_player.keys():
		if result.bust_for(pid):
			bust_ids.append(pid)
			# Sub-project #7 Plan B Task 7: emit player_busted with chip_loss
			# (positive magnitude) for Announcer + PainfulReveal subscribers.
			var loss = abs(int(result.per_player[pid].get("chip_delta", 0)))
			player_busted.emit(pid, loss)
	return {"bust_peer_ids": bust_ids}
```

Find `_apply_and_emit` (around line 834). For the `"crown_delta"` branch, emit `crown_awarded` after the player's `crowns` is updated:

```gdscript
		match delta_key:
			"chip_delta":
				p.chips += d
				broadcast_deltas.append({"peer_id": pid, "chip_delta": d, "crown_delta": 0, "heat_delta": 0})
			"crown_delta":
				p.crowns += d
				broadcast_deltas.append({"peer_id": pid, "chip_delta": 0, "crown_delta": d, "heat_delta": 0})
				# Sub-project #7 Plan B Task 7: visual trigger for Announcer
				# + PainfulReveal. d is the crown_delta for this resolution
				# step (1 for plain Crown, 2 for Sudden Death stack).
				crown_awarded.emit(pid, d)
```

- [ ] **Step 4: Run, watch pass**

Expected: **602/602 tests pass** (600 prior + 2 new).

All existing resolution + event tests continue to pass — the new emissions are purely additive (signals only; no state mutation changes).

- [ ] **Step 5: Commit**

```bash
git add scripts/match/match_controller.gd tests/unit/test_match_controller_player_busted_crown_awarded.gd
git commit -F - <<'EOF'
feat(client): player_busted + crown_awarded signals on MatchController

Extracts two visual-trigger signals from the existing resolution
pipeline. player_busted(peer_id, chip_loss) fires from
_build_busts_payload's per-peer loop with the chip_loss as a positive
magnitude (abs of chip_delta). crown_awarded(peer_id, count) fires
from _apply_and_emit's "crown_delta" branch with the delta value (1
for plain Crown, 2 for Sudden Death stack).

Both signals are additive — no state mutation changes, no existing
resolution test breaks. Announcer (Task 6) and PainfulReveal (Task 8)
both subscribe independently; the signals are general-purpose visual
hooks usable by future widgets (SFX in Plan C will subscribe too).

2 new tests verify the signal shape via direct .emit() calls.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 8: `PainfulReveal` widget

Animated text+chip overlay for bust + crown moments. Bust uses RED with a 2-second slide-in + dissolve; crown uses GOLD with a 1.5-second pulse. Subscribes to the same `player_busted` + `crown_awarded` signals as Announcer — both widgets receive every event. No SFX (Plan C).

**Files:**
- Create: `scripts/ui/painful_reveal.gd`
- Create: `scenes/ui/painful_reveal.tscn`
- Create: `tests/unit/test_painful_reveal.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_painful_reveal.gd`:
```gdscript
extends GutTest

const PainfulReveal = preload("res://scripts/ui/painful_reveal.gd")

func test_format_bust_reveal():
	var s = PainfulReveal.format_bust_reveal("P2", 100)
	assert_string_contains(s, "P2")
	assert_string_contains(s, "LOST")
	assert_string_contains(s, "100")

func test_format_crown_reveal_single():
	var s = PainfulReveal.format_crown_reveal("P3", 1)
	assert_string_contains(s, "P3")
	assert_string_contains(s, "+1 CROWN")

func test_format_crown_reveal_stacked():
	var s = PainfulReveal.format_crown_reveal("P3", 2)
	assert_string_contains(s, "P3")
	assert_string_contains(s, "+2 CROWN")
```

- [ ] **Step 2: Run, watch fail**

Expected: preload error for `painful_reveal.gd`.

- [ ] **Step 3: Implement `scripts/ui/painful_reveal.gd`**

```gdscript
# PainfulReveal: animated text+chip overlay for bust + crown moments.
# Subscribes to player_busted (RED, 2s slide-in + dissolve) and
# crown_awarded (GOLD, 1.5s pulse). No SFX — that's deferred to Plan C.
# Independent of Announcer; both widgets fire on every bust/crown event.
extends Control

const BUST_COLOR := Color(0.9, 0.2, 0.2, 1.0)  # RED
const CROWN_COLOR := Color(1.0, 0.84, 0.0, 1.0)  # GOLD

@onready var _label: Label = $MessageLabel if has_node("MessageLabel") else null

var controller  # MatchController-like

func _ready() -> void:
	visible = false
	if _label != null:
		_label.modulate.a = 0.0
	if controller != null:
		controller.player_busted.connect(_on_player_busted)
		controller.crown_awarded.connect(_on_crown_awarded)

func _on_player_busted(peer_id: int, chip_loss: int) -> void:
	var name = _name_for_peer(peer_id)
	_show(format_bust_reveal(name, chip_loss), BUST_COLOR, 2.0)

func _on_crown_awarded(peer_id: int, count: int) -> void:
	var name = _name_for_peer(peer_id)
	_show(format_crown_reveal(name, count), CROWN_COLOR, 1.5)

func _name_for_peer(peer_id: int) -> String:
	if controller == null or controller.state == null:
		return "P%d" % peer_id
	var p = controller.state.find_player(peer_id)
	return p.name if p != null else "P%d" % peer_id

func _show(message: String, color: Color, duration: float) -> void:
	if _label == null:
		return
	visible = true
	_label.text = message
	_label.modulate = color
	_label.modulate.a = 0.0
	# Slide-in (or pulse) + dissolve via Tween.
	var tw = create_tween()
	tw.tween_property(_label, "modulate:a", 1.0, duration * 0.25)
	tw.tween_interval(duration * 0.5)
	tw.tween_property(_label, "modulate:a", 0.0, duration * 0.25)
	tw.tween_callback(func(): visible = false)

# Static formatters (testable)

static func format_bust_reveal(peer_name: String, chip_loss: int) -> String:
	return "%s LOST $%d" % [peer_name, chip_loss]

static func format_crown_reveal(peer_name: String, count: int) -> String:
	return "%s +%d CROWN" % [peer_name, count]
```

- [ ] **Step 4: Implement `scenes/ui/painful_reveal.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/painful_reveal.gd" id="1"]

[node name="PainfulReveal" type="Control"]
script = ExtResource("1")
anchor_right = 1.0
anchor_bottom = 1.0

[node name="MessageLabel" type="Label" parent="."]
text = ""
anchor_left = 0.3
anchor_top = 0.4
anchor_right = 0.7
anchor_bottom = 0.6
horizontal_alignment = 1
vertical_alignment = 1
```

- [ ] **Step 5: Run, watch pass**

Expected: **604/604 tests pass** (602 prior + 2 new — actual count is 3; either way the suite must be green).

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/painful_reveal.gd scenes/ui/painful_reveal.tscn tests/unit/test_painful_reveal.gd
git commit -F - <<'EOF'
feat(client): PainfulReveal animated overlay for bust + crown moments

Animated text+chip overlay that pops on player_busted (RED, 2-second
slide-in + dissolve) and crown_awarded (GOLD, 1.5-second pulse). Uses
Godot's Tween for the modulate.a fade — no SFX, no AudioStreamPlayer
(Plan C handles audio).

Independent of Announcer — both widgets subscribe to the same Task 7
signals and fire in parallel. PainfulReveal is intentionally narrower:
only the 2 reveal types (bust, crown), not the 4 trigger types
Announcer covers. That keeps each widget's responsibility clear.

3 new tests cover format_bust_reveal + format_crown_reveal (single +
stacked) static formatters.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 3: Interactive overlays (Tasks 9-11)

### Task 9: `LoadoutOverlay` drag-to-loadout rewrite

REWRITE `scripts/ui/loadout_overlay.gd` from the Plan A static-formatter scaffold (sub-project #4) into a fully interactive drag-and-drop grid. Hand row of card buttons + 2 loadout slot PanelContainers. Drag protocol uses Godot 4's built-in API: `_get_drag_data` on hand buttons returns the card_id string; `_can_drop_data` on slots validates; `_drop_data` places + emits `loadout_changed(slot_index, card_id)`. Visual feedback via `NOTIFICATION_DRAG_BEGIN` / `NOTIFICATION_DRAG_END` modulate updates.

Preserves the existing static helpers (`format_card_label`, `is_card_playable`, `available_targets`) that other widgets / tests may consume.

**Files:**
- Modify: `scripts/ui/loadout_overlay.gd` (REWRITE)
- Modify: `scenes/ui/loadout_overlay.tscn` (add LoadoutSlot1 + LoadoutSlot2 PanelContainer nodes)
- Create: `tests/unit/test_loadout_overlay_drag.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_loadout_overlay_drag.gd`:
```gdscript
extends GutTest

const LoadoutOverlay = preload("res://scripts/ui/loadout_overlay.gd")

func test_can_drop_data_accepts_known_card_id():
	# Static helper: validates a drag payload against the valid hand IDs.
	assert_true(LoadoutOverlay.can_drop_card("heat_shield", ["heat_shield", "wager_tax"]),
		"card_id present in hand is droppable")

func test_can_drop_data_rejects_unknown_payload():
	assert_false(LoadoutOverlay.can_drop_card("not_a_card", ["heat_shield", "wager_tax"]),
		"card_id not in hand is rejected")
	assert_false(LoadoutOverlay.can_drop_card("", ["heat_shield"]),
		"empty string payload is rejected")

func test_apply_drop_returns_new_loadout_with_card_in_slot():
	# Pure-helper version of _drop_data: takes the current loadout +
	# slot_index + card_id and returns the new loadout.
	var loadout: Array = ["heat_shield", ""]
	var new_loadout = LoadoutOverlay.apply_drop(loadout, 1, "wager_tax")
	assert_eq(new_loadout, ["heat_shield", "wager_tax"],
		"drop in slot 1 places the card; slot 0 untouched")

func test_apply_drop_replaces_existing_slot_card():
	var loadout: Array = ["heat_shield", "wager_tax"]
	var new_loadout = LoadoutOverlay.apply_drop(loadout, 0, "insurance")
	assert_eq(new_loadout, ["insurance", "wager_tax"],
		"drop in a non-empty slot replaces the existing card")
```

- [ ] **Step 2: Run, watch fail**

Expected: 3 failures (4 tests) — `can_drop_card` and `apply_drop` static helpers don't exist on LoadoutOverlay.

- [ ] **Step 3: Rewrite `scripts/ui/loadout_overlay.gd`**

Replace the file body with:

```gdscript
# LoadoutOverlay: drag-to-loadout card grid shown during BET_LOADOUT.
# Hand row (HBoxContainer of HandCardButton nodes) + 2 LoadoutSlot
# PanelContainers. Drag-and-drop via Godot 4's _get_drag_data /
# _can_drop_data / _drop_data Control virtuals.
#
# Sub-project #7 Plan B Task 9: full rewrite of the Plan A static-
# formatter scaffold from sub-project #4. Emits loadout_changed
# (slot_index, card_id) — MatchScene wires that to MatchController.
# submit_loadout_change (Task 10).
extends PanelContainer

const CardRegistry = preload("res://scripts/cards/card_registry.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")

signal loadout_changed(slot_index: int, card_id: String)

@onready var _hand_row: HBoxContainer = $VBox/HandRow if has_node("VBox/HandRow") else null
@onready var _loadout_row: HBoxContainer = $VBox/LoadoutRow if has_node("VBox/LoadoutRow") else null
@onready var _slot_0: PanelContainer = $VBox/LoadoutRow/LoadoutSlot0 if has_node("VBox/LoadoutRow/LoadoutSlot0") else null
@onready var _slot_1: PanelContainer = $VBox/LoadoutRow/LoadoutSlot1 if has_node("VBox/LoadoutRow/LoadoutSlot1") else null
@onready var _hint_label: Label = $VBox/HintLabel if has_node("VBox/HintLabel") else null

var controller  # MatchController-like (set by MatchScene before _ready)
var local_player  # MatchPlayer-like

func _ready() -> void:
	visible = false
	if controller != null:
		controller.bet_loadout_started.connect(_on_bet_loadout_started)
		controller.bet_loadout_finished.connect(_on_bet_loadout_finished)
		controller.loadout_acknowledged.connect(_on_loadout_acknowledged)
		controller.card_effect_applied.connect(_on_card_effect_applied)
		controller.card_play_rejected.connect(_on_card_play_rejected)
	# Bind slot_index into _drop_data_slot so each slot's drop callback
	# receives its own index without a global-mouse-position lookup.
	if _slot_0 != null:
		_slot_0.set_drag_forwarding(_get_drag_data_noop, _can_drop_data_slot, _drop_data_slot.bind(0))
	if _slot_1 != null:
		_slot_1.set_drag_forwarding(_get_drag_data_noop, _can_drop_data_slot, _drop_data_slot.bind(1))

func _on_bet_loadout_started(_active_peer_ids: Array, _max_per_player: int) -> void:
	visible = true
	_refresh()

func _on_bet_loadout_finished() -> void:
	visible = false

func _on_loadout_acknowledged(peer_id: int, _loadout: Array) -> void:
	if local_player != null and peer_id == local_player.peer_id:
		_refresh()

func _on_card_effect_applied(peer_id: int, _card_id: String, _effect: Dictionary) -> void:
	if local_player != null and peer_id == local_player.peer_id:
		_refresh()

func _on_card_play_rejected(_card_id: String, _reason: String) -> void:
	_refresh()

func _refresh() -> void:
	if _hand_row == null or _loadout_row == null or local_player == null:
		return
	# Rebuild hand row.
	for child in _hand_row.get_children():
		child.queue_free()
	for card_id in local_player.hand:
		var btn = Button.new()
		btn.text = format_card_label(card_id)
		btn.set_meta("card_id", card_id)
		btn.set_drag_forwarding(_get_drag_data_card.bind(btn), _can_drop_data_noop, _drop_data_noop)
		_hand_row.add_child(btn)
	# Rebuild slot labels.
	_render_slot_label(_slot_0, 0)
	_render_slot_label(_slot_1, 1)
	if _hint_label != null:
		_hint_label.text = "Drag cards from hand into the loadout slots"

func _render_slot_label(slot: PanelContainer, slot_index: int) -> void:
	if slot == null or local_player == null:
		return
	for child in slot.get_children():
		child.queue_free()
	var lbl = Label.new()
	var card_id = ""
	if slot_index < local_player.loadout.size():
		card_id = String(local_player.loadout[slot_index])
	lbl.text = format_card_label(card_id) if card_id != "" else "[empty]"
	slot.add_child(lbl)

# Drag callbacks (Godot 4 Control virtuals via set_drag_forwarding)

func _get_drag_data_card(_at_position: Vector2, btn: Button) -> Variant:
	return String(btn.get_meta("card_id", ""))

func _get_drag_data_noop(_at_position: Vector2) -> Variant:
	return null

func _can_drop_data_slot(_at_position: Vector2, data) -> bool:
	if local_player == null:
		return false
	return can_drop_card(data, local_player.hand)

func _can_drop_data_noop(_at_position: Vector2, _data) -> bool:
	return false

func _drop_data_slot(_at_position: Vector2, data, slot_index: int) -> void:
	# slot_index is bound via Callable.bind() in _ready — no mouse-position
	# heuristic needed. Godot appends bound args after the declared params.
	var card_id = String(data)
	if local_player != null:
		local_player.loadout = apply_drop(local_player.loadout, slot_index, card_id)
		_render_slot_label(_slot_0, 0)
		_render_slot_label(_slot_1, 1)
	loadout_changed.emit(slot_index, card_id)

func _drop_data_noop(_at_position: Vector2, _data) -> void:
	pass

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_modulate_slots(Color(1.2, 1.2, 1.2, 1.0))
	elif what == NOTIFICATION_DRAG_END:
		_modulate_slots(Color(1.0, 1.0, 1.0, 1.0))

func _modulate_slots(c: Color) -> void:
	if _slot_0 != null:
		_slot_0.modulate = c
	if _slot_1 != null:
		_slot_1.modulate = c

# Static formatters / helpers (testable without scene)

static func format_card_label(card_id: String) -> String:
	if card_id == "":
		return ""
	var card = CardRegistry.get_card(card_id)
	return String(card.get("name", "?"))

static func is_card_playable(card_id: String, phase: int, played_this_event: Array) -> bool:
	if card_id in played_this_event:
		return false
	var card = CardRegistry.get_card(card_id)
	var timing = card.get("timing", "")
	if timing == "bet_loadout" and phase == MatchPhase.Phase.BET_LOADOUT:
		return true
	if timing == "cash_out" and phase == MatchPhase.Phase.MAIN_EVENT:
		return true
	return false

static func available_targets(local_peer_id: int, players: Array, card_meta: Dictionary) -> Array:
	if not card_meta.get("target_required", false):
		return []
	var out: Array = []
	for p in players:
		if not p.is_active_this_event:
			continue
		if p.peer_id == local_peer_id:
			continue
		out.append(p.peer_id)
	return out

# Sub-project #7 Plan B Task 9: testable drag predicates.

static func can_drop_card(payload, valid_hand_ids: Array) -> bool:
	if not (payload is String):
		return false
	if String(payload) == "":
		return false
	return String(payload) in valid_hand_ids

static func apply_drop(loadout: Array, slot_index: int, card_id: String) -> Array:
	var out: Array = loadout.duplicate()
	while out.size() <= slot_index:
		out.append("")
	out[slot_index] = card_id
	return out
```

- [ ] **Step 4: Update `scenes/ui/loadout_overlay.tscn`**

Modify the scene to add the two LoadoutSlot PanelContainers under VBox/LoadoutRow. The HandRow + HintLabel stay; replace any existing single LoadoutSlot with the two-slot structure:

```
[node name="LoadoutRow" type="HBoxContainer" parent="VBox"]

[node name="LoadoutSlot0" type="PanelContainer" parent="VBox/LoadoutRow"]

[node name="LoadoutSlot1" type="PanelContainer" parent="VBox/LoadoutRow"]
```

(Preserve any existing HandRow + HintLabel nodes already in the scene.)

- [ ] **Step 5: Run, watch pass**

Expected: **607/607 tests pass** (604 prior + 3 new — accounting headline; actual is 4 if all 4 tests count).

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/loadout_overlay.gd scenes/ui/loadout_overlay.tscn tests/unit/test_loadout_overlay_drag.gd
git commit -F - <<'EOF'
feat(client): LoadoutOverlay drag-to-loadout rewrite

Closes the sub-project #4 Plan A carry-forward "LoadoutOverlay
interactive grid." The Plan A delivery was static formatters + a
placeholder hint label — the real hand/loadout button-grid was deferred.

Full rewrite using Godot 4's _get_drag_data / _can_drop_data /
_drop_data Control virtuals (wired via set_drag_forwarding so the same
overlay can dispatch differently per child node). Hand row of card
buttons drags out a card_id String payload; two LoadoutSlot
PanelContainers validate via can_drop_card and place via apply_drop.
NOTIFICATION_DRAG_BEGIN / DRAG_END modulate the slots for visual
feedback during the drag.

Emits loadout_changed(slot_index, card_id) — Task 10 wires that to
MatchController.submit_loadout_change so the host RPC fires.

4 new tests cover the can_drop_card validation + apply_drop replace
semantics. The existing format_card_label / is_card_playable /
available_targets static helpers are preserved (other widgets / tests
may consume them).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 10: LoadoutOverlay integration wiring

Wire the new `loadout_changed(slot_index, card_id)` signal from Task 9 to `MatchController.submit_loadout_change(loadout)`. MatchScene constructs the loadout Array from the local player's current loadout state (after Task 9's `apply_drop` mutation) and forwards.

The existing `submit_loadout_change` RPC contract is unchanged — it takes `loadout: Array` and the host clamps to `MAX_LOADOUT_SIZE`.

**Files:**
- Modify: `scripts/ui/match_scene.gd` (wire `_on_loadout_changed` handler + connect signal)
- Create: `tests/unit/test_match_scene_loadout_wire.gd`

- [ ] **Step 1: Write failing test**

`tests/unit/test_match_scene_loadout_wire.gd`:
```gdscript
extends GutTest

const MatchScene = preload("res://scripts/ui/match_scene.gd")

# Pure unit test for the controller-call shape — the MatchScene method
# under test takes a local_player + the new slot_index/card_id and
# returns the updated full loadout Array that gets submitted.

func test_compute_loadout_from_drop_replaces_slot_0():
	var current_loadout: Array = ["heat_shield", "wager_tax"]
	var out = MatchScene.compute_loadout_from_drop(current_loadout, 0, "insurance")
	assert_eq(out, ["insurance", "wager_tax"])

func test_compute_loadout_from_drop_fills_empty_slot():
	var current_loadout: Array = ["heat_shield"]
	var out = MatchScene.compute_loadout_from_drop(current_loadout, 1, "wager_tax")
	assert_eq(out, ["heat_shield", "wager_tax"])
```

(2 tests — actual count 2; headline +1 in plan-doc estimate.)

- [ ] **Step 2: Run, watch fail**

Expected: 2 failures — `compute_loadout_from_drop` static doesn't exist on MatchScene.

- [ ] **Step 3: Wire the handler + static helper on MatchScene**

In `scripts/ui/match_scene.gd`, after `_build_loadout_overlay` add:

```gdscript
func _build_loadout_overlay() -> void:
	if _loadout_slot == null:
		return
	_loadout_overlay = LoadoutOverlayScene.instantiate()
	_loadout_overlay.controller = controller
	_loadout_overlay.local_player = _find_local_player()
	_loadout_slot.add_child(_loadout_overlay)
	# Sub-project #7 Plan B Task 10: wire drag-drop signal to controller.
	_loadout_overlay.loadout_changed.connect(_on_loadout_changed)

func _on_loadout_changed(slot_index: int, card_id: String) -> void:
	var local = _find_local_player()
	if local == null or controller == null:
		return
	var new_loadout = compute_loadout_from_drop(local.loadout, slot_index, card_id)
	controller.submit_loadout_change(new_loadout)

# Static helper (testable). Mirrors LoadoutOverlay.apply_drop's
# semantics — kept here so MatchScene's wiring is testable without
# needing the LoadoutOverlay scene.
static func compute_loadout_from_drop(current_loadout: Array, slot_index: int, card_id: String) -> Array:
	var out: Array = current_loadout.duplicate()
	while out.size() <= slot_index:
		out.append("")
	out[slot_index] = card_id
	return out
```

(Modify the existing `_build_loadout_overlay` body in place — the lines above show both old and new sections together for clarity. The only new lines inside `_build_loadout_overlay` are the `loadout_changed.connect` line; the rest is unchanged.)

- [ ] **Step 4: Run, watch pass**

Expected: **608/608 tests pass** (607 prior + 1 new — actual count 2; headline +1).

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/match_scene.gd tests/unit/test_match_scene_loadout_wire.gd
git commit -F - <<'EOF'
feat(client): MatchScene wires LoadoutOverlay.loadout_changed to controller

Closes the integration half of the sub-project #4 LoadoutOverlay
carry-forward. End-to-end drag flow now lands a host-acknowledged
loadout: user drags card -> LoadoutOverlay._drop_data_slot fires
loadout_changed(slot_index, card_id) -> MatchScene._on_loadout_changed
rebuilds the full loadout Array via compute_loadout_from_drop ->
MatchController.submit_loadout_change(loadout) -> rpc_id(host) ->
_rpc_loadout_set host-clamps and broadcasts _rpc_loadout_acknowledged.

Submit_loadout_change's RPC contract is unchanged — Plan A Task 12
already converted it to rpc_id(host_peer_id) for bandwidth.

2 new tests cover compute_loadout_from_drop's replace + extend
semantics. The drag itself is exercised by Plan B Task 9 tests and
by playtest checklist scenario 34 (Task 12).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 11: Cash-Out Jammer target picker modal

Modal popup that opens when the local player selects a `target_required` card from the Cash-Out drawer (today only Cash-Out Jammer). Lists other active peers as Button rows (peer name + chip count); clicking fires `submit_card_play(card_id, chosen_target_peer_id, params)` with the real target instead of the no-op `target_peer_id=0`. Closes the sub-project #4 Plan B carry-forward where Cash-Out Jammer was non-functional via UI.

**Files:**
- Create: `scripts/ui/cash_out_card_drawer_target_picker.gd`
- Create: `scenes/ui/cash_out_card_drawer_target_picker.tscn`
- Modify: `scripts/ui/cash_out_card_drawer.gd` (branch on `target_required` to open the picker)
- Modify: `scripts/ui/match_scene.gd` (instantiate the picker scene slot)
- Create: `tests/unit/test_cash_out_card_drawer_target_picker.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_cash_out_card_drawer_target_picker.gd`:
```gdscript
extends GutTest

const TargetPicker = preload("res://scripts/ui/cash_out_card_drawer_target_picker.gd")

func test_format_peer_button_label():
	var lbl = TargetPicker.format_peer_button_label("P2", 450)
	assert_string_contains(lbl, "P2")
	assert_string_contains(lbl, "450")

func test_filter_eligible_targets_excludes_self_and_busted():
	var players: Array = [
		{"peer_id": 1, "name": "P1", "chips": 500, "is_active_this_event": true},
		{"peer_id": 2, "name": "P2", "chips": 450, "is_active_this_event": true},
		{"peer_id": 3, "name": "P3", "chips": 0, "is_active_this_event": false},
	]
	var out = TargetPicker.filter_eligible_targets(1, players)
	assert_eq(out.size(), 1, "self excluded; busted (is_active_this_event=false) excluded")
	assert_eq(int(out[0].peer_id), 2)
```

- [ ] **Step 2: Run, watch fail**

Expected: preload error for `cash_out_card_drawer_target_picker.gd`.

- [ ] **Step 3: Implement `scripts/ui/cash_out_card_drawer_target_picker.gd`**

```gdscript
# CashOutCardDrawerTargetPicker: modal popup that opens when the local
# player selects a target_required cash-out card (Cash-Out Jammer
# today). Lists other active peers as buttons; click submits the card
# play with the chosen target_peer_id. Closes sub-project #4 Plan B
# carry-forward where the drawer submitted target_peer_id=0 and got
# host-rejected.
extends CenterContainer

signal target_chosen(target_peer_id: int)
signal cancelled

@onready var _row: VBoxContainer = $Panel/VBox/Row if has_node("Panel/VBox/Row") else null
@onready var _cancel_button: Button = $Panel/VBox/CancelButton if has_node("Panel/VBox/CancelButton") else null

var controller  # MatchController-like
var local_peer_id: int = 0
var _pending_card_id: String = ""

func _ready() -> void:
	visible = false
	if _cancel_button != null:
		_cancel_button.pressed.connect(_on_cancel)

func open_for_card(card_id: String, players: Array) -> void:
	_pending_card_id = card_id
	visible = true
	if _row == null:
		return
	for child in _row.get_children():
		child.queue_free()
	for peer in filter_eligible_targets(local_peer_id, players):
		var btn = Button.new()
		btn.text = format_peer_button_label(String(peer.get("name", "P?")), int(peer.get("chips", 0)))
		btn.pressed.connect(_on_peer_pressed.bind(int(peer.get("peer_id", 0))))
		_row.add_child(btn)

func _on_peer_pressed(peer_id: int) -> void:
	target_chosen.emit(peer_id)
	if controller != null and _pending_card_id != "":
		controller.submit_card_play(_pending_card_id, peer_id, null)
	_pending_card_id = ""
	visible = false

func _on_cancel() -> void:
	cancelled.emit()
	_pending_card_id = ""
	visible = false

# Static helpers (testable)

static func format_peer_button_label(peer_name: String, chips: int) -> String:
	return "%s (%d chips)" % [peer_name, chips]

static func filter_eligible_targets(local_peer_id: int, players: Array) -> Array:
	var out: Array = []
	for p in players:
		var pid = int(p.get("peer_id", 0)) if p is Dictionary else int(p.peer_id)
		if pid == local_peer_id:
			continue
		var active = (p.get("is_active_this_event", false) if p is Dictionary
			else bool(p.is_active_this_event))
		if not active:
			continue
		out.append(p)
	return out
```

- [ ] **Step 4: Implement `scenes/ui/cash_out_card_drawer_target_picker.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/cash_out_card_drawer_target_picker.gd" id="1"]

[node name="CashOutCardDrawerTargetPicker" type="CenterContainer"]
script = ExtResource("1")
anchor_right = 1.0
anchor_bottom = 1.0

[node name="Panel" type="PanelContainer" parent="."]

[node name="VBox" type="VBoxContainer" parent="Panel"]

[node name="Title" type="Label" parent="Panel/VBox"]
text = "Choose a target"

[node name="Row" type="VBoxContainer" parent="Panel/VBox"]

[node name="CancelButton" type="Button" parent="Panel/VBox"]
text = "Cancel"
```

- [ ] **Step 5: Update `cash_out_card_drawer.gd` to branch on `target_required`**

In `scripts/ui/cash_out_card_drawer.gd`, replace `_on_card_pressed`:

```gdscript
func _on_card_pressed(card_id: String) -> void:
	if controller == null:
		return
	# MVP: target_peer_id = 0 means UI defers to host's target_required reject.
	# Full target picker UI is a polish-pass item.
	controller.submit_card_play(card_id, 0, null)
```

with:

```gdscript
signal target_required_card_pressed(card_id: String)

func _on_card_pressed(card_id: String) -> void:
	if controller == null:
		return
	var card = CardRegistry.get_card(card_id)
	if card.get("target_required", false):
		# Sub-project #7 Plan B Task 11: defer to MatchScene's target
		# picker modal. MatchScene wires this signal to open the picker.
		target_required_card_pressed.emit(card_id)
		return
	controller.submit_card_play(card_id, 0, null)
```

- [ ] **Step 6: Wire the picker in MatchScene**

In `scripts/ui/match_scene.gd`, add preload + slot reference + builder:

```gdscript
const CashOutCardDrawerTargetPickerScene = preload("res://scenes/ui/cash_out_card_drawer_target_picker.tscn")

@onready var _target_picker_slot: Container = $TargetPickerSlot if has_node("TargetPickerSlot") else null

var _target_picker: Node = null
```

After `_build_cash_out_drawer`, add:

```gdscript
func _build_target_picker() -> void:
	if _target_picker_slot == null:
		return
	_target_picker = CashOutCardDrawerTargetPickerScene.instantiate()
	_target_picker.controller = controller
	var local = _find_local_player()
	_target_picker.local_peer_id = local.peer_id if local != null else 0
	_target_picker_slot.add_child(_target_picker)

func _on_target_required_card_pressed(card_id: String) -> void:
	if _target_picker == null or controller == null or controller.state == null:
		return
	# Pass MatchPlayer instances directly; filter_eligible_targets accepts
	# both Dictionary and object-with-properties shapes.
	_target_picker.open_for_card(card_id, controller.state.players)
```

In `_ready` after `_build_cash_out_drawer()`, add:

```gdscript
	_build_target_picker()
```

Inside `_build_cash_out_drawer`, after `_cash_out_slot.add_child(_cash_out_drawer)`, add:

```gdscript
	_cash_out_drawer.target_required_card_pressed.connect(_on_target_required_card_pressed)
```

Update `scenes/match_scene.tscn` to add a `TargetPickerSlot` Container under the root Control (sibling to the existing slot containers).

- [ ] **Step 7: Run, watch pass**

Expected: **610/610 tests pass** (608 prior + 2 new).

- [ ] **Step 8: Commit**

```bash
git add scripts/ui/cash_out_card_drawer_target_picker.gd scenes/ui/cash_out_card_drawer_target_picker.tscn scripts/ui/cash_out_card_drawer.gd scripts/ui/match_scene.gd scenes/match_scene.tscn tests/unit/test_cash_out_card_drawer_target_picker.gd
git commit -F - <<'EOF'
feat(client): Cash-Out Jammer target picker modal

Closes the sub-project #4 Plan B carry-forward "Cash-Out Card Drawer
target picker missing." Previously the drawer submitted Cash-Out
Jammer with target_peer_id=0 and the host's target_required validation
rejected the play — making the card non-functional via UI.

New modal: CenterContainer popup with a VBox of peer-name+chip-count
buttons. Click submits submit_card_play(card_id, chosen_target_peer_id,
null) with the real target. CashOutCardDrawer branches on card_meta.
target_required: target-required cards emit a new
target_required_card_pressed signal which MatchScene routes to the
picker; non-target cards keep the existing direct-submit path.

filter_eligible_targets excludes self + non-active peers (busted or
spectating). 2 new tests cover the formatter + filter logic.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Phase 4: Integration + docs (Task 12)

### Task 12: Integration test PENDING stub + PLAYTEST_CHECKLIST scenarios 28-34

Add a new PENDING integration test stub (matches the existing 7 PENDING precedent — pends cleanly when signaling server is unreachable). Append scenarios 28-34 to `docs/PLAYTEST_CHECKLIST.md` covering the 7 visible-info UX additions delivered in Plan B.

**Files:**
- Create: `tests/integration/test_announcer_fires_across_phases.gd`
- Modify: `docs/PLAYTEST_CHECKLIST.md`

- [ ] **Step 1: Create the integration test stub**

`tests/integration/test_announcer_fires_across_phases.gd`:
```gdscript
# Integration smoke test: real signaling + WebRTC + Announcer fires on
# all 4 trigger types (house_twist_announced, player_busted,
# crown_awarded, match_ended) across a 2-peer simulated match.
# Also verifies StatusGrid populates correctly per event and that
# PainfulReveal shows on bust and crown moments only.
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

func test_announcer_fires_across_phases():
	if not await _signaling_reachable():
		pending("Signaling server not reachable at %s; skipping. Start with `cd ../signaling-server && node server.js`." % SIGNALING_URL)
		return
	# Implementer note: cargo-cult test_three_event_rotation.gd; run
	# a 2-peer 3-event match; subscribe to controller signals on each
	# peer; assert: (a) house_twist_announced fires at HOUSE_TWIST end;
	# (b) player_busted fires for at least one peer across the match;
	# (c) crown_awarded fires for the event winner; (d) match_ended
	# fires once at the end with the winner in rankings[0].
	pending("Implementer: cargo-cult test_three_event_rotation.gd; subscribe to MatchController signals on both peers; assert Announcer-trigger signals fire on the host and mirror to the joiner.")
```

- [ ] **Step 2: Append scenarios 28-34 to PLAYTEST_CHECKLIST.md**

Open `docs/PLAYTEST_CHECKLIST.md` and append:

```markdown

## Sub-project #7 Plan B — visible-info polish

- [ ] **Scenario 28: StatusGrid populates correctly for each of the 3 events.** Run a Quick Clash. During Rocket Clash, verify the StatusGrid chips flip from IN to CASHED / BUSTED as players cash out or crash. During Bomb Pot, chips flip from IN to PULLED / BUSTED. During Card Cannon, chips flip from DRAWING to LOCKED / BUSTED.
- [ ] **Scenario 29: BetLoadoutOverlay shows countdown + per-peer readied checkmarks.** At BET_LOADOUT entry, verify the countdown label ticks `[15s]` → `[1s]`. As each peer hits Ready, verify their chip in the readied row flips to `✓ P2` (or whichever peer name).
- [ ] **Scenario 30: EventPickerOverlay countdown ticks down visibly.** Trigger a `lowest_chips_picks` house twist. Verify the picker peer sees the countdown label tick `[10s]` → `[1s]` during the pick window. Verify it hides when the picker chooses (or the timeout fallback fires).
- [ ] **Scenario 31: `crown_delta=2` renders prominently in resolution overlay.** Trigger a Sudden Death Jackpot house twist and have a survivor meet the condition (cash out >5x in Rocket Clash, pull out after 80% in Bomb Pot, lock at exactly 21 in Card Cannon). Verify the resolution overlay shows `P3 gets 👑👑 2 CROWNS (Sudden Death stack!)` for that survivor.
- [ ] **Scenario 32: Announcer fires on all 4 trigger types.** Across a single match, verify the top banner pops on: (a) HOUSE_TWIST announcement at end of event 1, (b) any player ejection during a main event, (c) the Crown award at the resolution step, (d) the match-end winner reveal. Each fade auto-dismisses after ~3 seconds.
- [ ] **Scenario 33: PainfulReveal animations appear on bust (RED) and crown (GOLD) moments only.** Verify the bust reveal uses red text+chip with a 2-second slide-in + dissolve. Verify the crown reveal uses gold text+chip with a 1.5-second pulse. Verify NEITHER fires on house twist nor match-end (those are Announcer-only).
- [ ] **Scenario 34: LoadoutOverlay drag-to-slot works end-to-end + Cash-Out Jammer target picker functional.** Drag a card from the hand row into LoadoutSlot0; verify the slot label updates and the host acknowledges via `_rpc_loadout_acknowledged`. During the rocket, select Cash-Out Jammer from the drawer; verify the target picker modal opens with peer-name+chips buttons; click a peer; verify the play succeeds (the target's cash-out is jammed).
```

- [ ] **Step 3: Run, verify pass**

Expected: **610/610 unit + 8/8 integration tests pass** (610 unit prior; the new integration test PENDINGs cleanly since signaling isn't reachable in the headless run, so the integration count rises 7 → 8 with the new PENDING).

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test_announcer_fires_across_phases.gd docs/PLAYTEST_CHECKLIST.md
git commit -F - <<'EOF'
test(integration): Announcer-across-phases PENDING stub + checklist 28-34

Adds the 8th integration test stub matching the existing PENDING
precedent. test_announcer_fires_across_phases pends cleanly when the
signaling server isn't reachable; the body documents the expected
2-peer behavior (Announcer fires on all 4 trigger types; StatusGrid
populates; PainfulReveal shows on bust + crown only).

PLAYTEST_CHECKLIST.md gains scenarios 28-34 covering the 7 visible-info
UX additions delivered in Plan B: StatusGrid populated, BetLoadoutOverlay
countdown + readied, EventPickerOverlay countdown, crown_delta=2
rendering, Announcer 4 trigger types, PainfulReveal bust + crown
animations, and LoadoutOverlay drag + Cash-Out Jammer target picker.

Closes Plan B. Test suite lands at 610 unit + 8 integration.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
```

---

## Done

Plan B complete. Sub-project #7 Plan B delivers:
- 6 UX carry-forwards from sub-project #6 final review closed (EventPickerOverlay countdown, `crown_delta=2` rendering, StatusGrid populated for all 3 events, BetLoadoutOverlay countdown + readied indicator, Cash-Out Card Drawer target picker, LoadoutOverlay drag interactive grid)
- 2 new widgets (Announcer banner, PainfulReveal animated overlay) firing on bust + crown + match-end moments
- 4 new MatchController signals (`player_busted`, `crown_awarded`, `bet_loadout_timer_tick`, `status_changed`) extracting visual triggers from resolution + phase machinery
- +23 unit tests + 1 new integration test target

**Cumulative state after Plan B merge:**
- Test suite: ~610 unit + 8 integration
- All visible-info polish for public alpha complete
- Plan C (feel + audio + a11y) is the last MVP plan

**Tags after Plan B merges:** `subproject-7-plan-b-complete`. After Plan C merges: `subproject-7-plan-c-complete` + `subproject-7-complete` + `mvp-complete`.

**Memory updates after Plan B merges:**
- `MEMORY.md` / `project_riskroyal.md` — mark Plan B done; Plan C next (final MVP plan)
- `project_riskroyal_followups.md` — close the 6 UX carry-forwards Plan B addressed (StatusGrid populated, EventPickerOverlay countdown, crown_delta=2 rendering, BetLoadoutOverlay countdown + readied, Cash-Out Card Drawer target picker, LoadoutOverlay interactive grid); flag remaining items as Plan C (SFX, polished animations, spectator polish, a11y) or post-MVP (integration test depth)
