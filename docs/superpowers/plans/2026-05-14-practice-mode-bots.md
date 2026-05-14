# Practice Match (Singleplayer + Bots) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Local-only "Practice vs Bots" mode that runs the full match loop end-to-end without WebRTC/signaling. Primarily a testing tool; secondarily a tutorial/demo path.

**Architecture:**

- Bots run **inside** the host process — no fake peers, no RPC roundtrip. They obtain a `peer_id` >= 1000 (high range to avoid collision with real Godot multiplayer peer IDs which start at 1 and increment).
- New host-side entry methods (`host_submit_*`) on MatchController + event nodes accept an explicit `peer_id`, mirroring existing `submit_*` methods which infer the actor from `multiplayer.get_unique_id()`. Bots call these.
- New `BotDecisions` static helper module makes every decision a pure function (testable in isolation, deterministic via seeded `RandomNumberGenerator`).
- New `BotController` instance per bot subscribes to MatchController signals (`phase_changed`, `bet_loadout_started`, `shop_opened`, `event_picker_started`, `event_starting`) and dispatches bot actions via `BotDecisions` + `host_submit_*`.
- New `PracticeSession` builder constructs a MatchStart with 1 human seat + N bot seats and a chosen seed, registers it with `NetSessionMain.get_last_match_start()`, and transitions to `MatchScene`. Scene gains a `practice_mode: bool` that spawns BotControllers for the bot seats.
- New "Practice vs Bots" button on Main Menu opens a small setup dialog (bot count 1-7, optional seed) then starts the match.

**Tech Stack:** Godot 4.6 + GDScript (tabs), GUT testing framework, static-only Object helpers (mirror `HeatRules`, `PlayerSelectors`, `BountyResolver` patterns).

**Non-goals:**
- Humans + bots in the same multiplayer lobby (deferred — practice mode only).
- Heuristic AI personalities (start with random-legal; layer heuristics later via the `BotDecisions` seam).
- Difficulty levels.

---

## File Structure

**Create:**
- `scripts/match/bot_decisions.gd` — Static-only helper. Pure functions for every bot decision point. Seeded.
- `scripts/match/bot_controller.gd` — Node-derived. One instance per bot. Wires signals to BotDecisions + host_submit calls. Owns one Timer per active event.
- `scripts/net/practice_session.gd` — Static helper that builds a `MatchStart` with bot seats + injects into `NetSessionMain` cache; transitions scene to `match_scene.tscn`.
- `scenes/practice_setup.tscn` — Small modal: bot-count Spinbox (1–7), seed LineEdit (optional), Start button, Cancel button.
- `scripts/ui/practice_setup_overlay.gd` — Controller for the practice setup modal.
- `tests/unit/test_bot_decisions.gd` — Pin decision functions via fixed seed.
- `tests/unit/test_bot_controller.gd` — Wire-level tests against a fake controller.
- `tests/unit/test_match_controller_host_submit.gd` — Cover the new explicit-peer-id entry points.
- `tests/integration/test_practice_match_runs_to_completion.gd` — One bot + one human run 5 events to `match_ended`.

**Modify:**
- `scripts/match/match_controller.gd` — Add `host_submit_wager(peer_id, amount)`, `host_submit_loadout(peer_id, loadout)`, `host_submit_card_play(peer_id, card_id, target_peer_id, params)`, `host_submit_event_pick(peer_id, chosen_path)`, `host_submit_shop_buy(peer_id, card_id)`, `host_submit_shop_done(peer_id)`. Each gated on `is_host = true`, otherwise pushes a warning and returns. Routes to the same internal logic as the existing `_rpc_*` receivers.
- `scripts/events/rocket_clash/rocket_clash_event.gd` — Add `host_submit_cash_out(peer_id, mult_snapshot)`.
- `scripts/events/bomb_pot/bomb_pot_event.gd` — Add `host_submit_pull_out(peer_id)`.
- `scripts/events/card_cannon/card_cannon_event.gd` — Add `host_submit_draw(peer_id)` and `host_submit_lock(peer_id)`.
- `scripts/ui/main_menu.gd` + `scenes/main_menu.tscn` — Add "Practice vs Bots" button + handler.
- `scripts/ui/match_scene.gd` — Read `practice_mode` flag from NetSessionMain cache; when true, instantiate one `BotController` per bot seat (seat.is_host == false AND seat.peer_id >= 1000) on host.
- `scripts/net/net_session_main.gd` — Add `practice_mode: bool` field + setter so PracticeSession can flag the next match.

