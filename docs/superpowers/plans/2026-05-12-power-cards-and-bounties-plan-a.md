# Power Cards & Bounties — Plan A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the foundation of sub-project #4 (Power Cards & Bounties) — bounty system (auto Leader + Heat with heat-scaling, plus resolution), 6 pre-event power cards (Insurance, Heat Shield, Multiplier Booster, Double or Nothing, Late Cash, Underdog Odds) wired through a card-play RPC pipeline, an upgraded SHOP phase with buy-from-offer mechanics, a starter pack distribution at match start, and three new HUD widgets (LoadoutOverlay, ShopOverlay, BountyPanel). After Plan A merges, the match runs end-to-end with bounties + 6 cards + shop; Plan B adds the remaining 6 cards (Cash-Out Jammer, Emergency Eject, Heat Spike, Wager Tax, Place Bounty, Copycat Bet) plus a MatchController refactor.

**Architecture:** Three layers building on sub-projects #2-3. (1) Pure-data card layer — `CardRegistry` static const dictionary plus one `static apply(ctx, target, params) -> Dictionary` per card. (2) State layer — `MatchPlayer.hand/loadout/played_this_event`, `MatchState.bounties/current_shop_offer/shop_done_peers/event_modifiers/pending_card_effects`, `EventContext.event_modifiers`, `Bounty` data class. (3) Control layer — `MatchController` gains card-play RPC pipeline, loadout management, SHOP async handler, bounty auto-placement + resolution, effect dispatcher. UI widgets follow the established static-formatter pattern from sub-projects #2-3.