---

## Task 1: BotDecisions static helpers + tests

**Files:**
- Create: `scripts/match/bot_decisions.gd`
- Test:   `tests/unit/test_bot_decisions.gd`

Pure static functions covering every bot decision. All take a `RandomNumberGenerator` as the last arg so callers can pass a seeded RNG and tests can pin behavior.

**Signatures (final):**

```gdscript
extends Object

# Returns wager in [0, max_wager]. Uses a simple distribution that biases
# toward the middle of the legal range (avoid 0-wagers which feel like the
# bot is skipping).
static func pick_wager(max_wager: int, player_chips: int, rng: RandomNumberGenerator) -> int

# Rocket Clash. Returns a delay in ms from rocket launch when the bot
# should request cash-out. Range 2500-8000 ms (skewed toward 3500-5500).
static func pick_cash_out_delay_ms(rng: RandomNumberGenerator) -> int

# Bomb Pot. Returns a delay in ms from pot opening when the bot should
# pull out. Spec gives min/max detonation (5.0-25.0s); bot pulls between
# 30% and 90% of midpoint. Range ~4500-13500 ms.
static func pick_pull_out_delay_ms(rng: RandomNumberGenerator) -> int

# Card Cannon. Returns the locked-score threshold the bot is aiming for.
# Range 14-19. Bot will draw until locked_score >= threshold or it busts.
static func pick_card_cannon_threshold(rng: RandomNumberGenerator) -> int

# BET_LOADOUT loadout selection. Returns up to `max_loadout_size` card ids
# from `hand`. Random selection (legal, deterministic via rng).
static func pick_loadout(hand: Array, max_loadout_size: int, rng: RandomNumberGenerator) -> Array

# SHOP. Returns the card_id to buy (or "" to skip). Buys if any offered
# card costs <= player_chips/2 (don't burn half their stack).
static func pick_shop_purchase(offered_card_ids: Array, offer_costs: Dictionary, player_chips: int, rng: RandomNumberGenerator) -> String

# EVENT_PICKER (Lowest Chips Picks twist). Returns one of the options at random.
static func pick_event_path(options: Array, rng: RandomNumberGenerator) -> String

# Helper: build a per-bot RNG derived from match seed + peer_id so two bots
# in the same match get different streams but the match is reproducible.
static func rng_for_bot(match_seed: int, bot_peer_id: int) -> RandomNumberGenerator
```

**Step 1 — Write the failing tests.** Create `tests/unit/test_bot_decisions.gd`. Pin each function with a fixed seed (e.g. `12345`). Assertions:

```gdscript
extends GutTest

const BotDecisions = preload("res://scripts/match/bot_decisions.gd")

func _seeded(seed_int: int = 12345) -> RandomNumberGenerator:
    var r = RandomNumberGenerator.new()
    r.seed = seed_int
    return r

func test_pick_wager_within_range():
    var w = BotDecisions.pick_wager(500, 1000, _seeded())
    assert_gte(w, 0); assert_lte(w, 500)

func test_pick_wager_deterministic_for_seed():
    var a = BotDecisions.pick_wager(500, 1000, _seeded(42))
    var b = BotDecisions.pick_wager(500, 1000, _seeded(42))
    assert_eq(a, b)

func test_pick_wager_zero_max_returns_zero():
    assert_eq(BotDecisions.pick_wager(0, 1000, _seeded()), 0)

func test_pick_cash_out_delay_in_range():
    var d = BotDecisions.pick_cash_out_delay_ms(_seeded())
    assert_gte(d, 2500); assert_lte(d, 8000)

func test_pick_pull_out_delay_in_range():
    var d = BotDecisions.pick_pull_out_delay_ms(_seeded())
    assert_gte(d, 4500); assert_lte(d, 13500)

func test_pick_card_cannon_threshold_in_range():
    var t = BotDecisions.pick_card_cannon_threshold(_seeded())
    assert_gte(t, 14); assert_lte(t, 19)

func test_pick_loadout_respects_max_size():
    var hand = ["a", "b", "c", "d", "e"]
    var lo = BotDecisions.pick_loadout(hand, 2, _seeded())
    assert_lte(lo.size(), 2)
    for c in lo:
        assert_true(c in hand)

func test_pick_loadout_no_duplicates():
    var hand = ["a", "b", "c"]
    var lo = BotDecisions.pick_loadout(hand, 3, _seeded())
    assert_eq(lo.size(), len(_unique(lo)))

func test_pick_loadout_empty_hand_returns_empty():
    assert_eq(BotDecisions.pick_loadout([], 2, _seeded()), [])

func test_pick_shop_purchase_skip_when_no_offer():
    assert_eq(BotDecisions.pick_shop_purchase([], {}, 500, _seeded()), "")

func test_pick_shop_purchase_skip_when_too_expensive():
    # Card costs 400, bot has 500 → 80% of stack, > 50% threshold → skip.
    var got = BotDecisions.pick_shop_purchase(["pricey"], {"pricey": 400}, 500, _seeded())
    assert_eq(got, "")

func test_pick_shop_purchase_buys_affordable():
    # Card costs 50, bot has 500 → 10% of stack, well under threshold.
    var got = BotDecisions.pick_shop_purchase(["cheap"], {"cheap": 50}, 500, _seeded())
    assert_eq(got, "cheap")

func test_pick_event_path_returns_member():
    var got = BotDecisions.pick_event_path(["a", "b", "c"], _seeded())
    assert_true(got in ["a", "b", "c"])

func test_rng_for_bot_differs_across_peer_ids():
    var ra = BotDecisions.rng_for_bot(99, 1000)
    var rb = BotDecisions.rng_for_bot(99, 1001)
    assert_ne(ra.randi(), rb.randi())

func test_rng_for_bot_reproducible_for_same_inputs():
    var ra = BotDecisions.rng_for_bot(99, 1000)
    var rb = BotDecisions.rng_for_bot(99, 1000)
    assert_eq(ra.randi(), rb.randi())

func _unique(arr: Array) -> Array:
    var seen: Dictionary = {}
    for x in arr:
        seen[x] = true
    return seen.keys()
```

**Step 2 — Run, verify RED.**

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_bot_decisions.gd -gexit
```

Expected: "Script not found" error on the preload.

**Step 3 — Implement minimum.** Create `scripts/match/bot_decisions.gd` with all 8 functions per signatures above.

**Step 4 — Run, verify GREEN.** All 15 tests pass.

**Step 5 — Commit.**

```
git add scripts/match/bot_decisions.gd tests/unit/test_bot_decisions.gd
git commit -F - <<'EOF'
feat(bots): BotDecisions static helpers + deterministic seeding

Pure functions for every bot decision point (wager, cash-out delay,
pull-out delay, card-cannon threshold, loadout pick, shop purchase,
event-picker choice). Each takes a seeded RandomNumberGenerator so
practice matches are reproducible via match_seed + bot peer_id.
EOF
```

---

## Task 2: host_submit_* methods on MatchController + event nodes

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Modify: `scripts/events/rocket_clash/rocket_clash_event.gd`
- Modify: `scripts/events/bomb_pot/bomb_pot_event.gd`
- Modify: `scripts/events/card_cannon/card_cannon_event.gd`
- Test:   `tests/unit/test_match_controller_host_submit.gd`

Add explicit-peer-id entry methods that bots use. Each method is host-only (push warning + return on non-host) and routes to the same internal logic as the existing `submit_*`/`_rpc_*` pair.

Pattern (for MatchController.submit_wager):

```gdscript
# Bot-friendly entry: takes explicit peer_id instead of inferring from
# multiplayer.get_unique_id(). Host-only — clients route via submit_wager.
func host_submit_wager(peer_id: int, amount: int) -> void:
    if not is_host:
        push_warning("host_submit_wager called on non-host")
        return
    _rpc_set_wager(peer_id, amount)
```

Mirror the pattern for:
- `host_submit_loadout(peer_id, loadout)` → calls `_rpc_loadout_set`
- `host_submit_card_play(peer_id, card_id, target_peer_id, params)` → calls `_rpc_card_play_requested`
- `host_submit_event_pick(peer_id, chosen_path)` → calls `_rpc_event_picker_choice`
- `host_submit_shop_buy(peer_id, card_id)` → calls `_rpc_shop_buy`
- `host_submit_shop_done(peer_id)` → calls `_rpc_shop_done`

For event nodes — same pattern, route to the existing RPC receivers:
- `RocketClashEvent.host_submit_cash_out(peer_id, mult_snapshot)` → calls `_rpc_cash_out_requested`
- `BombPotEvent.host_submit_pull_out(peer_id)` → calls `_rpc_pull_out_requested`
- `CardCannonEvent.host_submit_draw(peer_id)` → calls `_rpc_draw_requested`
- `CardCannonEvent.host_submit_lock(peer_id)` → calls `_rpc_lock_requested`

Each method needs a host-guard check.

**Tests** (`test_match_controller_host_submit.gd`): For each new method, verify (a) host-mode call routes through to state mutation; (b) non-host-mode call no-ops + push_warning fires.

**Steps:** RED → impl → GREEN → commit per the standard TDD pattern. Single commit at end:

```
feat(match): host_submit_* methods accept explicit peer_id

Bot-friendly entry points that bypass the multiplayer.get_unique_id()
inference in submit_*. Host-only; route to the same internal RPC
receivers (_rpc_set_wager, _rpc_loadout_set, etc.) for behavioral
parity. Required for Practice mode bots which share the local peer.
```

Expected new test count: ~10-14 tests across the 10 new methods.

---

## Task 3: BotController (signal wiring)

**Files:**
- Create: `scripts/match/bot_controller.gd`
- Test:   `tests/unit/test_bot_controller.gd`

Node-derived class. One instance per bot. Lifecycle: created by `MatchScene` for each bot seat after match starts; freed on `match_ended`.

```gdscript
extends Node

const BotDecisions = preload("res://scripts/match/bot_decisions.gd")

var controller       # MatchController-like
var bot_peer_id: int
var match_seed: int
var _rng: RandomNumberGenerator
var _scheduled_action_timer: Timer  # one-shot per event
var _cc_poll_timer: Timer            # repeating for Card Cannon draw/lock loop
var _cc_threshold: int               # locked at start of each Card Cannon event

func _ready() -> void:
    _rng = BotDecisions.rng_for_bot(match_seed, bot_peer_id)
    controller.bet_loadout_started.connect(_on_bet_loadout_started)
    controller.shop_opened.connect(_on_shop_opened)
    controller.event_picker_started.connect(_on_event_picker_started)
    controller.event_starting.connect(_on_event_starting)
    controller.match_ended.connect(_on_match_ended)
```

**Behaviors:**

- `_on_bet_loadout_started(active_peer_ids, max_per_player)`: if `bot_peer_id in active_peer_ids`, schedule a 100-500ms timer; on timeout, pick wager + loadout via BotDecisions, call `controller.host_submit_wager(...)` + `controller.host_submit_loadout(...)`.

- `_on_shop_opened(offered_card_ids)`: read offer costs via `CardRegistry.cost_for(card_id)`. Pick purchase via BotDecisions; if non-empty, call `controller.host_submit_shop_buy(bot_peer_id, card_id)`. Then call `controller.host_submit_shop_done(bot_peer_id)` after a small delay (let the buy resolve first).

- `_on_event_picker_started(picker_peer_id, options)`: if `picker_peer_id == bot_peer_id`, schedule a 500ms timer; pick path via BotDecisions; call `controller.host_submit_event_pick(bot_peer_id, chosen_path)`.

- `_on_event_starting(event_id, _event_index)`: dispatch on event_id:
  - `rocket_clash`: schedule a one-shot timer for `BotDecisions.pick_cash_out_delay_ms(_rng)`. On timeout, look up current event node via `controller._current_event_node` (add a `current_event_node` public getter), check it's a RocketClashEvent, call `event_node.host_submit_cash_out(bot_peer_id, event_node._current_multiplier_host())`. If the bot already busted (find_player(bot).busted_this_event), skip.
  - `bomb_pot`: schedule one-shot timer for `pick_pull_out_delay_ms`; on timeout, call `event_node.host_submit_pull_out(bot_peer_id)`.
  - `card_cannon`: lock `_cc_threshold = pick_card_cannon_threshold`. Start `_cc_poll_timer` (repeats every 700ms). On each tick: get bot's locked score from state, if locked → stop timer; else if total_score >= threshold → host_submit_lock; else → host_submit_draw.

- `_on_match_ended(_rankings)`: queue_free.

**Defensive guards:** every bot action checks (a) controller still valid, (b) match not ended, (c) bot still in match, (d) phase still appropriate. Avoid double-submission via a per-event-id "submitted_for_event" flag.

**Tests:** Use a `FakeController` Object that records `host_submit_*` calls. Drive signals manually and assert the correct calls happen.

**Steps:** standard TDD. Single commit at end:

```
feat(bots): BotController signal wiring + per-event timing