**Tech Stack:** Godot 4.6, GDScript, GUT testing framework, `@rpc("any_peer", "call_local", "reliable")` for client→host requests (mirror of sub-project #3's pattern). Uses existing `FakeMultiplayerNode` test fake.

**Parent spec:** [`docs/superpowers/specs/2026-05-12-power-cards-and-bounties-design.md`](../specs/2026-05-12-power-cards-and-bounties-design.md). Re-read §5 (Architecture), §6 (Components), §7 (Data Flow), §9 (Testing) before starting.

**Companion plans (already implemented, on main):**
- `2026-05-11-match-engine.md` — sub-project #2 Plan A (headless engine)
- `2026-05-11-match-ui-and-integration.md` — sub-project #2 Plan B (HUD + scheduler + RPC + integration)
- `2026-05-12-rocket-clash-event.md` — sub-project #3 (Rocket Clash + BET_LOADOUT upgrade)

**Baseline:** 292 unit + 3 integration after sub-project #3. This plan targets 387 unit + 3 integration after Task 18 (95 new unit tests; no new integration test in Plan A — Plan B adds one).

---

## File Structure

```
scripts/
  cards/                                   # NEW DIRECTORY
    card_registry.gd                       # NEW: static-only library + helpers
    effects/                               # NEW DIRECTORY
      insurance.gd                         # NEW
      heat_shield.gd                       # NEW
      multiplier_booster.gd                # NEW
      double_or_nothing.gd                 # NEW
      late_cash.gd                         # NEW
      underdog_odds.gd                     # NEW
  match/
    bounty.gd                              # NEW: RefCounted data class + statics
    match_player.gd                        # MODIFY: hand/loadout/played_this_event
    match_state.gd                         # MODIFY: bounties + shop + event_modifiers + pending_card_effects
    match_config.gd                        # MODIFY: 9 new constants
    match_controller.gd                    # MODIFY: card play, loadout, SHOP, bounties, dispatcher
  events/
    event_context.gd                       # MODIFY: event_modifiers field
  ui/
    loadout_overlay.gd                     # NEW
    shop_overlay.gd                        # NEW
    bounty_panel.gd                        # NEW
    match_scene.gd                         # MODIFY: wire 3 new signals + 3 new slots
scenes/
  ui/
    loadout_overlay.tscn                   # NEW
    shop_overlay.tscn                      # NEW
    bounty_panel.tscn                      # NEW
  match_scene.tscn                         # MODIFY: add LoadoutSlot, ShopSlot, BountyPanelSlot
tests/
  unit/
    test_match_config_card_constants.gd                # NEW: Task 1
    test_match_player_card_fields.gd                   # NEW: Task 1
    test_match_state_card_fields.gd                    # NEW: Task 2
    test_event_context_event_modifiers.gd              # NEW: Task 3
    test_bounty.gd                                     # NEW: Task 4
    test_match_controller_bounties.gd                  # NEW: Task 5
    test_card_registry.gd                              # NEW: Task 6
    test_card_insurance.gd                             # NEW: Task 7
    test_card_heat_shield.gd                           # NEW: Task 7
    test_card_multiplier_booster.gd                    # NEW: Task 7
    test_card_late_cash.gd                             # NEW: Task 8
    test_card_underdog_odds.gd                         # NEW: Task 8
    test_card_double_or_nothing.gd                     # NEW: Task 9
    test_match_controller_loadout.gd                   # NEW: Task 10
    test_match_controller_card_play.gd                 # NEW: Task 11
    test_rocket_clash_event_modifiers.gd               # NEW: Task 12
    test_match_controller_starter_pack.gd              # NEW: Task 13
    test_match_controller_shop.gd                      # NEW: Task 14
    test_loadout_overlay.gd                            # NEW: Task 15
    test_shop_overlay.gd                               # NEW: Task 16
    test_bounty_panel.gd                               # NEW: Task 17
```

**Per-file responsibility:**

- `card_registry.gd` — static `const CARDS` dict, `get_card`, `apply_card`, `starter_pool`, `shop_pool`, `heat_multiplier` statics. No instance state.
- `cards/effects/<card_id>.gd` (6 files Plan A) — each is a single `static apply(context, target_peer_id, params) -> Dictionary`. Pure functions; no SceneTree, no controller.
- `bounty.gd` — RefCounted data class (origin, target, condition, reward_chips, placed_by, placed_at_event, placed_at_target_heat). Statics: `satisfies(bounty, result, claimant_id)`, `compute_reward(bounty)`, `to_dict() / from_dict()`.
- `match_player.gd` — adds `hand: Array`, `loadout: Array`, `played_this_event: Array` with round-trip.
- `match_state.gd` — adds `bounties: Array`, `current_shop_offer: Array`, `shop_done_peers: Array`, `event_modifiers: Dictionary`, `pending_card_effects: Array` with round-trip.
- `match_config.gd` — appends 9 constants (SHOP_TIMEOUT_SEC, MAX_HAND_SIZE, MAX_LOADOUT_SIZE, STARTER_PACK_SIZE, SHOP_OFFER_SIZE, CARD_COST_COMMON, CARD_COST_RARE, CARD_COST_ROYAL, BOUNTY_BASE_REWARD).
- `event_context.gd` — adds `event_modifiers: Dictionary = {}` field with round-trip.
- `match_controller.gd` — five new responsibilities (card play pipeline, loadout management, SHOP async handler, bounty auto-placement + resolution, effect dispatcher). ~400 lines of additions; Plan B will refactor.
- `loadout_overlay.gd` + `.tscn` — wager input panel from sub-project #3 stays; this is a SIBLING widget shown alongside during BET_LOADOUT. Renders hand row + loadout slots + target picker. Static formatters: `format_card_label`, `is_card_playable`, `available_targets`.
- `shop_overlay.gd` + `.tscn` — shown during SHOP phase. 3 offered cards + Buy buttons + Done button. Static formatters: `format_shop_offer`, `can_afford`.
- `bounty_panel.gd` + `.tscn` — shown alongside PlayerPanels. Renders active bounties. Static formatter: `format_bounty_summary`.

## Conventions

- **TDD strictly:** failing test → run-fail → minimum implementation → run-pass → commit. Same as sub-projects #2-3.
- **Static-formatter UI testing pattern:** widget logic is unit-tested via `format_*` / `is_*` / `can_*` static helpers; scene wiring is verified by Plan B's integration test and manual playtest.
- **Test session injection:** UI scripts default `controller` / `session` to `null` in `_ready()`; tests set the property before adding to the tree.
- **RPC test seam:** controller/widgets take a `multiplayer_node` constructor arg (or settable property). Pass `null` to no-op, or inject a `FakeMultiplayerNode` (from sub-project #2 Plan B) to record `rpc(...)` calls.
- **`@rpc("any_peer", "call_local", "reliable")` for client→host requests.** Per sub-project #3's C1 fix, the `call_local` mode is required so the host's own calls also execute locally; the `if not is_host: return` guards prevent clients from running host-only logic. Mirror of established pattern.
- **Detached-controller test pattern:** sub-project #2's `is_inside_tree()` guard pattern. When detached, skip Timer/SceneTree-dependent paths.
- **Commit prefixes:** `feat(client):`, `test(client):`, `chore(client):`, `refactor(client):`, `fix(client):`, `docs(client):`. `(client)` scope matches prior work.
- **Tabs for indentation in `.gd` files.** No `class_name` registration; use `preload(...)` discipline.
- **PowerShell apostrophe quirk:** when commit message has apostrophes, fall back to `git commit -F <tempfile>` with `Set-Content -Encoding utf8`.
- **Co-author footer on every commit:**
  ```
  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  ```
- **GUT runner:**
  ```
  godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
  ```
- **`godot` is on PATH** — resolves to `C:\Users\whann\Tools\godot-voxel-1.6\godot.exe`.

---

## Phase 1: State foundation

Three tasks adding data fields to existing classes. Trivial round-trip tests + default values. Prerequisite for everything else.

### Task 1: MatchConfig constants + MatchPlayer card fields

Adds the 9 sub-project-#4 constants to MatchConfig and three new fields (`hand`, `loadout`, `played_this_event`) to MatchPlayer.

**Files:**
- Modify: `scripts/match/match_config.gd`
- Modify: `scripts/match/match_player.gd`
- Create: `tests/unit/test_match_config_card_constants.gd`
- Create: `tests/unit/test_match_player_card_fields.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_config_card_constants.gd`:
```gdscript
extends GutTest

const MatchConfig = preload("res://scripts/match/match_config.gd")

func test_shop_timeout_sec():
    assert_eq(MatchConfig.SHOP_TIMEOUT_SEC, 10)

func test_max_hand_size():
    assert_eq(MatchConfig.MAX_HAND_SIZE, 5)

func test_max_loadout_size():
    assert_eq(MatchConfig.MAX_LOADOUT_SIZE, 2)

func test_starter_pack_size():
    assert_eq(MatchConfig.STARTER_PACK_SIZE, 3)

func test_shop_offer_size():
    assert_eq(MatchConfig.SHOP_OFFER_SIZE, 3)

func test_card_cost_common():
    assert_eq(MatchConfig.CARD_COST_COMMON, 50)

func test_card_cost_rare():
    assert_eq(MatchConfig.CARD_COST_RARE, 150)

func test_card_cost_royal():
    assert_eq(MatchConfig.CARD_COST_ROYAL, 400)

func test_bounty_base_reward():
    assert_eq(MatchConfig.BOUNTY_BASE_REWARD, 150)
```

`tests/unit/test_match_player_card_fields.gd`:
```gdscript
extends GutTest

const MatchPlayer = preload("res://scripts/match/match_player.gd")

func test_hand_defaults_empty():
    var p = MatchPlayer.new()
    assert_eq(p.hand, [])

func test_loadout_defaults_empty():
    var p = MatchPlayer.new()
    assert_eq(p.loadout, [])

func test_played_this_event_defaults_empty():
    var p = MatchPlayer.new()
    assert_eq(p.played_this_event, [])

func test_card_fields_round_trip():
    var p = MatchPlayer.new()
    p.peer_id = 1
    p.hand = ["insurance", "heat_shield", "multiplier_booster"]
    p.loadout = ["insurance", "heat_shield"]
    p.played_this_event = ["insurance"]
    var d = p.to_dict()
    var p2 = MatchPlayer.from_dict(d)
    assert_eq(p2.hand, ["insurance", "heat_shield", "multiplier_booster"])
    assert_eq(p2.loadout, ["insurance", "heat_shield"])
    assert_eq(p2.played_this_event, ["insurance"])
```

- [ ] **Step 2: Run, watch fail**

Expected: missing constants on MatchConfig; missing fields on MatchPlayer.

- [ ] **Step 3: Implement**

Append to `scripts/match/match_config.gd`:
```gdscript
# Sub-project #4 (Power Cards & Bounties)
const SHOP_TIMEOUT_SEC: int = 10
const MAX_HAND_SIZE: int = 5
const MAX_LOADOUT_SIZE: int = 2
const STARTER_PACK_SIZE: int = 3
const SHOP_OFFER_SIZE: int = 3
const CARD_COST_COMMON: int = 50
const CARD_COST_RARE: int = 150
const CARD_COST_ROYAL: int = 400
const BOUNTY_BASE_REWARD: int = 150
```

In `scripts/match/match_player.gd`, add three fields and extend `to_dict` / `from_dict`:
```gdscript
# Add near existing fields:
var hand: Array = []
var loadout: Array = []
var played_this_event: Array = []
```

Update `to_dict`:
```gdscript
func to_dict() -> Dictionary:
    return {
        "peer_id": peer_id,
        "seat_index": seat_index,
        "name": name,
        "color_index": color_index,
        "chips": chips,
        "crowns": crowns,
        "heat": heat,
        "is_active_this_event": is_active_this_event,
        "hand": hand.duplicate(),
        "loadout": loadout.duplicate(),
        "played_this_event": played_this_event.duplicate(),
    }
```

Update `from_dict`:
```gdscript
static func from_dict(d: Dictionary) -> RefCounted:
    var p = load("res://scripts/match/match_player.gd").new()
    p.peer_id = d.get("peer_id", 0)
    p.seat_index = d.get("seat_index", -1)
    p.name = d.get("name", "")
    p.color_index = d.get("color_index", -1)
    p.chips = d.get("chips", 0)
    p.crowns = d.get("crowns", 0)
    p.heat = d.get("heat", 0)
    p.is_active_this_event = d.get("is_active_this_event", true)
    p.hand = d.get("hand", []).duplicate()
    p.loadout = d.get("loadout", []).duplicate()
    p.played_this_event = d.get("played_this_event", []).duplicate()
    return p
```

- [ ] **Step 4: Run, watch pass**

Expected: 305/305 tests pass (292 prior + 13 new — 9 constants + 4 field tests).

- [ ] **Step 5: Commit**

```
feat(client): sub-project #4 constants + MatchPlayer card fields

MatchConfig: 9 new constants (SHOP_TIMEOUT_SEC, MAX_HAND_SIZE,
MAX_LOADOUT_SIZE, STARTER_PACK_SIZE, SHOP_OFFER_SIZE, CARD_COST_COMMON,
CARD_COST_RARE, CARD_COST_ROYAL, BOUNTY_BASE_REWARD).

MatchPlayer: hand (cards owned, max 5), loadout (cards active this event,
max 2), played_this_event (cards already played, cleared at HOUSE_REVEAL).
All default empty arrays, round-trip via to_dict/from_dict with .duplicate
to avoid reference aliasing.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 2: MatchState card + bounty + shop fields

Adds the 5 new state fields. Round-trip preservation.

**Files:**
- Modify: `scripts/match/match_state.gd`
- Create: `tests/unit/test_match_state_card_fields.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_state_card_fields.gd`:
```gdscript
extends GutTest

const MatchState = preload("res://scripts/match/match_state.gd")

func test_bounties_defaults_empty():
    var s = MatchState.new()
    assert_eq(s.bounties, [])

func test_current_shop_offer_defaults_empty():
    var s = MatchState.new()
    assert_eq(s.current_shop_offer, [])

func test_shop_done_peers_defaults_empty():
    var s = MatchState.new()
    assert_eq(s.shop_done_peers, [])

func test_event_modifiers_defaults_empty_dict():
    var s = MatchState.new()
    assert_eq(s.event_modifiers, {})

func test_pending_card_effects_defaults_empty():
    var s = MatchState.new()
    assert_eq(s.pending_card_effects, [])

func test_round_trip_preserves_new_fields():
    var s = MatchState.new()
    s.bounties = [{"origin": "leader", "target": 1}]  # Bounty.to_dict shape (Task 4 produces real Bounty)
    s.current_shop_offer = ["insurance", "heat_shield"]
    s.shop_done_peers = [1, 2]
    s.event_modifiers = {1: {"insurance_pre": true}}
    s.pending_card_effects = [{"type": "wager_tax", "source": 1, "target": 2}]
    var d = s.to_dict()
    var s2 = MatchState.from_dict(d)
    assert_eq(s2.bounties.size(), 1)
    assert_eq(s2.bounties[0].get("origin", ""), "leader")
    assert_eq(s2.current_shop_offer, ["insurance", "heat_shield"])
    assert_eq(s2.shop_done_peers, [1, 2])
    assert_eq(s2.event_modifiers.get(1, {}).get("insurance_pre", false), true)
    assert_eq(s2.pending_card_effects.size(), 1)
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/match/match_state.gd`, add five fields near existing ones (pending_wagers is already there from sub-project #3):
```gdscript
var bounties: Array = []
var current_shop_offer: Array = []
var shop_done_peers: Array = []
var event_modifiers: Dictionary = {}
var pending_card_effects: Array = []
```

Update `to_dict` to include the new fields with `.duplicate(true)` for nested-dict safety:
```gdscript
func to_dict() -> Dictionary:
    var player_dicts: Array = []
    for p in players:
        player_dicts.append(p.to_dict())
    return {
        "event_index": event_index,
        "phase": phase,
        "players": player_dicts,
        "current_event_id": current_event_id,
        "rng_seed": rng_seed,
        "pending_wagers": pending_wagers.duplicate(true),
        "bounties": bounties.duplicate(true),
        "current_shop_offer": current_shop_offer.duplicate(),
        "shop_done_peers": shop_done_peers.duplicate(),
        "event_modifiers": event_modifiers.duplicate(true),
        "pending_card_effects": pending_card_effects.duplicate(true),
    }
```

Update `from_dict`:
```gdscript
static func from_dict(d: Dictionary) -> RefCounted:
    var s = load("res://scripts/match/match_state.gd").new()
    s.event_index = d.get("event_index", 0)
    s.phase = d.get("phase", MatchPhase.Phase.HOUSE_REVEAL)
    s.current_event_id = d.get("current_event_id", "")
    s.rng_seed = d.get("rng_seed", 0)
    s.pending_wagers = d.get("pending_wagers", {}).duplicate(true)
    s.bounties = d.get("bounties", []).duplicate(true)
    s.current_shop_offer = d.get("current_shop_offer", []).duplicate()
    s.shop_done_peers = d.get("shop_done_peers", []).duplicate()
    s.event_modifiers = d.get("event_modifiers", {}).duplicate(true)
    s.pending_card_effects = d.get("pending_card_effects", []).duplicate(true)
    s.players = []
    for raw in d.get("players", []):
        s.players.append(MatchPlayer.from_dict(raw))
    return s
```

- [ ] **Step 4: Run, watch pass**

Expected: 311/311 tests pass (305 prior + 6 new).

- [ ] **Step 5: Commit**

```
feat(client): MatchState fields for bounties, shop, card effects

bounties (Array of Bounty dicts, populated by Task 5+),
current_shop_offer (Array of card_ids offered in active SHOP visit),
shop_done_peers (peer_ids who have finalized SHOP this visit),
event_modifiers (per-peer dict of pre-event card flags, e.g.
{1: {"insurance_pre": true, "wager_multiplier": 1.25}}),
pending_card_effects (Array of post-event mutations from
Plan B cards like Wager Tax + Heat Spike).

All default empty; round-trip via to_dict/from_dict with .duplicate(true)
on nested structures to avoid reference aliasing.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 3: EventContext.event_modifiers field

The new field that carries per-player pre-event card flags from state into the event.

**Files:**
- Modify: `scripts/events/event_context.gd`
- Create: `tests/unit/test_event_context_event_modifiers.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_event_context_event_modifiers.gd`:
```gdscript
extends GutTest

const EventContext = preload("res://scripts/events/event_context.gd")

func test_event_modifiers_defaults_empty():
    var ctx = EventContext.new()
    assert_eq(ctx.event_modifiers, {})

func test_event_modifiers_round_trip():
    var ctx = EventContext.new()
    ctx.event_modifiers = {
        1: {"insurance_pre": true, "wager_multiplier": 1.25},
        2: {"heat_shield": true},
    }
    var d = ctx.to_dict()
    var ctx2 = EventContext.from_dict(d)
    assert_eq(ctx2.event_modifiers.get(1, {}).get("insurance_pre", false), true)
    assert_almost_eq(float(ctx2.event_modifiers.get(1, {}).get("wager_multiplier", 0.0)), 1.25, 0.001)
    assert_eq(ctx2.event_modifiers.get(2, {}).get("heat_shield", false), true)
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/events/event_context.gd`, add the field near `is_host`:
```gdscript
var event_modifiers: Dictionary = {}  # NEW: per-peer-id pre-event card flags
```

Update `to_dict`:
```gdscript
func to_dict() -> Dictionary:
    var player_dicts: Array = []
    for p in players:
        player_dicts.append(p.to_dict())
    return {
        "players": player_dicts,
        "event_index": event_index,
        "rng_seed": rng_seed,
        "wagers": wagers,
        "is_host": is_host,
        "event_modifiers": event_modifiers.duplicate(true),
    }
```

Update `from_dict`:
```gdscript
static func from_dict(d: Dictionary) -> RefCounted:
    var c = load("res://scripts/events/event_context.gd").new()
    c.event_index = d.get("event_index", 0)
    c.rng_seed = d.get("rng_seed", 0)
    c.wagers = d.get("wagers", {})
    c.is_host = d.get("is_host", false)
    c.event_modifiers = d.get("event_modifiers", {}).duplicate(true)
    c.players = []
    for raw in d.get("players", []):
        c.players.append(MatchPlayer.from_dict(raw))
    return c
```

- [ ] **Step 4: Run, watch pass**

Expected: 313/313 tests pass (311 prior + 2 new).

- [ ] **Step 5: Commit**

```
feat(client): EventContext.event_modifiers for per-player card flags

Real events (sub-project #4 onwards) need per-player pre-event card flags
threaded into compute_event_result. event_modifiers is a Dictionary keyed
by peer_id; values are dicts of flag_name -> value. Defaults empty;
round-trips via to_dict/from_dict with .duplicate(true).

MatchController._build_event_context (Task 11) will populate this from
state.event_modifiers at MAIN_EVENT entry.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 2: Bounty system

### Task 4: Bounty data class + static helpers

The Bounty RefCounted with `satisfies` and `compute_reward` statics. Pure-math TDD surface.

**Files:**
- Create: `scripts/match/bounty.gd`
- Create: `tests/unit/test_bounty.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_bounty.gd`:
```gdscript
extends GutTest

const Bounty = preload("res://scripts/match/bounty.gd")
const EventResult = preload("res://scripts/events/event_result.gd")

func _make_bounty(origin: String, target: int, target_heat: int = 0) -> RefCounted:
    var b = Bounty.new()
    b.origin = origin
    b.target = target
    b.condition = "bust"
    b.reward_chips = 150
    b.placed_by = 0
    b.placed_at_event = 1
    b.placed_at_target_heat = target_heat
    return b

func _make_result_with_bust(target_peer_id: int, claimant_peer_id: int) -> RefCounted:
    var r = EventResult.new()
    r.per_player[target_peer_id] = {"chip_delta": -100, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0}
    r.per_player[claimant_peer_id] = {"chip_delta": 100, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 2.0}
    return r

func test_defaults():
    var b = Bounty.new()
    assert_eq(b.origin, "")
    assert_eq(b.target, 0)
    assert_eq(b.condition, "")
    assert_eq(b.reward_chips, 0)
    assert_eq(b.placed_by, 0)
    assert_eq(b.placed_at_event, 0)
    assert_eq(b.placed_at_target_heat, 0)

func test_round_trip():
    var b = _make_bounty("leader", 1, 4)
    var d = b.to_dict()
    var b2 = Bounty.from_dict(d)
    assert_eq(b2.origin, "leader")
    assert_eq(b2.target, 1)
    assert_eq(b2.condition, "bust")
    assert_eq(b2.placed_at_target_heat, 4)

func test_satisfies_bust_condition_target_busted():
    var b = _make_bounty("leader", 1)
    var r = _make_result_with_bust(1, 2)
    assert_true(Bounty.satisfies(b, r, 2))

func test_satisfies_excludes_self_claim():
    var b = _make_bounty("leader", 1)
    var r = _make_result_with_bust(1, 2)
    assert_false(Bounty.satisfies(b, r, 1), "target cannot claim their own bounty")

func test_satisfies_excludes_busted_claimant():
    # Claimant 2 also busted; cannot claim
    var b = _make_bounty("leader", 1)
    var r = EventResult.new()
    r.per_player[1] = {"chip_delta": -100, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0}
    r.per_player[2] = {"chip_delta": -100, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0}
    assert_false(Bounty.satisfies(b, r, 2), "busted claimant cannot claim")

func test_satisfies_target_not_busted():
    var b = _make_bounty("leader", 1)
    var r = EventResult.new()
    r.per_player[1] = {"chip_delta": 200, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 2.0}
    r.per_player[2] = {"chip_delta": 100, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 1.5}
    assert_false(Bounty.satisfies(b, r, 2), "target survived; bounty condition not met")

func test_compute_reward_no_heat_bonus():
    var b = _make_bounty("leader", 1, 0)
    b.reward_chips = 150
    assert_eq(Bounty.compute_reward(b), 150)

func test_compute_reward_heat_band_noticed():
    var b = _make_bounty("heat", 1, 4)  # Heat 3-5 -> +25%
    b.reward_chips = 150
    assert_eq(Bounty.compute_reward(b), 187)  # 150 * 1.25 = 187.5 -> int truncates to 187

func test_compute_reward_heat_band_hot_seat():
    var b = _make_bounty("heat", 1, 7)  # Heat 6-8 -> +50%
    b.reward_chips = 150
    assert_eq(Bounty.compute_reward(b), 225)  # 150 * 1.5

func test_compute_reward_heat_band_public_enemy():
    var b = _make_bounty("heat", 1, 10)  # Heat 9-10 -> +100%
    b.reward_chips = 150
    assert_eq(Bounty.compute_reward(b), 300)  # 150 * 2.0
```

- [ ] **Step 2: Run, watch fail**

Expected: Bounty preload error (file doesn't exist).

- [ ] **Step 3: Implement**

Create `scripts/match/bounty.gd`:
```gdscript
# Bounty data class. Auto-placed at HOUSE_REVEAL (Leader + Heat) or
# manually placed via the Place Bounty card. Resolved at the end of
# BOUNTY_HEAT_UPDATE after heat application. Reward scales by Heat at
# placement time (captured in placed_at_target_heat) so Heat Shield can't
# suppress bounty rewards.
extends RefCounted

var origin: String = ""            # "leader" | "heat" | "placed"
var target: int = 0                # peer_id
var condition: String = ""         # "bust" (only condition in MVP)
var reward_chips: int = 0          # base reward (pre-heat-multiplier)
var placed_by: int = 0             # peer_id of placer; 0 for auto
var placed_at_event: int = 0       # event_index at placement
var placed_at_target_heat: int = 0 # target's heat at placement time

func to_dict() -> Dictionary:
    return {
        "origin": origin,
        "target": target,
        "condition": condition,
        "reward_chips": reward_chips,
        "placed_by": placed_by,
        "placed_at_event": placed_at_event,
        "placed_at_target_heat": placed_at_target_heat,
    }

static func from_dict(d: Dictionary) -> RefCounted:
    var b = load("res://scripts/match/bounty.gd").new()
    b.origin = d.get("origin", "")
    b.target = int(d.get("target", 0))
    b.condition = d.get("condition", "")
    b.reward_chips = int(d.get("reward_chips", 0))
    b.placed_by = int(d.get("placed_by", 0))
    b.placed_at_event = int(d.get("placed_at_event", 0))
    b.placed_at_target_heat = int(d.get("placed_at_target_heat", 0))
    return b

# Returns true if the claimant satisfies the bounty against the given
# event result. Claimant must not be the target and must not have busted.
static func satisfies(bounty, result, claimant_peer_id: int) -> bool:
    if claimant_peer_id == bounty.target:
        return false
    if result.bust_for(claimant_peer_id):
        return false
    match bounty.condition:
        "bust":
            return result.bust_for(bounty.target)
        _:
            return false

# Returns the heat-scaled reward. Uses placed_at_target_heat captured
# at placement so Heat Shield (which halves heat_delta during the event)
# doesn't reduce the bounty payout.
static func compute_reward(bounty) -> int:
    return int(bounty.reward_chips * _heat_multiplier(bounty.placed_at_target_heat))

# Heat-bounty scaling per design doc §6.5
static func _heat_multiplier(heat: int) -> float:
    if heat <= 2:
        return 1.0
    if heat <= 5:
        return 1.25
    if heat <= 8:
        return 1.5
    return 2.0
```

- [ ] **Step 4: Run, watch pass**

Expected: 324/324 tests pass (313 prior + 11 new — 2 default/round-trip + 4 satisfies + 4 compute_reward + 1 from the round-trip combined).

(Note: actual count is 10 new tests in the file above. Recount carefully — 1 default, 1 round-trip, 4 satisfies, 4 compute_reward = 10. Adjust expected to 323.)

Run the suite. Expected: 323/323 tests pass.

- [ ] **Step 5: Commit**

```
feat(client): Bounty data class + satisfies/compute_reward statics

RefCounted data class with origin/target/condition/reward_chips/placed_by/
placed_at_event/placed_at_target_heat. Round-trip via to_dict/from_dict.

Static satisfies(bounty, result, claimant_id) gates: claimant != target,
claimant didn't bust, condition holds (MVP supports "bust" only).

Static compute_reward(bounty) applies _heat_multiplier per design 6.5:
+25%/+50%/+100% at heat bands 3-5/6-8/9-10. Uses placed_at_target_heat
captured at placement so Heat Shield can't suppress rewards.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 5: MatchController bounty auto-placement + resolution

Auto-places Leader + Heat bounties at HOUSE_REVEAL of events ≥1, resolves bounties in BOUNTY_HEAT_UPDATE after heat application, broadcasts via 3 new RPCs.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_bounties.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_controller_bounties.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const EventResult = preload("res://scripts/events/event_result.gd")
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

func _new_host_with_fake() -> Dictionary:
    var fake = FakeMultiplayerNode.new()
    var c = MatchController.new(true, fake)
    c.no_op_phase_delay_ms_override = 0
    c.start_match(_build_match_start(2))
    return {"controller": c, "fake": fake}

func test_auto_place_bounties_skipped_at_event_zero():
    var d = _new_host_with_fake()
    var c = d.controller
    c.state.event_index = 0
    c._auto_place_bounties()
    assert_eq(c.state.bounties.size(), 0, "event 0: no auto-placement")

func test_auto_place_bounties_places_leader_and_heat():
    var d = _new_host_with_fake()
    var c = d.controller
    # Make P1 the chip leader and P2 the heat leader
    c.state.players[0].chips = 1000
    c.state.players[1].chips = 500
    c.state.players[1].heat = 6
    c.state.event_index = 2
    c._auto_place_bounties()
    assert_eq(c.state.bounties.size(), 2)
    var origins = [c.state.bounties[0].origin, c.state.bounties[1].origin]
    assert_true("leader" in origins)
    assert_true("heat" in origins)

func test_auto_placed_leader_targets_chip_leader():
    var d = _new_host_with_fake()
    var c = d.controller
    c.state.players[0].chips = 500
    c.state.players[1].chips = 900
    c.state.event_index = 1
    c._auto_place_bounties()
    var leader_bounty = null
    for b in c.state.bounties:
        if b.origin == "leader":
            leader_bounty = b
            break
    assert_not_null(leader_bounty)
    assert_eq(leader_bounty.target, 2, "P2 has more chips -> leader bounty targets P2")

func test_auto_placed_heat_captures_target_heat():
    var d = _new_host_with_fake()
    var c = d.controller
    c.state.players[1].heat = 7
    c.state.event_index = 1
    c._auto_place_bounties()
    var heat_bounty = null
    for b in c.state.bounties:
        if b.origin == "heat":
            heat_bounty = b
            break
    assert_not_null(heat_bounty)
    assert_eq(heat_bounty.placed_at_target_heat, 7)

func test_resolve_bounties_awards_single_claimant():
    var d = _new_host_with_fake()
    var c = d.controller
    # P1 has leader bounty on them; P2 busts P1
    var Bounty = load("res://scripts/match/bounty.gd")
    var b = Bounty.new()
    b.origin = "leader"; b.target = 1; b.condition = "bust"
    b.reward_chips = 150; b.placed_at_target_heat = 0
    c.state.bounties = [b]
    var result = EventResult.new()
    result.per_player[1] = {"chip_delta": -100, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0}
    result.per_player[2] = {"chip_delta": 100, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 2.0}
    var p2_chips_before = c.state.players[1].chips
    c._resolve_bounties(result)
    assert_eq(c.state.players[1].chips, p2_chips_before + 150, "P2 collected 150 bounty")
    assert_eq(c.state.bounties, [], "bounties cleared after resolution")

func test_resolve_bounties_splits_on_tie():
    # 3 players. P1 is target; P2 and P3 both survived; P1 busted.
    var d = _new_host_with_fake()
    var c = d.controller
    var p3 = MatchPlayer.new()
    p3.peer_id = 3; p3.name = "P3"; p3.chips = 100
    c.state.players.append(p3)
    var Bounty = load("res://scripts/match/bounty.gd")
    var b = Bounty.new()
    b.origin = "leader"; b.target = 1; b.condition = "bust"
    b.reward_chips = 150; b.placed_at_target_heat = 0
    c.state.bounties = [b]
    var result = EventResult.new()
    result.per_player[1] = {"chip_delta": -100, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0}
    result.per_player[2] = {"chip_delta": 100, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 2.0}
    result.per_player[3] = {"chip_delta": 100, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": 1.5}
    var p2_chips_before = c.state.players[1].chips
    var p3_chips_before = c.state.players[2].chips
    c._resolve_bounties(result)
    assert_eq(c.state.players[1].chips, p2_chips_before + 75, "split: P2 gets 75")
    assert_eq(c.state.players[2].chips, p3_chips_before + 75, "split: P3 gets 75")
```

- [ ] **Step 2: Run, watch fail**

Expected: `_auto_place_bounties`, `_resolve_bounties` missing.

- [ ] **Step 3: Implement**

In `scripts/match/match_controller.gd`, add at the top with the other preloads:
```gdscript
const Bounty = preload("res://scripts/match/bounty.gd")
```

Add signals near the existing signals:
```gdscript
signal bounty_placed(bounty_dict: Dictionary)
signal bounty_claimed(claimant_peer_id: int, bounty_dict: Dictionary, reward_chips: int)
signal bounty_unclaimed(bounty_dict: Dictionary)
```

Add the bounty methods (place near `_process_bounty_heat_update`):
```gdscript
func _auto_place_bounties() -> void:
    if not is_host:
        return
    if state.event_index == 0:
        return  # No auto-placement on the very first event (no rankings yet)
    state.bounties = []
    var leader_id = _find_chip_leader_peer_id()
    var heat_id = _find_heat_leader_peer_id()
    var leader_target = state.find_player(leader_id)
    var heat_target = state.find_player(heat_id)
    var leader_bounty = Bounty.new()
    leader_bounty.origin = "leader"
    leader_bounty.target = leader_id
    leader_bounty.condition = "bust"
    leader_bounty.reward_chips = MatchConfig.BOUNTY_BASE_REWARD
    leader_bounty.placed_at_event = state.event_index
    leader_bounty.placed_at_target_heat = leader_target.heat if leader_target != null else 0
    var heat_bounty = Bounty.new()
    heat_bounty.origin = "heat"
    heat_bounty.target = heat_id
    heat_bounty.condition = "bust"
    heat_bounty.reward_chips = MatchConfig.BOUNTY_BASE_REWARD
    heat_bounty.placed_at_event = state.event_index
    heat_bounty.placed_at_target_heat = heat_target.heat if heat_target != null else 0
    state.bounties = [leader_bounty, heat_bounty]
    var serialized = [leader_bounty.to_dict(), heat_bounty.to_dict()]
    _send_rpc("_rpc_bounties_placed", [serialized])
    bounty_placed.emit(leader_bounty.to_dict())
    bounty_placed.emit(heat_bounty.to_dict())

func _find_chip_leader_peer_id() -> int:
    var leader = state.players[0] if state.players.size() > 0 else null
    for p in state.players:
        if p.chips > leader.chips:
            leader = p
    return leader.peer_id if leader != null else 0

func _find_heat_leader_peer_id() -> int:
    var leader = state.players[0] if state.players.size() > 0 else null
    for p in state.players:
        if p.heat > leader.heat:
            leader = p
    return leader.peer_id if leader != null else 0

func _resolve_bounties(result) -> void:
    if not is_host:
        return
    for bounty in state.bounties:
        var claimants: Array = []
        for p in state.players:
            if Bounty.satisfies(bounty, result, p.peer_id):
                claimants.append(p.peer_id)
        if claimants.is_empty():
            _send_rpc("_rpc_bounty_unclaimed", [bounty.to_dict()])
            bounty_unclaimed.emit(bounty.to_dict())
            continue
        var reward = Bounty.compute_reward(bounty)
        if claimants.size() == 1:
            var claimant = state.find_player(claimants[0])
            claimant.chips += reward
            player_resources_changed.emit(claimants[0])
            _send_rpc("_rpc_bounty_claimed", [claimants[0], bounty.to_dict(), reward])
            bounty_claimed.emit(claimants[0], bounty.to_dict(), reward)
        else:
            var split = int(reward / claimants.size())
            for c_id in claimants:
                var c = state.find_player(c_id)
                c.chips += split
                player_resources_changed.emit(c_id)
                _send_rpc("_rpc_bounty_claimed", [c_id, bounty.to_dict(), split])
                bounty_claimed.emit(c_id, bounty.to_dict(), split)
    state.bounties = []
```

Add the three @rpc receivers (place after the existing receivers):
```gdscript
@rpc("authority", "call_remote", "reliable")
func _rpc_bounties_placed(serialized_bounties: Array) -> void:
    state.bounties = []
    for d in serialized_bounties:
        state.bounties.append(Bounty.from_dict(d))
        bounty_placed.emit(d)

@rpc("authority", "call_remote", "reliable")
func _rpc_bounty_claimed(claimant_peer_id: int, bounty_dict: Dictionary, reward_chips: int) -> void:
    var p = state.find_player(claimant_peer_id)
    if p != null:
        p.chips += reward_chips
        player_resources_changed.emit(claimant_peer_id)
    bounty_claimed.emit(claimant_peer_id, bounty_dict, reward_chips)

@rpc("authority", "call_remote", "reliable")
func _rpc_bounty_unclaimed(bounty_dict: Dictionary) -> void:
    bounty_unclaimed.emit(bounty_dict)
```

Hook `_auto_place_bounties` into HOUSE_REVEAL phase entry. Modify `_enter_phase_behavior`:
```gdscript
MatchPhase.Phase.HOUSE_REVEAL:
    _auto_place_bounties()
    # Clear played_this_event for all players (fresh event)
    for p in state.players:
        p.played_this_event = []
    state.event_modifiers = {}
    state.pending_card_effects = []
    await _schedule_advance()
```

Hook `_resolve_bounties` into BOUNTY_HEAT_UPDATE after heat application. Modify `_process_bounty_heat_update` (the existing handler from sub-project #2 currently just applies heat). Add the resolution call AFTER the existing heat-apply loop and after the existing broadcast:
```gdscript
func _process_bounty_heat_update() -> void:
    if not is_host:
        return
    var result = state.current_result
    if result == null:
        return
    # Existing: apply heat_delta + broadcast deltas
    var deltas: Array = []
    for pid in result.per_player.keys():
        var d = result.heat_delta_for(pid)
        if d == 0:
            continue
        var p = state.find_player(pid)
        if p == null:
            continue
        p.heat = clamp(p.heat + d, 0, MatchConfig.HEAT_MAX)
        player_resources_changed.emit(pid)
        deltas.append({"peer_id": pid, "chip_delta": 0, "crown_delta": 0, "heat_delta": d})
    if deltas.size() > 0:
        _send_rpc("_rpc_apply_deltas", [deltas])
    # NEW: bounty resolution
    _resolve_bounties(result)
```

- [ ] **Step 4: Run, watch pass**

Expected: 329/329 tests pass (323 prior + 6 new).

- [ ] **Step 5: Commit**

```
feat(client): MatchController bounty auto-placement + resolution

_auto_place_bounties (called at HOUSE_REVEAL of events 1+): computes
chip leader + heat leader, appends 2 Bounty instances to state.bounties,
captures placed_at_target_heat for each, broadcasts _rpc_bounties_placed,
emits bounty_placed signal per bounty.

_resolve_bounties (called from _process_bounty_heat_update after heat
applied): for each bounty in state, find claimants via Bounty.satisfies;
award compute_reward to single claimant or split equally; broadcast
_rpc_bounty_claimed or _rpc_bounty_unclaimed; clear state.bounties.

HOUSE_REVEAL branch in _enter_phase_behavior also now clears
played_this_event, event_modifiers, and pending_card_effects for the
fresh event.

Three new RPC receivers + three new signals (bounty_placed,
bounty_claimed, bounty_unclaimed) for HUD subscribers.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 3: Card library

### Task 6: CardRegistry foundation + heat_multiplier

The static-only registry with empty CARDS dict placeholder + `heat_multiplier`, `starter_pool`, `shop_pool` statics. Card effects populate the dict in Tasks 7-9.

**Files:**
- Create: `scripts/cards/card_registry.gd`
- Create: `tests/unit/test_card_registry.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_card_registry.gd`:
```gdscript
extends GutTest

const CardRegistry = preload("res://scripts/cards/card_registry.gd")

func test_heat_multiplier_quiet():
    assert_almost_eq(CardRegistry.heat_multiplier(0), 1.0, 0.001)
    assert_almost_eq(CardRegistry.heat_multiplier(2), 1.0, 0.001)

func test_heat_multiplier_noticed():
    assert_almost_eq(CardRegistry.heat_multiplier(3), 1.25, 0.001)
    assert_almost_eq(CardRegistry.heat_multiplier(5), 1.25, 0.001)

func test_heat_multiplier_hot_seat():
    assert_almost_eq(CardRegistry.heat_multiplier(6), 1.5, 0.001)
    assert_almost_eq(CardRegistry.heat_multiplier(8), 1.5, 0.001)

func test_heat_multiplier_public_enemy():
    assert_almost_eq(CardRegistry.heat_multiplier(9), 2.0, 0.001)
    assert_almost_eq(CardRegistry.heat_multiplier(10), 2.0, 0.001)

func test_get_card_unknown_returns_empty():
    assert_eq(CardRegistry.get_card("nonexistent"), {})
```

- [ ] **Step 2: Run, watch fail**

Expected: CardRegistry preload error.

- [ ] **Step 3: Implement**

Create `scripts/cards/card_registry.gd`:
```gdscript
# Power card registry. Pure static; no instance state. Each card has a
# metadata dict and a static apply function from scripts/cards/effects/<id>.gd.
#
# Sub-project #4 Plan A ships 6 cards (Insurance, Heat Shield, Multiplier
# Booster, Double or Nothing, Late Cash, Underdog Odds). Plan B appends
# the remaining 6 (Cash-Out Jammer, Emergency Eject, Heat Spike, Wager Tax,
# Place Bounty, Copycat Bet).
#
# See docs/superpowers/specs/2026-05-12-power-cards-and-bounties-design.md
# for the full contract.
extends Object

# CARDS dict is populated by Tasks 7-9 (Plan A) and Plan B. Each entry:
#   "card_id": {
#     name: String, rarity: String, category: String,
#     timing: String, target_required: bool, cost_chips: int,
#     description: String, effect: Callable
#   }
const CARDS: Dictionary = {}  # Filled in by per-card tasks via preload+append pattern below

static func get_card(card_id: String) -> Dictionary:
    return CARDS.get(card_id, {})

static func apply_card(card_id: String, context, target_peer_id: int, params = null) -> Dictionary:
    var card = get_card(card_id)
    if card.is_empty():
        return {"applied": false, "type": "unknown_card"}
    return card.effect.call(context, target_peer_id, params)

static func starter_pool() -> Array:
    # Commons that are NOT in the "sabotage" category. Keeps event 1 calm.
    var pool: Array = []
    for id in CARDS.keys():
        var c = CARDS[id]
        if c.rarity == "common" and c.category != "sabotage":
            pool.append(id)
    return pool

static func shop_pool() -> Array:
    return CARDS.keys()

# Heat-bounty value scaler per design doc §6.5
static func heat_multiplier(heat: int) -> float:
    if heat <= 2:
        return 1.0
    if heat <= 5:
        return 1.25
    if heat <= 8:
        return 1.5
    return 2.0
```

**Important:** GDScript's `const CARDS: Dictionary = {}` is module-level immutable at first sight, but in practice you can mutate the dictionary contents at runtime. However, the cleaner pattern Plan A uses: each card-effect task adds entries via a per-card const append. The simplest implementation: have each card file `extends Object` and expose its metadata via a `static const CARD_DATA` const that CardRegistry's bootstrap imports.

**Practical approach for this plan:** declare `CARDS` as a `static var` (not const) and populate via a `_static_init` block that imports each effect file's `CARD_META` dict. GDScript 4.6 doesn't have `_static_init`, so use a one-time initializer pattern triggered on first lookup.

Revised `card_registry.gd`:
```gdscript
extends Object

# Card registry. Each effect file under scripts/cards/effects/<id>.gd
# exposes a `static const CARD_META: Dictionary` plus a `static apply()`.
# CardRegistry imports them all here.

const Insurance = preload("res://scripts/cards/effects/insurance.gd")
const HeatShield = preload("res://scripts/cards/effects/heat_shield.gd")
const MultiplierBooster = preload("res://scripts/cards/effects/multiplier_booster.gd")
const DoubleOrNothing = preload("res://scripts/cards/effects/double_or_nothing.gd")
const LateCash = preload("res://scripts/cards/effects/late_cash.gd")
const UnderdogOdds = preload("res://scripts/cards/effects/underdog_odds.gd")

# CARDS dict assembled from each effect file's CARD_META + apply Callable.
static func _build_cards() -> Dictionary:
    return {
        "insurance": _entry(Insurance.CARD_META, Callable(Insurance, "apply")),
        "heat_shield": _entry(HeatShield.CARD_META, Callable(HeatShield, "apply")),
        "multiplier_booster": _entry(MultiplierBooster.CARD_META, Callable(MultiplierBooster, "apply")),
        "double_or_nothing": _entry(DoubleOrNothing.CARD_META, Callable(DoubleOrNothing, "apply")),
        "late_cash": _entry(LateCash.CARD_META, Callable(LateCash, "apply")),
        "underdog_odds": _entry(UnderdogOdds.CARD_META, Callable(UnderdogOdds, "apply")),
    }

static func _entry(meta: Dictionary, effect: Callable) -> Dictionary:
    var e = meta.duplicate(true)
    e["effect"] = effect
    return e

# Lazy-built singleton-ish dict. Initialized on first lookup.
static var _cards_cache: Dictionary = {}

static func _get_cards() -> Dictionary:
    if _cards_cache.is_empty():
        _cards_cache = _build_cards()
    return _cards_cache

static func get_card(card_id: String) -> Dictionary:
    return _get_cards().get(card_id, {})

static func apply_card(card_id: String, context, target_peer_id: int, params = null) -> Dictionary:
    var card = get_card(card_id)
    if card.is_empty():
        return {"applied": false, "type": "unknown_card"}
    return card.effect.call(context, target_peer_id, params)

static func starter_pool() -> Array:
    var pool: Array = []
    for id in _get_cards().keys():
        var c = _get_cards()[id]
        if c.rarity == "common" and c.category != "sabotage":
            pool.append(id)
    return pool

static func shop_pool() -> Array:
    return _get_cards().keys()

static func heat_multiplier(heat: int) -> float:
    if heat <= 2:
        return 1.0
    if heat <= 5:
        return 1.25
    if heat <= 8:
        return 1.5
    return 2.0
```

**Note:** The preloads at the top of `card_registry.gd` will fail until Tasks 7-9 create the effect files. To make Task 6 testable on its own, **stub the preloads** by creating empty effect files in this task (just `extends Object` with a `const CARD_META = {}` and a `static func apply(...) -> Dictionary: return {"applied": false}`). Tasks 7-9 will replace the bodies.

Create 6 stub files in `scripts/cards/effects/`:
```gdscript
# scripts/cards/effects/insurance.gd (etc., one per card)
extends Object

const CARD_META: Dictionary = {
    "name": "stub",
    "rarity": "common",
    "category": "stub",
    "timing": "bet_loadout",
    "target_required": false,
    "cost_chips": 0,
    "description": "Stub effect — Task 7 fills this in.",
}

static func apply(_context, _target_peer_id: int, _params = null) -> Dictionary:
    return {"applied": false, "type": "stub"}
```

(Repeat for `heat_shield.gd`, `multiplier_booster.gd`, `double_or_nothing.gd`, `late_cash.gd`, `underdog_odds.gd`.)

- [ ] **Step 4: Run, watch pass**

Expected: 334/334 tests pass (329 prior + 5 new).

- [ ] **Step 5: Commit**

```
feat(client): CardRegistry foundation + heat_multiplier

Static-only Object subclass with lazy-built CARDS dict assembled from
6 preloaded effect files. get_card, apply_card, starter_pool (commons
minus sabotage), shop_pool (all 12 when Plan B lands), heat_multiplier
(design doc 6.5 banding: +25%/+50%/+100% at heat 3-5/6-8/9-10).

Effect files in scripts/cards/effects/ stubbed for Plan A scope (6
files: insurance, heat_shield, multiplier_booster, double_or_nothing,
late_cash, underdog_odds). Each stub returns {"applied": false, "type":
"stub"}. Real effects land in Tasks 7-9.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 7: Insurance + Heat Shield + Multiplier Booster effects

Three simple flag-setting effects. Pure functions; each returns a dict with `{type, applied, ...params}`.

**Files:**
- Modify: `scripts/cards/effects/insurance.gd`
- Modify: `scripts/cards/effects/heat_shield.gd`
- Modify: `scripts/cards/effects/multiplier_booster.gd`
- Create: `tests/unit/test_card_insurance.gd`
- Create: `tests/unit/test_card_heat_shield.gd`
- Create: `tests/unit/test_card_multiplier_booster.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_card_insurance.gd`:
```gdscript
extends GutTest

const Insurance = preload("res://scripts/cards/effects/insurance.gd")

func test_insurance_meta_is_defense_common_bet_loadout():
    var m = Insurance.CARD_META
    assert_eq(m.name, "Insurance")
    assert_eq(m.rarity, "common")
    assert_eq(m.category, "defense")
    assert_eq(m.timing, "bet_loadout")
    assert_eq(m.target_required, false)
    assert_eq(m.cost_chips, 50)

func test_insurance_apply_returns_insurance_pre():
    var result = Insurance.apply(null, 0, null)
    assert_true(result.applied)
    assert_eq(result.type, "insurance_pre")
```

`tests/unit/test_card_heat_shield.gd`:
```gdscript
extends GutTest

const HeatShield = preload("res://scripts/cards/effects/heat_shield.gd")

func test_heat_shield_meta():
    var m = HeatShield.CARD_META
    assert_eq(m.name, "Heat Shield")
    assert_eq(m.rarity, "common")
    assert_eq(m.category, "defense")
    assert_eq(m.timing, "bet_loadout")
    assert_eq(m.target_required, false)

func test_heat_shield_apply():
    var result = HeatShield.apply(null, 0, null)
    assert_true(result.applied)
    assert_eq(result.type, "heat_shield")
```

`tests/unit/test_card_multiplier_booster.gd`:
```gdscript
extends GutTest

const MultiplierBooster = preload("res://scripts/cards/effects/multiplier_booster.gd")

func test_multiplier_booster_meta_is_rare_greed():
    var m = MultiplierBooster.CARD_META
    assert_eq(m.name, "Multiplier Booster")
    assert_eq(m.rarity, "rare")
    assert_eq(m.category, "greed")
    assert_eq(m.timing, "bet_loadout")
    assert_eq(m.cost_chips, 150)

func test_multiplier_booster_apply_returns_125_factor():
    var result = MultiplierBooster.apply(null, 0, null)
    assert_true(result.applied)
    assert_eq(result.type, "wager_multiplier")
    assert_almost_eq(float(result.multiplier), 1.25, 0.001)
```

- [ ] **Step 2: Run, watch fail**

Expected: effects still return stub `{"applied": false}`.

- [ ] **Step 3: Implement**

Replace `scripts/cards/effects/insurance.gd`:
```gdscript
# Insurance card: if the player busts this event, recover 50% of wager
# (chip_delta = -wager/2 instead of -wager). Set during BET_LOADOUT;
# resolved in compute_event_result via the insurance_pre flag.
extends Object

const CARD_META: Dictionary = {
    "name": "Insurance",
    "rarity": "common",
    "category": "defense",
    "timing": "bet_loadout",
    "target_required": false,
    "cost_chips": 50,
    "description": "If you bust this event, recover 50% of your wager.",
}

static func apply(_context, _target_peer_id: int, _params = null) -> Dictionary:
    return {"type": "insurance_pre", "applied": true}
```

Replace `scripts/cards/effects/heat_shield.gd`:
```gdscript
# Heat Shield card: halves the heat_delta the player takes from this event.
# Set during BET_LOADOUT; resolved in compute_event_result by halving
# result.per_player[peer_id].heat_delta before it propagates.
extends Object

const CARD_META: Dictionary = {
    "name": "Heat Shield",
    "rarity": "common",
    "category": "defense",
    "timing": "bet_loadout",
    "target_required": false,
    "cost_chips": 50,
    "description": "Halve the Heat you take from this event.",
}

static func apply(_context, _target_peer_id: int, _params = null) -> Dictionary:
    return {"type": "heat_shield", "applied": true}
```

Replace `scripts/cards/effects/multiplier_booster.gd`:
```gdscript
# Multiplier Booster card: if the player survives, multiply their chip
# gain by 1.25. Set during BET_LOADOUT; resolved in compute_event_result.
extends Object

const CARD_META: Dictionary = {
    "name": "Multiplier Booster",
    "rarity": "rare",
    "category": "greed",
    "timing": "bet_loadout",
    "target_required": false,
    "cost_chips": 150,
    "description": "If you survive, your chip gain is multiplied by 1.25.",
}

static func apply(_context, _target_peer_id: int, _params = null) -> Dictionary:
    return {"type": "wager_multiplier", "applied": true, "multiplier": 1.25}
```

- [ ] **Step 4: Run, watch pass**

Expected: 340/340 tests pass (334 prior + 6 new — 2 per card).

- [ ] **Step 5: Commit**

```
feat(client): Insurance + Heat Shield + Multiplier Booster card effects

Three pre-event modifier cards, all timing "bet_loadout":

Insurance (defense/common/50c): on bust, recover 50% of wager.
Heat Shield (defense/common/50c): halve the Heat you take this event.
Multiplier Booster (greed/rare/150c): survivor's chip gain × 1.25.

Each card's apply() returns a deterministic effect dict; state mutation
happens in MatchController's effect dispatcher (Task 11) and the
RocketClashEvent.compute_event_result extension (Task 12).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 8: Late Cash + Underdog Odds effects

Two conditional effects. Late Cash always applies the flag (resolution checks cash_out_at > 5.0); Underdog Odds gates on caller's chip rank at apply time.

**Files:**
- Modify: `scripts/cards/effects/late_cash.gd`
- Modify: `scripts/cards/effects/underdog_odds.gd`
- Create: `tests/unit/test_card_late_cash.gd`
- Create: `tests/unit/test_card_underdog_odds.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_card_late_cash.gd`:
```gdscript
extends GutTest

const LateCash = preload("res://scripts/cards/effects/late_cash.gd")

func test_late_cash_meta():
    var m = LateCash.CARD_META
    assert_eq(m.name, "Late Cash")
    assert_eq(m.rarity, "common")
    assert_eq(m.category, "greed")
    assert_eq(m.timing, "bet_loadout")

func test_late_cash_apply():
    var result = LateCash.apply(null, 0, null)
    assert_true(result.applied)
    assert_eq(result.type, "late_cash_bonus")
    assert_almost_eq(float(result.threshold), 5.0, 0.001)
    assert_eq(result.bonus_chips, 200)
```

`tests/unit/test_card_underdog_odds.gd`:
```gdscript
extends GutTest

const UnderdogOdds = preload("res://scripts/cards/effects/underdog_odds.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(peer_id: int, chips: int) -> RefCounted:
    var p = MatchPlayer.new()
    p.peer_id = peer_id
    p.chips = chips
    p.is_active_this_event = true
    return p

func _ctx_with_players(chips_by_id: Dictionary) -> RefCounted:
    var ctx = EventContext.new()
    for pid in chips_by_id.keys():
        ctx.players.append(_make_player(pid, chips_by_id[pid]))
    return ctx

func test_underdog_odds_meta():
    var m = UnderdogOdds.CARD_META
    assert_eq(m.name, "Underdog Odds")
    assert_eq(m.category, "social")  # or "comeback" — spec says "Social-Comeback"
    assert_eq(m.timing, "bet_loadout")

func test_underdog_odds_applies_when_caller_is_last_in_chips():
    # Caller (peer_id=2) has fewest chips
    var ctx = _ctx_with_players({1: 500, 2: 100, 3: 300})
    var result = UnderdogOdds.apply(ctx, 2, null)
    assert_true(result.applied)
    assert_eq(result.type, "underdog_multiplier")
    assert_almost_eq(float(result.multiplier), 1.5, 0.001)

func test_underdog_odds_no_op_when_caller_not_last():
    # Caller (peer_id=1) has the most chips
    var ctx = _ctx_with_players({1: 500, 2: 100, 3: 300})
    var result = UnderdogOdds.apply(ctx, 1, null)
    assert_false(result.applied)
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

Replace `scripts/cards/effects/late_cash.gd`:
```gdscript
# Late Cash card: if the player cashes out above 5.0x, +200 bonus chips.
# Always applies the flag; resolution in compute_event_result checks the
# cash_out_at threshold.
extends Object

const CARD_META: Dictionary = {
    "name": "Late Cash",
    "rarity": "common",
    "category": "greed",
    "timing": "bet_loadout",
    "target_required": false,
    "cost_chips": 50,
    "description": "If you cash out above 5.0x, +200 chips.",
}

static func apply(_context, _target_peer_id: int, _params = null) -> Dictionary:
    return {
        "type": "late_cash_bonus",
        "applied": true,
        "threshold": 5.0,
        "bonus_chips": 200,
    }
```

Replace `scripts/cards/effects/underdog_odds.gd`:
```gdscript
# Underdog Odds card: if the player is currently last in chips, their
# chip gain this event is multiplied by 1.5 (only if they survive).
# Gates at apply-time on the caller's chip rank in context.players.
# Note: the spec lists this as "Social-Comeback" category; we use "social"
# in metadata for simplicity.
extends Object

const CARD_META: Dictionary = {
    "name": "Underdog Odds",
    "rarity": "common",
    "category": "social",
    "timing": "bet_loadout",
    "target_required": false,
    "cost_chips": 50,
    "description": "If you're last in chips, your reward this event ×1.5.",
}

static func apply(context, target_peer_id: int, _params = null) -> Dictionary:
    # `target_peer_id` here is the caller's own peer_id (no separate target).
    if context == null:
        return {"applied": false, "type": "underdog_multiplier"}
    var min_chips = -1
    for p in context.players:
        if min_chips < 0 or p.chips < min_chips:
            min_chips = p.chips
    var caller = null
    for p in context.players:
        if p.peer_id == target_peer_id:
            caller = p
            break
    if caller == null or caller.chips != min_chips:
        return {"applied": false, "type": "underdog_multiplier"}
    return {
        "type": "underdog_multiplier",
        "applied": true,
        "multiplier": 1.5,
    }
```

- [ ] **Step 4: Run, watch pass**

Expected: 345/345 tests pass (340 prior + 5 new — 2 for Late Cash + 3 for Underdog).

- [ ] **Step 5: Commit**

```
feat(client): Late Cash + Underdog Odds card effects

Late Cash (greed/common/50c): always-applies flag; resolution checks
cash_out_at > 5.0 and adds 200 chips. Effect dict carries threshold +
bonus_chips for the dispatcher.

Underdog Odds (social/common/50c): gates at apply-time on caller's chip
rank. Returns applied=true with multiplier=1.5 only if caller is the
chip minimum among ctx.players. The "you must be last" condition is
checked at BET_LOADOUT time; rank may change during the event but the
modifier sticks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 9: Double or Nothing effect

The most complex of Plan A's 6 cards — mutates pending_wagers directly (returns the doubled amount, dispatcher writes to state).

**Files:**
- Modify: `scripts/cards/effects/double_or_nothing.gd`
- Create: `tests/unit/test_card_double_or_nothing.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_card_double_or_nothing.gd`:
```gdscript
extends GutTest

const DoubleOrNothing = preload("res://scripts/cards/effects/double_or_nothing.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func test_double_or_nothing_meta():
    var m = DoubleOrNothing.CARD_META
    assert_eq(m.name, "Double or Nothing")
    assert_eq(m.rarity, "rare")
    assert_eq(m.category, "greed")
    assert_eq(m.cost_chips, 150)

func test_apply_returns_doubled_wager():
    var ctx = EventContext.new()
    var p = MatchPlayer.new()
    p.peer_id = 1
    p.chips = 500
    ctx.players.append(p)
    ctx.wagers = {1: 100}
    var result = DoubleOrNothing.apply(ctx, 1, null)
    assert_true(result.applied)
    assert_eq(result.type, "double_or_nothing")
    assert_eq(result.new_wager, 200)

func test_apply_caps_at_chip_count():
    var ctx = EventContext.new()
    var p = MatchPlayer.new()
    p.peer_id = 1
    p.chips = 150
    ctx.players.append(p)
    ctx.wagers = {1: 100}
    var result = DoubleOrNothing.apply(ctx, 1, null)
    assert_true(result.applied)
    assert_eq(result.new_wager, 150, "doubled wager capped at chip count")
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

Replace `scripts/cards/effects/double_or_nothing.gd`:
```gdscript
# Double or Nothing card: double the player's wager (capped at chip count).
# Greedy: 2x reward on success, 2x penalty on bust. Returns the new wager
# amount; the dispatcher mutates state.pending_wagers[peer_id] = new_wager.
extends Object

const CARD_META: Dictionary = {
    "name": "Double or Nothing",
    "rarity": "rare",
    "category": "greed",
    "timing": "bet_loadout",
    "target_required": false,
    "cost_chips": 150,
    "description": "Double your wager. 2× reward, 2× bust penalty.",
}

static func apply(context, target_peer_id: int, _params = null) -> Dictionary:
    if context == null:
        return {"applied": false, "type": "double_or_nothing"}
    var current_wager = int(context.wagers.get(target_peer_id, 0))
    var caller_chips = 0
    for p in context.players:
        if p.peer_id == target_peer_id:
            caller_chips = p.chips
            break
    var new_wager = min(current_wager * 2, caller_chips)
    return {
        "type": "double_or_nothing",
        "applied": true,
        "new_wager": new_wager,
    }
```

- [ ] **Step 4: Run, watch pass**

Expected: 348/348 tests pass (345 prior + 3 new).

- [ ] **Step 5: Commit**

```
feat(client): Double or Nothing card effect

Greed/rare/150c: doubles caller's pending_wager, capped at chip count.
Effect dict carries new_wager; dispatcher writes to state.pending_wagers
in Task 11. Resolution in compute_event_result naturally applies the
doubled wager × cash_out_at (or -wager on bust), so no extra modifier
flag needed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 4: Card play pipeline

### Task 10: Loadout management

Adds `submit_loadout_change` + `_rpc_loadout_set` + `_rpc_loadout_acknowledged`. Validates loadout ⊆ hand, clamps to MAX_LOADOUT_SIZE, allowed during BET_LOADOUT only.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_loadout.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_controller_loadout.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
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

func _new_host_with_fake() -> Dictionary:
    var fake = FakeMultiplayerNode.new()
    var c = MatchController.new(true, fake)
    c.no_op_phase_delay_ms_override = 0
    c.start_match(_build_match_start(2))
    # Give P1 a hand of 3 cards
    c.state.players[0].hand = ["insurance", "heat_shield", "multiplier_booster"]
    return {"controller": c, "fake": fake}

func test_loadout_set_with_valid_hand_subset():
    var d = _new_host_with_fake()
    var c = d.controller
    c.state.phase = MatchPhase.Phase.BET_LOADOUT
    c._rpc_loadout_set(1, ["insurance", "heat_shield"])
    assert_eq(c.state.players[0].loadout, ["insurance", "heat_shield"])

func test_loadout_set_drops_cards_not_in_hand():
    var d = _new_host_with_fake()
    var c = d.controller
    c.state.phase = MatchPhase.Phase.BET_LOADOUT
    c._rpc_loadout_set(1, ["insurance", "nonexistent_card"])
    assert_eq(c.state.players[0].loadout, ["insurance"], "invalid card dropped")

func test_loadout_set_truncates_at_max():
    var d = _new_host_with_fake()
    var c = d.controller
    c.state.players[0].hand = ["insurance", "heat_shield", "multiplier_booster", "late_cash"]
    c.state.phase = MatchPhase.Phase.BET_LOADOUT
    c._rpc_loadout_set(1, ["insurance", "heat_shield", "multiplier_booster", "late_cash"])
    assert_eq(c.state.players[0].loadout.size(), 2, "truncated to MAX_LOADOUT_SIZE = 2")

func test_loadout_set_rejected_outside_bet_loadout():
    var d = _new_host_with_fake()
    var c = d.controller
    c.state.phase = MatchPhase.Phase.MAIN_EVENT
    c._rpc_loadout_set(1, ["insurance"])
    assert_eq(c.state.players[0].loadout, [], "no change when phase != BET_LOADOUT")

func test_loadout_set_broadcasts_acknowledged():
    var d = _new_host_with_fake()
    var c = d.controller
    c.state.phase = MatchPhase.Phase.BET_LOADOUT
    d.fake.rpc_calls.clear()
    c._rpc_loadout_set(1, ["insurance"])
    var ack_found = false
    for call in d.fake.rpc_calls:
        if call.method == "_rpc_loadout_acknowledged":
            ack_found = true
            assert_eq(call.args[0], 1)
            assert_eq(call.args[1], ["insurance"])
            break
    assert_true(ack_found)
```

- [ ] **Step 2: Run, watch fail**

Expected: `_rpc_loadout_set` missing.

- [ ] **Step 3: Implement**

In `scripts/match/match_controller.gd`, add the signal:
```gdscript
signal loadout_acknowledged(peer_id: int, loadout: Array)
```

Add `submit_loadout_change` public method (near `submit_wager`):
```gdscript
func submit_loadout_change(loadout: Array) -> void:
    var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
    _send_rpc("_rpc_loadout_set", [my_peer_id, loadout])
```

Add the receiver methods:
```gdscript
@rpc("any_peer", "call_local", "reliable")
func _rpc_loadout_set(peer_id: int, loadout: Array) -> void:
    if not is_host:
        return
    if state.phase != MatchPhase.Phase.BET_LOADOUT:
        return  # Silent reject; UI should disable slots outside BET_LOADOUT
    var player = state.find_player(peer_id)
    if player == null:
        return
    # Clamp: keep only cards that are in the player's hand
    var clamped: Array = []
    for card_id in loadout:
        if card_id in player.hand and not (card_id in clamped):
            clamped.append(card_id)
            if clamped.size() >= MatchConfig.MAX_LOADOUT_SIZE:
                break
    player.loadout = clamped
    _send_rpc("_rpc_loadout_acknowledged", [peer_id, clamped])

@rpc("authority", "call_remote", "reliable")
func _rpc_loadout_acknowledged(peer_id: int, loadout: Array) -> void:
    var player = state.find_player(peer_id)
    if player != null:
        player.loadout = loadout.duplicate()
    loadout_acknowledged.emit(peer_id, loadout)
```

- [ ] **Step 4: Run, watch pass**

Expected: 353/353 tests pass (348 prior + 5 new).

- [ ] **Step 5: Commit**

```
feat(client): MatchController loadout management RPC pipeline

submit_loadout_change public method routes via _send_rpc; _rpc_loadout_set
@rpc receiver (call_local) validates: phase == BET_LOADOUT, clamps loadout
to player.hand subset, truncates at MAX_LOADOUT_SIZE = 2. Broadcasts
_rpc_loadout_acknowledged with the accepted loadout. Clients mirror via
the acknowledged receiver + emit loadout_acknowledged signal for the
LoadoutOverlay widget.

Silent reject outside BET_LOADOUT (player's UI should have its slot
buttons disabled). Silent drop of invalid card_ids — UI snaps to the
acknowledged state.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 11: Card play pipeline + effect dispatcher

The heaviest task in Plan A. Adds `submit_card_play` + `_rpc_card_play_requested` + `_rpc_card_play_rejected` + `_rpc_card_effect_applied` + the `_apply_effect_result` dispatcher that switches on effect type to mutate state.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_card_play.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_controller_card_play.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
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

func _new_host_with_fake() -> Dictionary:
    var fake = FakeMultiplayerNode.new()
    var c = MatchController.new(true, fake)
    c.no_op_phase_delay_ms_override = 0
    c.start_match(_build_match_start(2))
    c.state.players[0].hand = ["insurance", "heat_shield"]
    c.state.players[0].loadout = ["insurance", "heat_shield"]
    return {"controller": c, "fake": fake}

func test_card_play_during_bet_loadout_applies_modifier():
    var d = _new_host_with_fake()
    var c = d.controller
    c.state.phase = MatchPhase.Phase.BET_LOADOUT
    c._rpc_card_play_requested(1, "insurance", 0, null)
    assert_true(c.state.event_modifiers.get(1, {}).get("insurance_pre", false))
    assert_true("insurance" in c.state.players[0].played_this_event)

func test_card_play_outside_window_rejected():
    var d = _new_host_with_fake()
    var c = d.controller
    c.state.phase = MatchPhase.Phase.MAIN_EVENT
    c._rpc_card_play_requested(1, "insurance", 0, null)
    assert_false(c.state.event_modifiers.get(1, {}).get("insurance_pre", false))
    assert_false("insurance" in c.state.players[0].played_this_event)

func test_card_not_in_loadout_rejected():
    var d = _new_host_with_fake()
    var c = d.controller
    c.state.phase = MatchPhase.Phase.BET_LOADOUT
    # Card is in hand but not loadout
    c._rpc_card_play_requested(1, "multiplier_booster", 0, null)
    assert_false(c.state.event_modifiers.get(1, {}).get("wager_multiplier", false))

func test_card_already_played_silently_dropped():
    var d = _new_host_with_fake()
    var c = d.controller
    c.state.phase = MatchPhase.Phase.BET_LOADOUT
    c._rpc_card_play_requested(1, "insurance", 0, null)  # first
    var first_event_modifiers_size = c.state.event_modifiers.size()
    d.fake.rpc_calls.clear()
    c._rpc_card_play_requested(1, "insurance", 0, null)  # second
    var ack_count = 0
    for call in d.fake.rpc_calls:
        if call.method == "_rpc_card_effect_applied":
            ack_count += 1
    assert_eq(ack_count, 0, "second play silently dropped (no new broadcast)")

func test_card_play_broadcasts_effect_applied():
    var d = _new_host_with_fake()
    var c = d.controller
    c.state.phase = MatchPhase.Phase.BET_LOADOUT
    d.fake.rpc_calls.clear()
    c._rpc_card_play_requested(1, "insurance", 0, null)
    var found = false
    for call in d.fake.rpc_calls:
        if call.method == "_rpc_card_effect_applied":
            found = true
            assert_eq(call.args[0], 1)  # peer_id
            assert_eq(call.args[1], "insurance")  # card_id
            break
    assert_true(found)

func test_card_play_multiple_cards_accumulates_modifiers():
    var d = _new_host_with_fake()
    var c = d.controller
    c.state.phase = MatchPhase.Phase.BET_LOADOUT
    c._rpc_card_play_requested(1, "insurance", 0, null)
    c._rpc_card_play_requested(1, "heat_shield", 0, null)
    assert_true(c.state.event_modifiers.get(1, {}).get("insurance_pre", false))
    assert_true(c.state.event_modifiers.get(1, {}).get("heat_shield", false))
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

In `scripts/match/match_controller.gd`, add at the top:
```gdscript
const CardRegistry = preload("res://scripts/cards/card_registry.gd")
```

Add `_send_rpc_to_peer` helper next to `_send_rpc` (~line 144):
```gdscript
func _send_rpc_to_peer(peer_id: int, method_name: String, args: Array = []) -> void:
	# Targeted RPC. Routes through _multiplayer_node.rpc_id when non-null;
	# no-ops in unit tests where _multiplayer_node is null. FakeMultiplayerNode
	# records these as {method, peer_id, args} in its rpc_calls log.
	if _multiplayer_node == null:
		return
	match args.size():
		0: _multiplayer_node.rpc_id(peer_id, method_name)
		1: _multiplayer_node.rpc_id(peer_id, method_name, args[0])
		2: _multiplayer_node.rpc_id(peer_id, method_name, args[0], args[1])
		3: _multiplayer_node.rpc_id(peer_id, method_name, args[0], args[1], args[2])
		_:
			push_error("MatchController._send_rpc_to_peer: unsupported arity %d" % args.size())
```

`FakeMultiplayerNode` already records `rpc_id(peer_id, method, ...)` as `{method, peer_id, args}` (see `tests/fakes/fake_multiplayer_node.gd`), so no fake changes are needed.

Add signals:
```gdscript
signal card_effect_applied(peer_id: int, card_id: String, effect_result: Dictionary)
signal card_play_rejected(card_id: String, reason: String)
```

Add `submit_card_play` public:
```gdscript
func submit_card_play(card_id: String, target_peer_id: int = 0, params = null) -> void:
    var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
    _send_rpc("_rpc_card_play_requested", [my_peer_id, card_id, target_peer_id, params])
```

Add the receiver + dispatcher:
```gdscript
@rpc("any_peer", "call_local", "reliable")
func _rpc_card_play_requested(peer_id: int, card_id: String, target_peer_id: int, params) -> void:
    if not is_host:
        return
    var player = state.find_player(peer_id)
    if player == null:
        return
    # Validation
    if not (card_id in player.loadout):
        return  # silent reject; UI should not have shown this card
    if card_id in player.played_this_event:
        return  # idempotent silent drop (double-click guard)
    var card = CardRegistry.get_card(card_id)
    if card.is_empty():
        return
    var current_window = _current_timing_window()
    if card.get("timing", "") != current_window:
        return  # silent reject; timing mismatch
    if card.get("target_required", false) and target_peer_id == 0:
        _send_rpc_to_peer(peer_id, "_rpc_card_play_rejected", [card_id, "target_required"])
        return
    # Build a minimal context for the effect function
    var ctx = _build_event_context()
    var effect_result = CardRegistry.apply_card(card_id, ctx, peer_id if not card.target_required else target_peer_id, params)
    if not effect_result.get("applied", false):
        # Effect declined (e.g., Underdog Odds when not last); don't add to played_this_event
        _send_rpc_to_peer(peer_id, "_rpc_card_play_rejected", [card_id, "effect_declined"])
        return
    _apply_effect_result(effect_result, peer_id)
    player.played_this_event.append(card_id)
    _send_rpc("_rpc_card_effect_applied", [peer_id, card_id, effect_result])
    card_effect_applied.emit(peer_id, card_id, effect_result)

@rpc("authority", "call_remote", "reliable")
func _rpc_card_effect_applied(peer_id: int, card_id: String, effect_result: Dictionary) -> void:
    # Clients mirror the state mutation via the same dispatcher
    _apply_effect_result(effect_result, peer_id)
    var player = state.find_player(peer_id)
    if player != null and not (card_id in player.played_this_event):
        player.played_this_event.append(card_id)
    card_effect_applied.emit(peer_id, card_id, effect_result)

@rpc("authority", "call_remote", "reliable")
func _rpc_card_play_rejected(card_id: String, reason: String) -> void:
    card_play_rejected.emit(card_id, reason)

func _current_timing_window() -> String:
    match state.phase:
        MatchPhase.Phase.BET_LOADOUT:
            return "bet_loadout"
        MatchPhase.Phase.MAIN_EVENT:
            return "cash_out"
        _:
            return ""

func _apply_effect_result(effect: Dictionary, peer_id: int) -> void:
    if not effect.get("applied", false):
        return
    var t = effect.get("type", "")
    match t:
        "insurance_pre":
            _ensure_modifiers(peer_id)
            state.event_modifiers[peer_id]["insurance_pre"] = true
        "heat_shield":
            _ensure_modifiers(peer_id)
            state.event_modifiers[peer_id]["heat_shield"] = true
        "wager_multiplier":
            _ensure_modifiers(peer_id)
            state.event_modifiers[peer_id]["wager_multiplier"] = float(effect.get("multiplier", 1.0))
        "late_cash_bonus":
            _ensure_modifiers(peer_id)
            state.event_modifiers[peer_id]["late_cash_bonus"] = true
            state.event_modifiers[peer_id]["late_cash_threshold"] = float(effect.get("threshold", 5.0))
            state.event_modifiers[peer_id]["late_cash_bonus_chips"] = int(effect.get("bonus_chips", 200))
        "underdog_multiplier":
            _ensure_modifiers(peer_id)
            state.event_modifiers[peer_id]["underdog_multiplier"] = float(effect.get("multiplier", 1.5))
        "double_or_nothing":
            var new_wager = int(effect.get("new_wager", 0))
            state.pending_wagers[peer_id] = new_wager
            # Only the host broadcasts the resulting wager change. Clients mirror
            # state via _rpc_card_effect_applied below — they must not re-broadcast.
            if is_host:
                _send_rpc("_rpc_wager_acknowledged", [peer_id, new_wager])
        # Plan B types appended later
        _:
            push_warning("Unhandled effect type: %s" % t)

func _ensure_modifiers(peer_id: int) -> void:
    if not state.event_modifiers.has(peer_id):
        state.event_modifiers[peer_id] = {}
```

- [ ] **Step 4: Run, watch pass**

Expected: 359/359 tests pass (353 prior + 6 new).

- [ ] **Step 5: Commit**

```
feat(client): MatchController card play pipeline + effect dispatcher

submit_card_play public method routes via _send_rpc. _rpc_card_play_requested
@rpc receiver validates: card in loadout, not already played this event,
timing matches current phase (bet_loadout for BET_LOADOUT, cash_out for
MAIN_EVENT), target valid if required.

CardRegistry.apply_card produces an effect_result dict. If applied=false,
host sends _rpc_card_play_rejected (so client UI re-enables the slot).
Otherwise host calls _apply_effect_result dispatcher (switch on type:
insurance_pre, heat_shield, wager_multiplier, late_cash_bonus,
underdog_multiplier, double_or_nothing), mutates state.event_modifiers
or state.pending_wagers, adds card_id to player.played_this_event,
broadcasts _rpc_card_effect_applied.

Clients mirror state via _rpc_card_effect_applied receiver which runs
the same dispatcher. Two new signals (card_effect_applied,
card_play_rejected) for HUD subscribers.

Plan B's 6 cards will append new effect types to the dispatcher
match table; the refactor task in Plan B extracts this dispatcher into
its own CardEffectDispatcher collaborator.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 5: Event integration

### Task 12: RocketClashEvent reads event_modifiers

Extends `compute_event_result` to accept a 5th `event_modifiers` argument and apply per-player flags during chip_delta computation. MatchController populates `ctx.event_modifiers` from `state.event_modifiers` in `_build_event_context`.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Modify: `scripts/events/rocket_clash/rocket_clash_event.gd`
- Create: `tests/unit/test_rocket_clash_event_modifiers.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_rocket_clash_event_modifiers.gd`:
```gdscript
extends GutTest

const RocketClashEvent = preload("res://scripts/events/rocket_clash/rocket_clash_event.gd")
const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(peer_id: int, name: String, chips: int = 800) -> RefCounted:
    var p = MatchPlayer.new()
    p.peer_id = peer_id
    p.name = name
    p.chips = chips
    p.is_active_this_event = true
    return p

func _make_context(player_count: int, wagers: Dictionary, modifiers: Dictionary) -> RefCounted:
    var ctx = EventContext.new()
    for i in player_count:
        ctx.players.append(_make_player(i + 1, "P%d" % (i + 1)))
    ctx.wagers = wagers
    ctx.event_modifiers = modifiers
    return ctx

func test_insurance_halves_bust_penalty():
    var ctx = _make_context(2, {1: 100, 2: 100}, {1: {"insurance_pre": true}})
    var cash_outs = {}
    var busted = [1, 2]
    var result = RocketClashEvent.compute_event_result(ctx, 1.5, cash_outs, busted)
    assert_eq(result.chip_delta_for(1), -50, "P1 with insurance loses 50 not 100")
    assert_eq(result.chip_delta_for(2), -100, "P2 without insurance loses 100")

func test_wager_multiplier_boosts_survivor_chip_gain():
    var ctx = _make_context(2, {1: 100, 2: 100}, {1: {"wager_multiplier": 1.25}})
    var cash_outs = {1: 2.0, 2: 2.0}
    var busted = []
    var result = RocketClashEvent.compute_event_result(ctx, 3.0, cash_outs, busted)
    # P1: 100 * 2.0 * 1.25 = 250
    # P2: 100 * 2.0 = 200
    assert_eq(result.chip_delta_for(1), 250)
    assert_eq(result.chip_delta_for(2), 200)

func test_underdog_multiplier_boosts_survivor_chip_gain():
    var ctx = _make_context(2, {1: 100, 2: 100}, {1: {"underdog_multiplier": 1.5}})
    var cash_outs = {1: 2.0, 2: 2.0}
    var busted = []
    var result = RocketClashEvent.compute_event_result(ctx, 3.0, cash_outs, busted)
    # P1: 100 * 2.0 * 1.5 = 300
    assert_eq(result.chip_delta_for(1), 300)

func test_late_cash_bonus_applies_above_threshold():
    var ctx = _make_context(2, {1: 100, 2: 100},
        {1: {"late_cash_bonus": true, "late_cash_threshold": 5.0, "late_cash_bonus_chips": 200}})
    var cash_outs = {1: 6.0, 2: 6.0}
    var busted = []
    var result = RocketClashEvent.compute_event_result(ctx, 7.0, cash_outs, busted)
    # P1: 100 * 6.0 + 200 = 800
    # P2: 100 * 6.0 = 600
    assert_eq(result.chip_delta_for(1), 800)
    assert_eq(result.chip_delta_for(2), 600)

func test_late_cash_bonus_skipped_below_threshold():
    var ctx = _make_context(1, {1: 100},
        {1: {"late_cash_bonus": true, "late_cash_threshold": 5.0, "late_cash_bonus_chips": 200}})
    var cash_outs = {1: 4.0}
    var busted = []
    var result = RocketClashEvent.compute_event_result(ctx, 5.0, cash_outs, busted)
    # cash_out 4.0 < threshold 5.0; no bonus
    assert_eq(result.chip_delta_for(1), 400)

func test_heat_shield_halves_heat_delta():
    # Heat Shield's mechanism: compute_event_result halves heat_delta in the
    # per_player entry for players with heat_shield flag.
    var ctx = _make_context(1, {1: 100}, {1: {"heat_shield": true}})
    var cash_outs = {1: 2.0}
    var busted = []
    var result = RocketClashEvent.compute_event_result(ctx, 3.0, cash_outs, busted)
    # Crown winner gets heat_delta = 1 base; with shield, halved = 0
    # (int(1 / 2) = 0)
    assert_eq(result.per_player[1].heat_delta, 0)

func test_compute_event_result_with_no_modifiers_unchanged():
    # Sanity: existing tests from sub-project #3 should still pass
    var ctx = _make_context(2, {1: 100, 2: 100}, {})
    var cash_outs = {1: 2.5, 2: 1.5}
    var busted = []
    var result = RocketClashEvent.compute_event_result(ctx, 3.0, cash_outs, busted)
    assert_eq(result.chip_delta_for(1), 250)
    assert_eq(result.chip_delta_for(2), 150)
```

- [ ] **Step 2: Run, watch fail**

Expected: `compute_event_result` doesn't read modifiers yet (sub-project #3's version).

- [ ] **Step 3: Implement**

Modify `RocketClashEvent.compute_event_result` to accept and apply event_modifiers. The current signature is:
```gdscript
static func compute_event_result(context, crash_at: float, cash_outs: Dictionary, busted: Array) -> RefCounted:
```

Change body to read `context.event_modifiers` per-player. Replace the existing function (sub-project #3 added the Crown logic; preserve it; add modifier application). New version:
```gdscript
static func compute_event_result(context, crash_at: float, cash_outs: Dictionary, busted: Array) -> RefCounted:
    var result = EventResult.new()
    result.event_id = "rocket_clash"
    var summary: Array = []
    var winner_peer_id = 0
    var winner_name = ""
    var winner_cash_out = -1.0
    var modifiers = {}
    if context != null and "event_modifiers" in context:
        modifiers = context.event_modifiers
    for player in context.players:
        var pid = player.peer_id
        var wager = int(context.wagers.get(pid, 0))
        var p_mods = modifiers.get(pid, {})
        if busted.has(pid):
            var bust_loss = wager
            if p_mods.get("insurance_pre", false):
                bust_loss = int(wager / 2)  # Insurance halves bust penalty
            result.per_player[pid] = {
                "chip_delta": -bust_loss,
                "crown_delta": 0,
                "heat_delta": 0,
                "bust": true,
                "cash_out_at": 0.0,
            }
            summary.append({
                "peer_id": pid, "name": player.name, "cash_out_at": 0.0,
                "chip_delta": -bust_loss, "busted": true, "wager": wager,
            })
        else:
            var cash_out_at = float(cash_outs.get(pid, 0.0))
            var chip_delta = int(wager * cash_out_at)
            # Wager multiplier (Multiplier Booster)
            var wm = float(p_mods.get("wager_multiplier", 1.0))
            if wm != 1.0:
                chip_delta = int(chip_delta * wm)
            # Underdog multiplier
            var um = float(p_mods.get("underdog_multiplier", 1.0))
            if um != 1.0:
                chip_delta = int(chip_delta * um)
            # Late Cash bonus
            if p_mods.get("late_cash_bonus", false):
                var threshold = float(p_mods.get("late_cash_threshold", 5.0))
                var bonus = int(p_mods.get("late_cash_bonus_chips", 200))
                if cash_out_at > threshold:
                    chip_delta += bonus
            result.per_player[pid] = {
                "chip_delta": chip_delta,
                "crown_delta": 0,
                "heat_delta": 0,
                "bust": false,
                "cash_out_at": cash_out_at,
            }
            summary.append({
                "peer_id": pid, "name": player.name, "cash_out_at": cash_out_at,
                "chip_delta": chip_delta, "busted": false, "wager": wager,
            })
            if cash_out_at > winner_cash_out:
                winner_cash_out = cash_out_at
                winner_peer_id = pid
                winner_name = player.name
    # Award Crown + heat_delta (Crown winner gets +1 heat by Rocket Clash convention)
    if winner_peer_id != 0:
        result.per_player[winner_peer_id]["crown_delta"] = 1
        var winner_mods = modifiers.get(winner_peer_id, {})
        var heat_delta = 1
        if winner_mods.get("heat_shield", false):
            heat_delta = int(heat_delta / 2)  # Heat Shield halves heat_delta
        result.per_player[winner_peer_id]["heat_delta"] = heat_delta
    result.painful_reveal = {
        "crash_at": crash_at,
        "winner_peer_id": winner_peer_id,
        "winner_name": winner_name,
        "cash_outs_summary": summary,
    }
    return result
```

In `MatchController._build_event_context`, the existing code (from sub-projects #2-3) sets ctx.event_index, ctx.rng_seed, ctx.is_host, and populates ctx.wagers from pending_wagers. Add population of `ctx.event_modifiers` from `state.event_modifiers`:
```gdscript
func _build_event_context():
    var ctx = EventContext.new()
    for p in state.players:
        if p.is_active_this_event:
            ctx.players.append(p)
    ctx.event_index = state.event_index
    ctx.rng_seed = state.rng_seed ^ (state.event_index * 0x9E3779B9)
    ctx.is_host = is_host
    if not state.pending_wagers.is_empty():
        for p in ctx.players:
            ctx.wagers[p.peer_id] = state.pending_wagers.get(p.peer_id, 0)
    else:
        var ante = MatchConfig.ANTE_BY_EVENT_INDEX[state.event_index]
        for p in ctx.players:
            ctx.wagers[p.peer_id] = ante
    # NEW: thread event_modifiers
    ctx.event_modifiers = state.event_modifiers.duplicate(true)
    return ctx
```

- [ ] **Step 4: Run, watch pass**

Expected: 366/366 tests pass (359 prior + 7 new). Plan A's existing `test_rocket_clash_result.gd` continues to pass because tests there create context without `event_modifiers` (the empty-dict default branch in compute_event_result keeps the original behavior).

- [ ] **Step 5: Commit**

```
feat(client): RocketClashEvent.compute_event_result reads event_modifiers

Extended to apply per-player pre-event card flags during chip_delta
computation:
- insurance_pre: bust penalty halved (-wager/2 instead of -wager)
- wager_multiplier: survivor chip_delta multiplied (Multiplier Booster 1.25)
- underdog_multiplier: survivor chip_delta multiplied (Underdog Odds 1.5)
- late_cash_bonus: +bonus_chips if cash_out_at > threshold
- heat_shield: Crown winner's heat_delta halved

MatchController._build_event_context populates ctx.event_modifiers from
state.event_modifiers (deep-copied). When no modifiers present, the
existing math from sub-project #3 is unchanged.

All Plan A and sub-project #3 tests continue to pass; new tests verify
each modifier in isolation.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 6: Starter pack

### Task 13: start_match distributes starter pack

At match start, each player gets 3 random commons (excluding sabotage) into their hand. Broadcasts via a new RPC so clients mirror.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_starter_pack.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_controller_starter_pack.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
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

func test_start_match_deals_starter_pack_size_3():
    var c = MatchController.new(true, null)
    c.no_op_phase_delay_ms_override = 0
    c.start_match(_build_match_start(2))
    for p in c.state.players:
        assert_eq(p.hand.size(), 3, "%s should have 3 starter cards" % p.name)

func test_starter_pack_excludes_sabotage():
    # All Plan A cards are non-sabotage anyway, but the starter_pool() filter
    # is what we're testing. Until Plan B adds sabotage cards, this just
    # asserts the deal works.
    var c = MatchController.new(true, null)
    c.no_op_phase_delay_ms_override = 0
    c.start_match(_build_match_start(2))
    var sabotage_count = 0
    var CardRegistry = load("res://scripts/cards/card_registry.gd")
    for p in c.state.players:
        for card_id in p.hand:
            var card = CardRegistry.get_card(card_id)
            if card.get("category", "") == "sabotage":
                sabotage_count += 1
    assert_eq(sabotage_count, 0, "no sabotage cards in starter pack")

func test_starter_pack_is_deterministic_with_seed():
    var c1 = MatchController.new(true, null)
    c1.no_op_phase_delay_ms_override = 0
    c1.start_match(_build_match_start(2, 0xCAFE))
    var c2 = MatchController.new(true, null)
    c2.no_op_phase_delay_ms_override = 0
    c2.start_match(_build_match_start(2, 0xCAFE))
    assert_eq(c1.state.players[0].hand, c2.state.players[0].hand,
              "same seed -> same starter pack")
```

- [ ] **Step 2: Run, watch fail**

Expected: `start_match` doesn't populate hands.

- [ ] **Step 3: Implement**

In `scripts/match/match_controller.gd`, modify `start_match` to deal starter packs after building players. Insert the deal block before `_set_phase(MatchPhase.Phase.HOUSE_REVEAL)`:
```gdscript
func start_match(match_start) -> void:
    if not is_host:
        return
    if _multiplayer_node == null and is_inside_tree():
        _multiplayer_node = self
    # Build MatchPlayer records from MatchStart seats.
    state.players = []
    var player_count = match_start.seats.size()
    var starting_chips = MatchConfig.starting_chips_for_player_count(player_count)
    for seat in match_start.seats:
        var mp = MatchPlayer.new()
        mp.peer_id = seat.peer_id
        mp.seat_index = seat.seat_index
        mp.name = seat.name
        mp.color_index = seat.color_index
        mp.chips = starting_chips
        state.players.append(mp)
    state.rng_seed = match_start.rng_seed
    state.seed_rng()
    state.event_index = 0
    # NEW: deal starter pack
    _deal_starter_pack()
    _set_phase(MatchPhase.Phase.HOUSE_REVEAL)

func _deal_starter_pack() -> void:
    var pool = CardRegistry.starter_pool()
    if pool.is_empty():
        return
    var serialized_hands: Dictionary = {}
    for p in state.players:
        # Sample STARTER_PACK_SIZE cards (with replacement allowed for now;
        # if Plan A's pool has 6 cards and starter is 3, distinct sampling
        # is plausible)
        var hand: Array = []
        for i in MatchConfig.STARTER_PACK_SIZE:
            var idx = state.rng.randi() % pool.size()
            hand.append(pool[idx])
        p.hand = hand
        serialized_hands[p.peer_id] = hand.duplicate()
    _send_rpc("_rpc_starter_pack_dealt", [serialized_hands])

@rpc("authority", "call_remote", "reliable")
func _rpc_starter_pack_dealt(hands: Dictionary) -> void:
    for pid_key in hands.keys():
        var pid = int(pid_key)
        var p = state.find_player(pid)
        if p != null:
            p.hand = hands[pid_key].duplicate()
```

- [ ] **Step 4: Run, watch pass**

Expected: 369/369 tests pass (366 prior + 3 new).

- [ ] **Step 5: Commit**

```
feat(client): start_match deals starter pack of 3 cards

_deal_starter_pack runs after player records build, before HOUSE_REVEAL.
Samples STARTER_PACK_SIZE = 3 card_ids from CardRegistry.starter_pool()
(commons minus sabotage) using the seeded RNG. Each player's hand
populated; broadcasts via new _rpc_starter_pack_dealt receiver so clients
mirror.

Deterministic: same MatchStart.rng_seed produces same starter packs
across host + clients (because state.rng is seeded once and used
identically).

Sampling allows duplicates within a pack — acceptable for MVP given the
Plan A pool is 5 cards and starter is 3 cards; Plan B will grow the pool
to 7-8 non-sabotage commons making duplicates rare.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 7: SHOP phase

### Task 14: SHOP phase upgrade

Replaces sub-project #2's no-op SHOP pass-through with a real async phase. Offers 3 cards, accepts buys, tracks done-peers, advances on all-done OR timer-expire.

**Files:**
- Modify: `scripts/match/match_controller.gd`
- Create: `tests/unit/test_match_controller_shop.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_match_controller_shop.gd`:
```gdscript
extends GutTest

const MatchController = preload("res://scripts/match/match_controller.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")
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

func _new_host_with_fake() -> Dictionary:
    var fake = FakeMultiplayerNode.new()
    var c = MatchController.new(true, fake)
    c.no_op_phase_delay_ms_override = 0
    c.shop_timeout_sec_override = 0.0
    c.start_match(_build_match_start(2))
    return {"controller": c, "fake": fake}

func test_shop_entry_offers_3_cards():
    var d = _new_host_with_fake()
    var c = d.controller
    add_child_autofree(c)
    c.state.phase = MatchPhase.Phase.SHOP
    c._process_shop()
    await get_tree().process_frame
    assert_eq(c.state.current_shop_offer.size(), MatchConfig.SHOP_OFFER_SIZE)

func test_shop_emits_opened_signal():
    var d = _new_host_with_fake()
    var c = d.controller
    add_child_autofree(c)
    var opened_payload: Array = []
    c.shop_opened.connect(func(offered): opened_payload = [offered])
    c.state.phase = MatchPhase.Phase.SHOP
    c._process_shop()
    await get_tree().process_frame
    assert_eq(opened_payload.size(), 1)
    assert_eq(opened_payload[0].size(), MatchConfig.SHOP_OFFER_SIZE)

func test_buy_valid_card_deducts_chips_and_adds_to_hand():
    var d = _new_host_with_fake()
    var c = d.controller
    add_child_autofree(c)
    c.state.phase = MatchPhase.Phase.SHOP
    c.state.current_shop_offer = ["insurance", "heat_shield", "multiplier_booster"]
    var p1_chips_before = c.state.players[0].chips
    c._rpc_shop_buy_requested(1, "insurance")
    assert_eq(c.state.players[0].chips, p1_chips_before - 50, "Insurance costs 50")
    assert_true("insurance" in c.state.players[0].hand)

func test_buy_insufficient_chips_rejected():
    var d = _new_host_with_fake()
    var c = d.controller
    add_child_autofree(c)
    c.state.phase = MatchPhase.Phase.SHOP
    c.state.current_shop_offer = ["multiplier_booster"]
    c.state.players[0].chips = 100  # less than 150 cost
    var hand_before = c.state.players[0].hand.size()
    c._rpc_shop_buy_requested(1, "multiplier_booster")
    assert_eq(c.state.players[0].hand.size(), hand_before, "buy rejected; hand unchanged")

func test_buy_card_not_in_offer_rejected():
    var d = _new_host_with_fake()
    var c = d.controller
    add_child_autofree(c)
    c.state.phase = MatchPhase.Phase.SHOP
    c.state.current_shop_offer = ["insurance"]
    c._rpc_shop_buy_requested(1, "heat_shield")  # not in offer
    assert_false("heat_shield" in c.state.players[0].hand)

func test_buy_hand_full_rejected():
    var d = _new_host_with_fake()
    var c = d.controller
    add_child_autofree(c)
    c.state.phase = MatchPhase.Phase.SHOP
    c.state.current_shop_offer = ["insurance"]
    c.state.players[0].hand = ["c1", "c2", "c3", "c4", "c5"]  # MAX
    c._rpc_shop_buy_requested(1, "insurance")
    assert_eq(c.state.players[0].hand.size(), 5, "hand full; no buy")
    assert_false("insurance" in c.state.players[0].hand)

func test_buy_twice_per_visit_rejected():
    var d = _new_host_with_fake()
    var c = d.controller
    add_child_autofree(c)
    c.state.phase = MatchPhase.Phase.SHOP
    c.state.current_shop_offer = ["insurance", "heat_shield"]
    c._rpc_shop_buy_requested(1, "insurance")
    c._rpc_shop_buy_requested(1, "heat_shield")  # second; should be rejected
    assert_true("insurance" in c.state.players[0].hand)
    assert_false("heat_shield" in c.state.players[0].hand, "second buy rejected")

func test_submit_done_marks_peer_done():
    var d = _new_host_with_fake()
    var c = d.controller
    add_child_autofree(c)
    c.state.phase = MatchPhase.Phase.SHOP
    c._rpc_shop_done(1)
    assert_true(1 in c.state.shop_done_peers)
```

- [ ] **Step 2: Run, watch fail**

Expected: `_process_shop`, `_rpc_shop_buy_requested`, etc. missing.

- [ ] **Step 3: Implement**

In `scripts/match/match_controller.gd`, add signals + test seam:
```gdscript
signal shop_opened(offered_card_ids: Array)
signal shop_closed
signal shop_purchase_confirmed(peer_id: int, card_id: String, cost_chips: int)
signal shop_purchase_rejected(peer_id: int, card_id: String, reason: String)

var shop_timeout_sec_override: float = -1.0

func _shop_timeout_sec() -> float:
    if shop_timeout_sec_override >= 0.0:
        return shop_timeout_sec_override
    return float(MatchConfig.SHOP_TIMEOUT_SEC)
```

Add the SHOP phase handler:
```gdscript
func _process_shop() -> void:
    if not is_host:
        return
    # Pick 3 random cards from the shop pool
    var pool = CardRegistry.shop_pool().duplicate()
    pool.shuffle()
    state.current_shop_offer = pool.slice(0, min(MatchConfig.SHOP_OFFER_SIZE, pool.size()))
    state.shop_done_peers = []
    _send_rpc("_rpc_shop_opened", [state.current_shop_offer.duplicate()])
    shop_opened.emit(state.current_shop_offer.duplicate())
    var timeout_sec = _shop_timeout_sec()
    if timeout_sec <= 0.0:
        # Test-bypass path: shop is open; do NOT await, do NOT auto-close.
        # Tests inspect state.current_shop_offer/shop_opened immediately. Any
        # test exercising the close path calls _close_shop() directly.
        return
    if not is_inside_tree():
        # Detached controller (no scene): treat like timeout=0 — caller
        # drives the close path explicitly.
        return
    var timer = get_tree().create_timer(timeout_sec)
    while timer.time_left > 0.0:
        if _all_active_done_in_shop():
            break
        await get_tree().process_frame
    _close_shop()

func _all_active_done_in_shop() -> bool:
    for p in state.players:
        if p.is_active_this_event and not (p.peer_id in state.shop_done_peers):
            return false
    return true

func _close_shop() -> void:
    state.current_shop_offer = []
    state.shop_done_peers = []
    _send_rpc("_rpc_shop_closed", [])
    shop_closed.emit()

func _card_cost(card_id: String) -> int:
    var card = CardRegistry.get_card(card_id)
    return int(card.get("cost_chips", 0))

@rpc("any_peer", "call_local", "reliable")
func _rpc_shop_buy_requested(peer_id: int, card_id: String) -> void:
    if not is_host:
        return
    if state.phase != MatchPhase.Phase.SHOP:
        return
    if not (card_id in state.current_shop_offer):
        _send_rpc_to_peer(peer_id, "_rpc_shop_buy_rejected", [card_id, "not_in_offer"])
        return
    if peer_id in state.shop_done_peers:
        return  # silent: second buy attempt
    var player = state.find_player(peer_id)
    if player == null:
        return
    var cost = _card_cost(card_id)
    if player.chips < cost:
        _send_rpc_to_peer(peer_id, "_rpc_shop_buy_rejected", [card_id, "insufficient_chips"])
        return
    if player.hand.size() >= MatchConfig.MAX_HAND_SIZE:
        _send_rpc_to_peer(peer_id, "_rpc_shop_buy_rejected", [card_id, "hand_full"])
        return
    # Apply
    player.chips -= cost
    player.hand.append(card_id)
    state.shop_done_peers.append(peer_id)
    player_resources_changed.emit(peer_id)
    _send_rpc("_rpc_shop_purchase_confirmed", [peer_id, card_id, cost])
    _send_rpc("_rpc_apply_deltas", [[{"peer_id": peer_id, "chip_delta": -cost, "crown_delta": 0, "heat_delta": 0}]])
    shop_purchase_confirmed.emit(peer_id, card_id, cost)

@rpc("any_peer", "call_local", "reliable")
func _rpc_shop_done(peer_id: int) -> void:
    if not is_host:
        return
    if state.phase != MatchPhase.Phase.SHOP:
        return
    if not (peer_id in state.shop_done_peers):
        state.shop_done_peers.append(peer_id)

@rpc("authority", "call_remote", "reliable")
func _rpc_shop_opened(offered: Array) -> void:
    state.current_shop_offer = offered.duplicate()
    state.shop_done_peers = []
    shop_opened.emit(offered)

@rpc("authority", "call_remote", "reliable")
func _rpc_shop_closed() -> void:
    state.current_shop_offer = []
    state.shop_done_peers = []
    shop_closed.emit()

@rpc("authority", "call_remote", "reliable")
func _rpc_shop_purchase_confirmed(peer_id: int, card_id: String, cost_chips: int) -> void:
    var player = state.find_player(peer_id)
    if player != null and not (card_id in player.hand):
        player.hand.append(card_id)
    shop_purchase_confirmed.emit(peer_id, card_id, cost_chips)

@rpc("authority", "call_remote", "reliable")
func _rpc_shop_buy_rejected(card_id: String, reason: String) -> void:
    shop_purchase_rejected.emit(0, card_id, reason)  # peer_id 0; receiver is the originator

func submit_shop_buy(card_id: String) -> void:
    var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
    _send_rpc("_rpc_shop_buy_requested", [my_peer_id, card_id])

func submit_shop_done() -> void:
    var my_peer_id = multiplayer.get_unique_id() if multiplayer != null else 1
    _send_rpc("_rpc_shop_done", [my_peer_id])
```

Wire SHOP into `_enter_phase_behavior` (replacing the existing no-op):
```gdscript
MatchPhase.Phase.SHOP:
    await _process_shop()
    await _schedule_advance()
```

- [ ] **Step 4: Run, watch pass**

Expected: 377/377 tests pass (369 prior + 8 new).

- [ ] **Step 5: Commit**

```
feat(client): MatchController SHOP phase upgrade

_process_shop async handler replaces sub-project #2's no-op pass-through.
Entry: shuffle CardRegistry.shop_pool() and slice SHOP_OFFER_SIZE = 3 cards
into state.current_shop_offer; clear shop_done_peers; broadcast
_rpc_shop_opened; emit shop_opened signal. Poll per-frame for all active
peers done OR timer expiry. Exit: clear offer + done_peers, broadcast
_rpc_shop_closed, emit shop_closed.

submit_shop_buy + _rpc_shop_buy_requested: validates card in offer,
peer not already done, chips sufficient, hand not full. On accept:
deduct chips, append to hand, mark peer done, broadcast purchase_confirmed
+ apply_deltas. On reject: targeted _rpc_shop_buy_rejected with reason.

submit_shop_done + _rpc_shop_done: peer opts out of SHOP this visit.

shop_timeout_sec_override test seam (mirror of bet_loadout_timeout pattern).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 8: UI widgets

### Task 15: LoadoutOverlay widget

The card hand + loadout slot UI shown during BET_LOADOUT alongside BetLoadoutOverlay.

**Files:**
- Create: `scripts/ui/loadout_overlay.gd`
- Create: `scenes/ui/loadout_overlay.tscn`
- Create: `tests/unit/test_loadout_overlay.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_loadout_overlay.gd`:
```gdscript
extends GutTest

const LoadoutOverlay = preload("res://scripts/ui/loadout_overlay.gd")

func test_format_card_label_known():
    var s = LoadoutOverlay.format_card_label("insurance")
    assert_eq(s, "Insurance")

func test_format_card_label_unknown():
    var s = LoadoutOverlay.format_card_label("nonexistent")
    assert_eq(s, "?")

func test_is_card_playable_in_bet_loadout_window():
    # Insurance is bet_loadout timing; phase BET_LOADOUT (3 per MatchPhase enum)
    var played: Array = []
    assert_true(LoadoutOverlay.is_card_playable("insurance", 3, played))

func test_is_card_playable_outside_window():
    var played: Array = []
    # MAIN_EVENT phase (4 per enum)
    assert_false(LoadoutOverlay.is_card_playable("insurance", 4, played))

func test_is_card_playable_already_played():
    var played: Array = ["insurance"]
    assert_false(LoadoutOverlay.is_card_playable("insurance", 3, played))
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement script**

`scripts/ui/loadout_overlay.gd`:
```gdscript
# LoadoutOverlay: card hand + loadout slot UI shown during BET_LOADOUT.
# Lives in MatchScene's LoadoutSlot. Subscribes to MatchController signals.
extends PanelContainer

const CardRegistry = preload("res://scripts/cards/card_registry.gd")
const MatchPhase = preload("res://scripts/match/match_phase.gd")

@onready var _hand_row: HBoxContainer = $VBox/HandRow if has_node("VBox/HandRow") else null
@onready var _loadout_row: HBoxContainer = $VBox/LoadoutRow if has_node("VBox/LoadoutRow") else null
@onready var _hint_label: Label = $VBox/HintLabel if has_node("VBox/HintLabel") else null

var controller  # MatchController-like (set by MatchScene)
var local_player  # MatchPlayer-like

func _ready() -> void:
    visible = false
    if controller != null:
        controller.bet_loadout_started.connect(_on_bet_loadout_started)
        controller.bet_loadout_finished.connect(_on_bet_loadout_finished)
        controller.loadout_acknowledged.connect(_on_loadout_acknowledged)
        controller.card_effect_applied.connect(_on_card_effect_applied)
        controller.card_play_rejected.connect(_on_card_play_rejected)

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
    # Scene-tree-dependent rendering — exercised by integration tests + playtest.
    # MVP: a placeholder hint label updates with hand size.
    if _hint_label != null and local_player != null:
        _hint_label.text = "Hand: %d / Loadout: %d" % [local_player.hand.size(), local_player.loadout.size()]

# Static formatters (testable without scene)

static func format_card_label(card_id: String) -> String:
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
            continue  # MVP: no self-target
        out.append(p.peer_id)
    return out
```

- [ ] **Step 4: Implement scene**

`scenes/ui/loadout_overlay.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/loadout_overlay.gd" id="1"]

[node name="LoadoutOverlay" type="PanelContainer"]
script = ExtResource("1")

[node name="VBox" type="VBoxContainer" parent="."]

[node name="Title" type="Label" parent="VBox"]
text = "Your Cards"

[node name="HandRow" type="HBoxContainer" parent="VBox"]

[node name="LoadoutRow" type="HBoxContainer" parent="VBox"]

[node name="HintLabel" type="Label" parent="VBox"]
text = "Hand: 0 / Loadout: 0"
```

- [ ] **Step 5: Run, watch pass**

Expected: 382/382 tests pass (377 prior + 5 new).

- [ ] **Step 6: Commit**

```
feat(client): LoadoutOverlay widget for BET_LOADOUT card UI

PanelContainer with hand row + loadout row + hint label. Subscribes to
MatchController.bet_loadout_started/finished/loadout_acknowledged/
card_effect_applied/card_play_rejected.

MVP rendering is a hint label showing "Hand: N / Loadout: M" — full
hand+loadout button-grid is a polish-pass item. Static formatters
format_card_label, is_card_playable, available_targets are unit-tested
without scene instantiation; instance rendering is exercised by Plan B's
integration test and manual playtest.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 16: ShopOverlay widget

Shown during SHOP phase. Renders 3 offered cards + Buy buttons + Done button.

**Files:**
- Create: `scripts/ui/shop_overlay.gd`
- Create: `scenes/ui/shop_overlay.tscn`
- Create: `tests/unit/test_shop_overlay.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_shop_overlay.gd`:
```gdscript
extends GutTest

const ShopOverlay = preload("res://scripts/ui/shop_overlay.gd")

func test_format_shop_offer_returns_per_card_dicts():
    var offered = ["insurance", "heat_shield", "multiplier_booster"]
    var formatted = ShopOverlay.format_shop_offer(offered)
    assert_eq(formatted.size(), 3)
    assert_eq(formatted[0].card_id, "insurance")
    assert_eq(formatted[0].name, "Insurance")
    assert_eq(formatted[0].cost, 50)

func test_can_afford_true_when_chips_meet_cost():
    assert_true(ShopOverlay.can_afford(50, 50))
    assert_true(ShopOverlay.can_afford(100, 50))

func test_can_afford_false_when_chips_less_than_cost():
    assert_false(ShopOverlay.can_afford(49, 50))
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement script**

`scripts/ui/shop_overlay.gd`:
```gdscript
# ShopOverlay: shown during SHOP phase. Renders 3 offered cards + Buy
# buttons + a Done button. Subscribes to MatchController.shop_opened /
# shop_closed.
extends PanelContainer

const CardRegistry = preload("res://scripts/cards/card_registry.gd")

@onready var _offer_row: HBoxContainer = $VBox/OfferRow if has_node("VBox/OfferRow") else null
@onready var _done_button: Button = $VBox/DoneButton if has_node("VBox/DoneButton") else null
@onready var _summary_label: Label = $VBox/SummaryLabel if has_node("VBox/SummaryLabel") else null

var controller  # MatchController-like
var local_player

func _ready() -> void:
    visible = false
    if controller != null:
        controller.shop_opened.connect(_on_shop_opened)
        controller.shop_closed.connect(_on_shop_closed)
    if _done_button != null:
        _done_button.pressed.connect(_on_done_pressed)

func _on_shop_opened(offered: Array) -> void:
    visible = true
    if _summary_label != null and local_player != null:
        _summary_label.text = "Shop open: %d offered, you have %d chips" % [offered.size(), local_player.chips]

func _on_shop_closed() -> void:
    visible = false

func _on_done_pressed() -> void:
    if controller != null:
        controller.submit_shop_done()
        if _done_button != null:
            _done_button.disabled = true

# Static formatters

static func format_shop_offer(offered: Array) -> Array:
    var out: Array = []
    for card_id in offered:
        var card = CardRegistry.get_card(card_id)
        out.append({
            "card_id": card_id,
            "name": String(card.get("name", "?")),
            "description": String(card.get("description", "")),
            "cost": int(card.get("cost_chips", 0)),
        })
    return out

static func can_afford(chips: int, cost: int) -> bool:
    return chips >= cost
```

- [ ] **Step 4: Implement scene**

`scenes/ui/shop_overlay.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/shop_overlay.gd" id="1"]

[node name="ShopOverlay" type="PanelContainer"]
script = ExtResource("1")

[node name="VBox" type="VBoxContainer" parent="."]

[node name="Title" type="Label" parent="VBox"]
text = "Shop"

[node name="OfferRow" type="HBoxContainer" parent="VBox"]

[node name="SummaryLabel" type="Label" parent="VBox"]
text = "Shop open"

[node name="DoneButton" type="Button" parent="VBox"]
text = "Done"
```

- [ ] **Step 5: Run, watch pass**

Expected: 385/385 tests pass (382 prior + 3 new).

- [ ] **Step 6: Commit**

```
feat(client): ShopOverlay widget for SHOP phase

PanelContainer subscribed to controller.shop_opened / shop_closed.
Renders summary label + Done button. Full per-card Buy button grid is
a polish-pass item; MVP shows the offer summary and lets the player
opt out via Done.

Static formatters format_shop_offer (returns per-card metadata dicts)
and can_afford (chip check) are unit-tested.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 17: BountyPanel widget

Shown alongside PlayerPanels. Renders active bounties from `controller.state.bounties`.

**Files:**
- Create: `scripts/ui/bounty_panel.gd`
- Create: `scenes/ui/bounty_panel.tscn`
- Create: `tests/unit/test_bounty_panel.gd`

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_bounty_panel.gd`:
```gdscript
extends GutTest

const BountyPanel = preload("res://scripts/ui/bounty_panel.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func _make_player(peer_id: int, name: String, heat: int = 0) -> RefCounted:
    var p = MatchPlayer.new()
    p.peer_id = peer_id; p.name = name; p.heat = heat
    return p

func test_format_bounty_summary_leader():
    var bounty_dict = {
        "origin": "leader", "target": 2, "condition": "bust",
        "reward_chips": 150, "placed_at_target_heat": 0,
    }
    var target = _make_player(2, "Maya")
    var s = BountyPanel.format_bounty_summary(bounty_dict, target)
    assert_true(s.contains("Maya"))
    assert_true(s.contains("Leader"))
    assert_true(s.contains("150"))

func test_format_bounty_summary_heat_scaled():
    var bounty_dict = {
        "origin": "heat", "target": 2, "condition": "bust",
        "reward_chips": 150, "placed_at_target_heat": 7,
    }
    var target = _make_player(2, "Maya", 7)
    var s = BountyPanel.format_bounty_summary(bounty_dict, target)
    # Should include heat-scaled reward (150 * 1.5 = 225 at heat 7)
    assert_true(s.contains("225") or s.contains("1.5"))
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement script**

`scripts/ui/bounty_panel.gd`:
```gdscript
# BountyPanel: shown alongside PlayerPanels. Lists active bounties.
# Subscribes to controller.bounty_placed.
extends PanelContainer

const Bounty = preload("res://scripts/match/bounty.gd")
const CardRegistry = preload("res://scripts/cards/card_registry.gd")

@onready var _rows: VBoxContainer = $VBox/Rows if has_node("VBox/Rows") else null

var controller

func _ready() -> void:
    if controller != null:
        controller.bounty_placed.connect(_on_bounty_placed)
        controller.bounty_claimed.connect(_on_bounty_claimed)
        controller.bounty_unclaimed.connect(_on_bounty_unclaimed)

func _on_bounty_placed(bounty_dict: Dictionary) -> void:
    _refresh()

func _on_bounty_claimed(_claimant_peer_id: int, _bounty_dict: Dictionary, _reward: int) -> void:
    _refresh()

func _on_bounty_unclaimed(_bounty_dict: Dictionary) -> void:
    _refresh()

func _refresh() -> void:
    if _rows == null or controller == null:
        return
    # Clear and re-render
    for child in _rows.get_children():
        child.queue_free()
    for bounty in controller.state.bounties:
        var label = Label.new()
        var target = controller.state.find_player(bounty.target)
        label.text = format_bounty_summary(bounty.to_dict(), target)
        _rows.add_child(label)

# Static formatter

static func format_bounty_summary(bounty_dict: Dictionary, target_player) -> String:
    var origin = String(bounty_dict.get("origin", "")).capitalize()
    var target_name = target_player.name if target_player != null else ("P%d" % int(bounty_dict.get("target", 0)))
    var base_reward = int(bounty_dict.get("reward_chips", 0))
    var heat = int(bounty_dict.get("placed_at_target_heat", 0))
    var scaled = int(base_reward * CardRegistry.heat_multiplier(heat))
    return "%s Bounty: %s — %d chips for bust" % [origin, target_name, scaled]
```

- [ ] **Step 4: Implement scene**

`scenes/ui/bounty_panel.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/bounty_panel.gd" id="1"]

[node name="BountyPanel" type="PanelContainer"]
script = ExtResource("1")

[node name="VBox" type="VBoxContainer" parent="."]

[node name="Title" type="Label" parent="VBox"]
text = "Bounties"

[node name="Rows" type="VBoxContainer" parent="VBox"]
```

- [ ] **Step 5: Run, watch pass**

Expected: 387/387 tests pass (385 prior + 2 new).

- [ ] **Step 6: Commit**

```
feat(client): BountyPanel widget

PanelContainer subscribed to controller.bounty_placed/claimed/unclaimed.
Renders active state.bounties as labeled rows. Static formatter
format_bounty_summary applies heat-scaled reward via
CardRegistry.heat_multiplier(placed_at_target_heat).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 18: MatchScene wiring

Final integration task. Adds three new slots (LoadoutSlot, ShopSlot, BountyPanelSlot) to MatchScene + wires the new signals.

**Files:**
- Modify: `scripts/ui/match_scene.gd`
- Modify: `scenes/match_scene.tscn`

No new unit test — wiring is exercised by Plan B's integration test and manual playtest.

- [ ] **Step 1: Verify existing tests still pass**

Run the unit suite (387/387). Confirm baseline before modifications.

- [ ] **Step 2: Update scene file**

In `scenes/match_scene.tscn`, add three new container nodes inside `VBox`:
```
[node name="BountyPanelSlot" type="Container" parent="VBox"]

[node name="LoadoutSlot" type="Container" parent="VBox"]

[node name="ShopSlot" type="Container" parent="VBox"]
```

Insert them at appropriate positions in the existing scene structure (preserve order: PlayerPanels → BountyPanelSlot → ... → BetLoadoutSlot → LoadoutSlot → EventSlot → ShopSlot → ResolutionSlot → MatchEndSlot).

- [ ] **Step 3: Update match_scene.gd**

In `scripts/ui/match_scene.gd`, add preloads near the others:
```gdscript
const LoadoutOverlayScene = preload("res://scenes/ui/loadout_overlay.tscn")
const ShopOverlayScene = preload("res://scenes/ui/shop_overlay.tscn")
const BountyPanelScene = preload("res://scenes/ui/bounty_panel.tscn")
```

Add @onready vars:
```gdscript
@onready var _loadout_slot: Container = $VBox/LoadoutSlot if has_node("VBox/LoadoutSlot") else null
@onready var _shop_slot: Container = $VBox/ShopSlot if has_node("VBox/ShopSlot") else null
@onready var _bounty_slot: Container = $VBox/BountyPanelSlot if has_node("VBox/BountyPanelSlot") else null

var _loadout_overlay: Node = null
var _shop_overlay: Node = null
var _bounty_panel: Node = null
```

In `_ready` (after the controller is constructed and existing signals connected), build the three widgets:
```gdscript
# After existing controller.bet_loadout_started.connect(...) etc.
_build_loadout_overlay()
_build_shop_overlay()
_build_bounty_panel()
```

Add the builder methods:
```gdscript
func _build_loadout_overlay() -> void:
    if _loadout_slot == null:
        return
    _loadout_overlay = LoadoutOverlayScene.instantiate()
    _loadout_overlay.controller = controller
    _loadout_overlay.local_player = _find_local_player()
    _loadout_slot.add_child(_loadout_overlay)

func _build_shop_overlay() -> void:
    if _shop_slot == null:
        return
    _shop_overlay = ShopOverlayScene.instantiate()
    _shop_overlay.controller = controller
    _shop_overlay.local_player = _find_local_player()
    _shop_slot.add_child(_shop_overlay)

func _build_bounty_panel() -> void:
    if _bounty_slot == null:
        return
    _bounty_panel = BountyPanelScene.instantiate()
    _bounty_panel.controller = controller
    _bounty_slot.add_child(_bounty_panel)
```

- [ ] **Step 4: Run, watch pass**

Expected: 387/387 tests pass (no new unit tests; existing tests unaffected by the scene/wiring additions).

- [ ] **Step 5: Commit**

```
feat(client): MatchScene wires LoadoutOverlay + ShopOverlay + BountyPanel

Three new slots in match_scene.tscn (LoadoutSlot between BetLoadoutSlot
and EventSlot, ShopSlot between EventSlot and ResolutionSlot,
BountyPanelSlot near the top with PlayerPanels). match_scene.gd builds
each widget after the controller is constructed and passes
controller + local_player.

Plan A complete: bounty system + 6 pre-event cards + SHOP phase + 3
HUD widgets. Plan B follows with the remaining 6 cards (Rocket Clash
event hooks for Cash-Out Jammer + Emergency Eject, plus Heat Spike,
Wager Tax, Place Bounty, Copycat Bet) and the MatchController refactor.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Done

When all checkboxes above are checked, sub-project #4 Plan A is complete:

1. **Bounty system.** Leader + Heat bounties auto-placed at HOUSE_REVEAL of events 1+. Resolution in BOUNTY_HEAT_UPDATE after heat application; reward scales by `placed_at_target_heat`. Place Bounty card lands in Plan B.
2. **6 pre-event cards.** Insurance, Heat Shield, Multiplier Booster, Double or Nothing, Late Cash, Underdog Odds. All play during BET_LOADOUT; all integrate with `RocketClashEvent.compute_event_result` via `event_modifiers`.
3. **Card play pipeline.** `submit_card_play` → `_rpc_card_play_requested` → `CardEffectDispatcher` (currently inlined in MatchController; Plan B extracts) → `_apply_effect_result` mutates state → `_rpc_card_effect_applied` broadcast. Host-authoritative validation throughout.
4. **Loadout management.** Players choose 0-2 cards from their hand for the active loadout. Persists across events; modifiable only during BET_LOADOUT.
5. **SHOP phase upgrade.** 3 cards offered each round; players buy 1 with chips OR opt out via Done. Hand cap at 5; can't buy when full.
6. **Starter pack.** Each player starts with 3 random commons (no Sabotage). Deterministic from `MatchStart.rng_seed`.
7. **HUD widgets.** LoadoutOverlay (hand + loadout), ShopOverlay (offer + buy buttons), BountyPanel (active bounties with heat-scaled rewards).
8. **387 unit + 3 integration tests passing** (up from 292 + 3 baseline; +95 unit). Plan A's integration test slot stays empty — Plan B adds the integration smoke test.

**Tag this milestone after merge:** `cards-and-bounties-plan-a-v0.1`.

**Next step:** Plan B (Power Cards & Bounties Plan B) — adds the remaining 6 cards (Cash-Out Jammer, Emergency Eject, Heat Spike, Wager Tax, Place Bounty, Copycat Bet) including Rocket Clash event-level hooks for the reactive cards, then refactors MatchController into MatchRpcRouter + BountyResolver + ShopController + CardEffectDispatcher collaborators per the spec §10 bundled task. Brainstorm Plan B starting from this spec's §6.7 item 7 and §11 contract.