Subscribes to MatchController phase + shop + picker signals plus the
three event-node API surfaces. Dispatches BotDecisions outputs through
the new host_submit_* methods. Per-bot deterministic RNG seeded from
match_seed + peer_id. Card Cannon uses a repeating poll timer for the
draw/lock loop.
```

Expected ~12-18 new tests.

---

## Task 4: PracticeSession + main-menu entry + scene wiring

**Files:**
- Create: `scripts/net/practice_session.gd`
- Create: `scenes/practice_setup.tscn`
- Create: `scripts/ui/practice_setup_overlay.gd`
- Modify: `scripts/net/net_session_main.gd`
- Modify: `scripts/ui/main_menu.gd`
- Modify: `scripts/ui/match_scene.gd`
- Test:   `tests/unit/test_practice_session.gd`

**`PracticeSession.start(bot_count: int, seed: int = 0) -> void`** (static):

1. Build a MatchStart with seats: 1 human (peer_id=1, is_host=true, name="You") + N bots (peer_ids 1000..1000+N-1, is_host=false, name="Bot 1"…). host_peer_id=1. rng_seed = seed (or `Time.get_ticks_msec()` if 0).
2. Set `NetSessionMain.session.local_peer_id = 1` and stuff the MatchStart into `NetSessionMain.set_last_match_start(match_start)`.
3. Set `NetSessionMain.practice_mode = true`.
4. Transition: `get_tree().change_scene_to_file("res://scenes/match_scene.tscn")`.

**`practice_setup_overlay.gd`** wires the modal: bot count (SpinBox 1-7, default 3), seed (LineEdit, optional), Start button calls `PracticeSession.start(count, seed_or_0)`.

**`main_menu.gd`** — add "Practice vs Bots" button next to Host/Join. On press, instantiate the setup overlay scene as a child of the main menu (or use a single AcceptDialog modal).

**`match_scene.gd` changes:**
- Read `NetSessionMain.practice_mode` flag at the top of `_ready()`.
- When `practice_mode == true`: skip the `session.is_host` checks (always treat as host) and after `controller.start_match(match_start)`, instantiate one `BotController` per non-host seat:

```gdscript
if NetSessionMain.practice_mode:
    for seat in match_start.seats:
        if seat.is_host:
            continue
        var bc = BotController.new()
        bc.controller = controller
        bc.bot_peer_id = seat.peer_id
        bc.match_seed = match_start.rng_seed
        add_child(bc)
```

**`net_session_main.gd` changes:**
- Add `var practice_mode: bool = false`.
- Add `func set_last_match_start(ms) -> void`.
- Ensure `get_last_match_start()` returns the cached value.

**Tests** (`test_practice_session.gd`):
- `PracticeSession.start(3)` constructs a MatchStart with 4 seats (1 host + 3 bots).
- Bot peer_ids are 1000, 1001, 1002.
- Seed defaults to non-zero when unspecified.
- Caches MatchStart on NetSessionMain.

Static-formatter test pattern; no live scene needed. Use a fake NetSessionMain.

**Single commit at end:**

```
feat(practice): main-menu entry + scene wiring for bots-only mode

PracticeSession.start(bot_count, seed) builds a MatchStart with the
local human (peer_id=1) and N bots (peer_id 1000+) and routes through
the existing MatchScene. NetSessionMain gains practice_mode flag;
MatchScene spawns one BotController per bot seat when set.
```

Expected ~5-7 new tests.

---

## Task 5: Integration test

**File:**
- Create: `tests/integration/test_practice_match_runs_to_completion.gd`

**Goal:** Spin up a practice match with 1 human + 2 bots and a fixed seed. Run to `match_ended`. Assert no errors, all 5 events completed, rankings size == 3.

**Pattern:**

```gdscript
extends GutTest

const PracticeSession = preload("res://scripts/net/practice_session.gd")
const MatchController = preload("res://scripts/match/match_controller.gd")
const BotController = preload("res://scripts/match/bot_controller.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func test_practice_match_5_events_to_completion():
    var ms = _build_match_start(2, 42)
    var fake = FakeMultiplayerNode.new()
    var c = MatchController.new(true, fake)
    add_child_autofree(c)
    c.no_op_phase_delay_ms_override = 0
    c.resolution_step_delay_ms_override = 0
    
    var bots: Array = []
    for seat in ms.seats:
        if seat.is_host: continue
        var bc = BotController.new()
        bc.controller = c
        bc.bot_peer_id = seat.peer_id
        bc.match_seed = ms.rng_seed
        add_child_autofree(bc)
        bots.append(bc)
    
    # Also need a human bot for peer_id=1; for the integration test, give
    # the human a BotController too (so the match self-drives).
    var human = BotController.new()
    human.controller = c
    human.bot_peer_id = 1
    human.match_seed = ms.rng_seed
    add_child_autofree(human)
    
    var ended: bool = false
    var rankings_out: Array = []
    c.match_ended.connect(func(r): ended = true; rankings_out = r)
    
    c.start_match(ms)
    
    # Wait up to 30s for match_ended.
    var deadline = Time.get_ticks_msec() + 30000
    while not ended and Time.get_ticks_msec() < deadline:
        await get_tree().process_frame
    
    assert_true(ended, "match_ended did not fire within 30s")
    assert_eq(rankings_out.size(), 3)
```

This is a **slow** test (potentially seconds of wall-clock). Will live in `tests/integration/` not `tests/unit/`. CI integration suite isn't gated (PENDING-skip pattern is the established convention) so this test should run to completion when invoked but be acceptable as PENDING when controller setup fails.

**Single commit:**

```
test(practice): end-to-end practice match integration test

1 host + 2 bots, fixed seed 42, runs 5-event match to completion via
BotController self-driving on all 3 seats. Asserts match_ended fires
and rankings.size() == 3. Slow test — lives under tests/integration/.
```

---

## Task 6: Manual playtest checklist

After Task 5 passes:

- [ ] Run the project from the editor.
- [ ] Click "Practice vs Bots" on Main Menu.
- [ ] Pick 3 bots, seed 42, Start.
- [ ] Verify the match runs 5 events. Bots act on their own.
- [ ] Verify Announcer banners fire for bot card plays (Phase F coverage).
- [ ] Verify a bot taking a House Loan shows the +1 Heat (Phase E coverage).
- [ ] Verify the match-end overlay shows correctly with 4 ranked players.
- [ ] Quit, restart practice with the same seed → match should be deterministic (same crashes, same shop offers, same bot decisions).

No code changes for Task 6. Note any issues; queue up follow-ups in `project_riskroyal_followups.md`.

---

## Out of scope (deferred)

- Heuristic bot personalities (cautious/greedy/aggressive). Foundation is in `BotDecisions` — swap implementations behind the same signatures.
- Humans + bots in multiplayer lobbies.
- Difficulty curves.
- Bot bounty placement (auto-bounties already cover the placed-bounty surface; bots manually placing via card play is rare and can be deferred).
- Bot tutorials (annotated bot behaviors that explain the game).

## Expected final state

- Test count: ~46-58 new tests (15 BotDecisions + 14 host_submit + 18 BotController + 7 PracticeSession + 1 integration) → 842-854 total unit + 10 integration.
- New files: 8 (`bot_decisions.gd`, `bot_controller.gd`, `practice_session.gd`, `practice_setup.tscn`, `practice_setup_overlay.gd`, 4 test files).
- Modified files: 5 (`match_controller.gd`, 3 event scripts, `match_scene.gd`, `main_menu.gd`, `net_session_main.gd`).
- 5 commits total.
