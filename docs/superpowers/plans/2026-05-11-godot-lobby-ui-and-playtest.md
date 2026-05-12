# Godot Lobby UI + Manual Playtest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the lobby user interface scenes (MainMenu, Lobby, PlaceholderMatch), CLI flags for headless launches, and run through the spec §9.3 manual playtest checklist. After this plan, sub-project #1 is shippable — a player can launch the game, host or join via a 6-char code, configure name/color/ready, and start a placeholder match scene that receives the `MatchStart` payload.

**Architecture:** Three Godot scenes (`MainMenu.tscn`, `Lobby.tscn`, `PlaceholderMatch.tscn`) consume the `NetSessionMain` autoload. Each scene's script reacts to `NetSessionMain.session` signals and calls its methods for actions. Scene transitions are driven by `state_changed` (IDLE → LOBBY → MATCH) and `match_starting`. CLI flags (`--host-locally`, `--join-code=CODE`) parsed in MainMenu's `_ready` for headless playtest setup. Manual playtest = running the 11 scenarios in spec §9.3 against two real instances on this machine plus one networked counterpart, recording results in a checklist doc.

**Tech Stack:** Godot 4.6 desktop, GDScript, `.tscn` text-format scenes (no editor required to author), GUT for script-logic unit tests, manual two-instance testing for visual/network behavior.

**Parent spec:** [`docs/superpowers/specs/2026-05-10-networking-lobby-foundation-design.md`](../specs/2026-05-10-networking-lobby-foundation-design.md). §6.6 details the lobby UI surface; §9.3 lists the 11 playtest scenarios.

**Companion plans (implemented):**
- Plan A — signaling server: `2026-05-10-signaling-server.md`.
- Plan B — NetSession foundations: `2026-05-11-godot-netsession-foundations.md`.
- Plan C — signaling + WebRTC integration: `2026-05-11-godot-signaling-and-webrtc.md`.

**After Plan D:** Sub-project #1 (Networking & Lobby Foundation) is complete. Next: sub-project #2 (Match Loop & Economy Core) per the original MVP decomposition in `project_riskroyal` memory.

---

## File Structure

```
scripts/
  ui/                              # NEW directory
    main_menu.gd                   # MainMenu controller
    lobby.gd                       # Lobby controller
    placeholder_match.gd           # placeholder match scene
  util/                            # NEW directory
    cli_args.gd                    # CLI flag parsing helper
  net/
    net_session.gd                 # MODIFY: add public set_name(value)
scenes/                            # NEW directory
  main_menu.tscn                   # title + Host/Join buttons + code dialog
  lobby.tscn                       # 8 slots + name/color/ready + Start/Kick + pause overlay
  placeholder_match.tscn           # displays MatchStart contents
tests/unit/
  test_cli_args.gd                 # CLI parser tests
  test_main_menu_logic.gd          # MainMenu script logic (no scene)
  test_lobby_logic.gd              # Lobby script logic (no scene)
  test_placeholder_match_logic.gd  # PlaceholderMatch script logic (no scene)
  test_net_session_set_name.gd     # set_name wrapper tests
project.godot                      # MODIFY: run/main_scene = MainMenu
docs/
  PLAYTEST_CHECKLIST.md            # NEW: spec §9.3 results
```

**Per-file responsibility:**

- `main_menu.gd` — Title screen behavior. Wires the two buttons + code dialog to `NetSessionMain.session.host_session()` / `join_session(code)`. Transitions to `lobby.tscn` on `state_changed(LOBBY)`. Reads CLI args via `CliArgs` and auto-fires Host/Join in headless mode.
- `lobby.gd` — Renders 8 slot widgets from `NetSessionMain.session.players`, watches `players_changed` to re-render. Local-player controls (name LineEdit, color OptionButton, ready CheckBox) call `set_name` / `set_color` / `set_ready`. Host-only Start button + per-slot Kick buttons. Pause overlay on `state == PAUSED`. Transitions to `placeholder_match.tscn` on `match_starting`.
- `placeholder_match.gd` — Receives the `MatchStart` payload (via `NetSessionMain.session.match_starting` signal already fired from Lobby; we read `MatchStart` from autoload). Shows a Label with `seats[]`, `rng_seed`, `mode`. Sub-project #2 will replace this scene with the real match loop.
- `cli_args.gd` — Static helper: `parse_cli() -> Dictionary` returns `{host_locally: bool, join_code: String}` from `OS.get_cmdline_args()`.
- `net_session.gd` (modify) — Add `set_name(value: String)` public wrapper, symmetric with `set_ready` / `set_color`.

**Per-scene structure (kept minimal — `.tscn` files are committed as plain text):**

- `main_menu.tscn`: Control (root) with:
  - VBoxContainer
    - Label "Risk Royal"
    - Button "Host" (`name="HostButton"`)
    - Button "Join" (`name="JoinButton"`)
  - AcceptDialog (initially hidden) with LineEdit (`name="CodeInput"`, max_length=6) and OK/Cancel
  - script_path = `res://scripts/ui/main_menu.gd`

- `lobby.tscn`: Control (root) with:
  - VBoxContainer
    - Label `name="CodeLabel"` (host-only visibility, shows the code)
    - HBoxContainer with 8 children — each is a small VBox showing slot info, kick button (host-only)
    - Local-player panel: LineEdit (name), OptionButton (color), CheckBox (ready), Button "Start" (host-only)
  - PanelContainer `name="PauseOverlay"` (initially hidden) with Label `name="PauseLabel"` and Label `name="CountdownLabel"`
  - script_path = `res://scripts/ui/lobby.gd`

- `placeholder_match.tscn`: Control (root) with:
  - VBoxContainer
    - Label "Match starting!"
    - Label `name="MatchInfoLabel"` (multiline, shows MatchStart contents)
  - script_path = `res://scripts/ui/placeholder_match.gd`

## Conventions

- **TDD where applicable:** script logic that doesn't depend on the scene tree (CLI parsing, state-driven view updates, button handlers as pure functions) gets unit tests. Scene tree / signal-connection wiring gets manual playtest verification only.
- **Test session injection pattern:** UI scripts default to `NetSessionMain.session` in `_ready()` but expose a `var session` property tests can set BEFORE `_ready` runs (via `var lobby = preload(...).new(); lobby.session = test_session;`). This sidesteps the autoload-singleton mocking problem.
- **`.tscn` files committed as plain text:** Godot's text format is greppable and human-editable; we author them directly without launching the editor. The implementer should validate each scene loads cleanly with `godot --headless --quit --path .` after each scene creation.
- **Commit prefixes:** `feat(client):`, `test(client):`, `chore(client):`, `docs(client):`. Avoid apostrophes in commit message bodies (PowerShell here-string quirk).
- **Tabs for indentation in `.gd` files.**
- **Co-author footer required:**
  ```
  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  ```
- Headless GUT command:
  ```
  godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
  ```

---

## Phase 1: NetSession public surface completion

### Task 1: Add `set_name(value)` public wrapper

Symmetric with `set_ready` / `set_color`. Local user updates their displayed name; in production this routes through the host validator (in Plan B/C, `receive_player_info`). For Plan D, follow the same pattern Plan B established for `set_ready`/`set_color`: host calls the receive_* validator directly; joiner side TODOs the RPC for the future Plan E (or whenever the joiner-side intent RPCs land).

**Files:**
- Modify: `scripts/net/net_session.gd`
- Create: `tests/unit/test_net_session_set_name.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_net_session_set_name.gd`:
```gdscript
extends GutTest

const NetSession = preload("res://scripts/net/net_session.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")

var transport
var signaling
var session

func before_each():
    transport = FakeTransport.new()
    signaling = FakeSignalingClient.new()
    session = NetSession.new(transport, signaling)
    session.host_session()
    signaling.emit_code_issued("ABC234")

func _slot(peer_id: int):
    for s in session.players:
        if s.peer_id == peer_id:
            return s
    return null

func test_set_name_routes_through_host_validator():
    session.set_name("Maya")
    assert_eq(_slot(1).name, "Maya")

func test_set_name_truncates_long_names():
    session.set_name("x".repeat(50))
    assert_eq(_slot(1).name.length(), 16)

func test_set_name_empty_falls_back_to_player_n():
    session.set_name("")
    assert_eq(_slot(1).name, "Player 1")
```

- [ ] **Step 2: Run, watch fail**

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
```

Expected: 3 new tests fail (no `set_name` method).

- [ ] **Step 3: Implement**

In `scripts/net/net_session.gd`, add near `set_ready` / `set_color`:
```gdscript
func set_name(value: String) -> void:
    if is_host:
        var slot = _find_slot(local_peer_id)
        if slot != null:
            receive_player_info(local_peer_id, value, slot.color_index)
    # TODO(plan-e): joiner case routes via rpc.request_set_name(value) to host
```

The host-side path calls `receive_player_info` which already handles name normalization (truncate to 16, empty → "Player N"). It re-passes the current color so we don't clobber it.

- [ ] **Step 4: Run, watch pass**

Expected: 96/96 unit tests pass (93 prior + 3 new).

- [ ] **Step 5: Commit**

```
feat(client): NetSession public set_name wrapper

Local-user-facing method symmetric with set_ready / set_color. Routes
through receive_player_info on the host so name normalization (16-char
truncate, empty-string fallback to Player N) is applied consistently.
Non-host case is TODO for a future joiner-RPC plan.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 2: CLI arg parser

### Task 2: `CliArgs` static helper

**Files:**
- Create: `scripts/util/cli_args.gd`
- Create: `tests/unit/test_cli_args.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_cli_args.gd`:
```gdscript
extends GutTest

const CliArgs = preload("res://scripts/util/cli_args.gd")

func test_empty_argv_yields_no_flags():
    var r = CliArgs.parse([])
    assert_false(r.host_locally)
    assert_eq(r.join_code, "")

func test_host_locally_flag():
    var r = CliArgs.parse(["--host-locally"])
    assert_true(r.host_locally)

func test_join_code_flag():
    var r = CliArgs.parse(["--join-code=ABC234"])
    assert_eq(r.join_code, "ABC234")

func test_unknown_flags_ignored():
    var r = CliArgs.parse(["--unknown", "positional", "--some-other=value"])
    assert_false(r.host_locally)
    assert_eq(r.join_code, "")

func test_combined_flags():
    var r = CliArgs.parse(["--host-locally", "--join-code=XYZ789", "--unrelated"])
    assert_true(r.host_locally)
    assert_eq(r.join_code, "XYZ789")

func test_join_code_uppercases():
    # Per spec, codes are case-insensitive and normalized upstream, but the
    # CLI parser shouldn't pre-transform — the signaling server's normalizeCode
    # handles it. Just verify we pass the raw string.
    var r = CliArgs.parse(["--join-code=abc234"])
    assert_eq(r.join_code, "abc234")
```

- [ ] **Step 2: Run, watch fail**

Expected: preload failure (cli_args.gd doesn't exist).

- [ ] **Step 3: Implement**

`scripts/util/cli_args.gd`:
```gdscript
# Parses Godot OS.get_cmdline_args() into a flag dictionary.
# Recognized flags:
#   --host-locally           : auto-host on MainMenu boot
#   --join-code=CODE         : auto-join with CODE on MainMenu boot
# Unknown args are ignored.
extends Object

static func parse(argv: Array) -> Dictionary:
    var result := {
        "host_locally": false,
        "join_code": "",
    }
    for arg in argv:
        if typeof(arg) != TYPE_STRING:
            continue
        if arg == "--host-locally":
            result["host_locally"] = true
        elif arg.begins_with("--join-code="):
            result["join_code"] = arg.substr("--join-code=".length())
    return result

static func from_cmdline() -> Dictionary:
    return parse(OS.get_cmdline_args())
```

- [ ] **Step 4: Run, watch pass**

Expected: 102/102 unit tests pass (96 prior + 6 new).

- [ ] **Step 5: Commit**

```
feat(client): CliArgs parser for --host-locally and --join-code

Static helper that converts Godot OS.get_cmdline_args output into a
flag dictionary. Used by MainMenu to auto-fire Host or Join in headless
playtest runs. Unknown flags ignored (forward compat).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 3: PlaceholderMatch scene

### Task 3: PlaceholderMatch scene + script

Simple — just displays the received MatchStart. Building this first because it's the smallest scene; other tasks transition into it.

**Files:**
- Create: `scripts/ui/placeholder_match.gd`
- Create: `scenes/placeholder_match.tscn`
- Create: `tests/unit/test_placeholder_match_logic.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_placeholder_match_logic.gd`:
```gdscript
extends GutTest

const PlaceholderMatch = preload("res://scripts/ui/placeholder_match.gd")
const MatchStart = preload("res://scripts/data/match_start.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")

func _build_match_start():
    var ms = MatchStart.new()
    var s1 = PlayerSlot.new()
    s1.peer_id = 1; s1.is_host = true; s1.seat_index = 0; s1.name = "Host"; s1.color_index = 2
    var s2 = PlayerSlot.new()
    s2.peer_id = 2; s2.seat_index = 1; s2.name = "Maya"; s2.color_index = 5
    ms.seats = [s1, s2]
    ms.host_peer_id = 1
    ms.rng_seed = 0xCAFEBABE
    ms.mode = "quick_clash"
    return ms

func test_format_match_start_contains_seat_count():
    var ms = _build_match_start()
    var text = PlaceholderMatch.format_match_start(ms)
    assert_true("2 player" in text, "expected mention of player count, got: %s" % text)

func test_format_match_start_contains_seed_in_hex():
    var ms = _build_match_start()
    var text = PlaceholderMatch.format_match_start(ms)
    assert_true("cafebabe" in text.to_lower() or "CAFEBABE" in text, "expected seed in hex, got: %s" % text)

func test_format_match_start_lists_all_seat_names():
    var ms = _build_match_start()
    var text = PlaceholderMatch.format_match_start(ms)
    assert_true("Host" in text)
    assert_true("Maya" in text)

func test_format_match_start_contains_mode():
    var ms = _build_match_start()
    var text = PlaceholderMatch.format_match_start(ms)
    assert_true("quick_clash" in text)
```

- [ ] **Step 2: Run, watch fail**

Expected: preload failure.

- [ ] **Step 3: Implement script**

`scripts/ui/placeholder_match.gd`:
```gdscript
# Placeholder scene shown after the host clicks Start. Displays the MatchStart
# payload for diagnostic purposes. Sub-project #2 will replace this with the
# real match loop scene.
extends Control

@onready var _info_label: Label = $VBoxContainer/MatchInfoLabel

func _ready() -> void:
    var ms = _read_match_start_from_autoload()
    if ms == null:
        _info_label.text = "(no MatchStart available)"
        return
    _info_label.text = format_match_start(ms)

func _read_match_start_from_autoload():
    # Lobby cached the MatchStart on NetSessionMain.last_match_start before
    # transitioning to this scene. See lobby.gd._on_match_starting.
    if not get_tree().root.has_node("NetSessionMain"):
        return null
    var nsm = get_tree().root.get_node("NetSessionMain")
    if not nsm.has_method("get_last_match_start"):
        return null
    return nsm.get_last_match_start()

static func format_match_start(ms) -> String:
    var lines: Array = []
    lines.append("Match starting!")
    lines.append("Mode: %s" % ms.mode)
    lines.append("Host peer_id: %d" % ms.host_peer_id)
    lines.append("RNG seed: 0x%X" % ms.rng_seed)
    lines.append("%d players:" % ms.seats.size())
    for s in ms.seats:
        var host_tag = " (host)" if s.is_host else ""
        lines.append("  seat %d: %s [color %d] peer_id=%d%s" % [s.seat_index, s.name, s.color_index, s.peer_id, host_tag])
    return "\n".join(lines)
```

- [ ] **Step 4: Implement scene**

`scenes/placeholder_match.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/placeholder_match.gd" id="1"]

[node name="PlaceholderMatch" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="VBoxContainer" type="VBoxContainer" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -200.0
offset_top = -100.0
offset_right = 200.0
offset_bottom = 100.0

[node name="MatchInfoLabel" type="Label" parent="VBoxContainer"]
layout_mode = 2
text = "..."
```

- [ ] **Step 5: Add `get_last_match_start` accessor to NetSessionMain**

In `scripts/net/net_session_main.gd`, add a field + getter:
```gdscript
var _last_match_start = null

func get_last_match_start():
    return _last_match_start
```

And subscribe to the session's `match_starting` signal during `_ready` so the autoload caches the most recent payload:
```gdscript
# In _ready, after the other session signal wirings:
session.match_starting.connect(_on_match_starting)

func _on_match_starting(match_start) -> void:
    _last_match_start = match_start
```

- [ ] **Step 6: Verify scene loads + tests pass**

```
godot --headless --path . --quit
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
```

Expected: scene loads without errors (no print on first command means OK). 106/106 unit tests pass (102 prior + 4 new).

- [ ] **Step 7: Commit**

```
feat(client): PlaceholderMatch scene displays MatchStart payload

Minimal Control scene shown after host clicks Start. Reads the cached
MatchStart from NetSessionMain.get_last_match_start (populated when
NetSession.match_starting fires). Sub-project 2 will replace this with
the real match loop scene.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 4: MainMenu scene

### Task 4: MainMenu scene skeleton + script wiring

**Files:**
- Create: `scripts/ui/main_menu.gd`
- Create: `scenes/main_menu.tscn`
- Create: `tests/unit/test_main_menu_logic.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_main_menu_logic.gd`:
```gdscript
extends GutTest

const MainMenu = preload("res://scripts/ui/main_menu.gd")
const NetSession = preload("res://scripts/net/net_session.gd")
const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")

var session
var menu

func before_each():
    var t = FakeTransport.new()
    var s = FakeSignalingClient.new()
    session = NetSession.new(t, s)
    menu = MainMenu.new()
    menu.session = session  # bypass autoload

func test_on_host_pressed_invokes_host_session():
    menu._on_host_pressed()
    assert_true(session.is_host)

func test_on_join_with_code_invokes_join_session():
    menu._on_join_with_code("ABC234")
    assert_eq(session._signaling.connect_to_code_calls[0].code, "ABC234")

func test_normalize_code_input_uppercases():
    assert_eq(MainMenu.normalize_code_input("abc234"), "ABC234")
    assert_eq(MainMenu.normalize_code_input("  AbC234  "), "ABC234")

func test_normalize_code_input_rejects_too_short():
    assert_eq(MainMenu.normalize_code_input("abc"), "")

func test_normalize_code_input_rejects_too_long():
    assert_eq(MainMenu.normalize_code_input("abcdef234"), "")
```

- [ ] **Step 2: Run, watch fail**

Expected: preload failure.

- [ ] **Step 3: Implement script**

`scripts/ui/main_menu.gd`:
```gdscript
# Title screen with Host / Join buttons. The Join button opens an AcceptDialog
# for code entry. Auto-fires Host or Join when CLI flags are present
# (--host-locally / --join-code=CODE).
extends Control

const CliArgs = preload("res://scripts/util/cli_args.gd")

var session  # NetSession-like; defaults to NetSessionMain.session

@onready var _host_button: Button = $VBoxContainer/HostButton if has_node("VBoxContainer/HostButton") else null
@onready var _join_button: Button = $VBoxContainer/JoinButton if has_node("VBoxContainer/JoinButton") else null
@onready var _join_dialog: AcceptDialog = $JoinDialog if has_node("JoinDialog") else null
@onready var _code_input: LineEdit = $JoinDialog/CodeInput if has_node("JoinDialog/CodeInput") else null

func _ready() -> void:
    if session == null:
        if get_tree().root.has_node("NetSessionMain"):
            session = get_tree().root.get_node("NetSessionMain").session
    if session == null:
        push_warning("MainMenu has no session; UI buttons will be inert")
        return

    if _host_button != null:
        _host_button.pressed.connect(_on_host_pressed)
    if _join_button != null:
        _join_button.pressed.connect(_on_join_pressed)
    if _join_dialog != null:
        _join_dialog.confirmed.connect(_on_join_dialog_confirmed)
    session.state_changed.connect(_on_state_changed)

    # CLI flag handling for headless playtest runs.
    var args := CliArgs.from_cmdline()
    if args.host_locally:
        _on_host_pressed()
    elif args.join_code != "":
        _on_join_with_code(args.join_code)

func _on_host_pressed() -> void:
    session.host_session()

func _on_join_pressed() -> void:
    if _join_dialog != null:
        _join_dialog.popup_centered()

func _on_join_dialog_confirmed() -> void:
    var code := normalize_code_input(_code_input.text) if _code_input != null else ""
    if code != "":
        _on_join_with_code(code)

func _on_join_with_code(code: String) -> void:
    session.join_session(code)

func _on_state_changed(new_state: int) -> void:
    if new_state == 1:  # NetSessionState.LOBBY
        get_tree().change_scene_to_file("res://scenes/lobby.tscn")

static func normalize_code_input(text: String) -> String:
    var trimmed := text.strip_edges().to_upper()
    if trimmed.length() != 6:
        return ""
    return trimmed
```

- [ ] **Step 4: Implement scene**

`scenes/main_menu.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/main_menu.gd" id="1"]

[node name="MainMenu" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="VBoxContainer" type="VBoxContainer" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -100.0
offset_top = -60.0
offset_right = 100.0
offset_bottom = 60.0

[node name="TitleLabel" type="Label" parent="VBoxContainer"]
layout_mode = 2
text = "Risk Royal"
horizontal_alignment = 1

[node name="HostButton" type="Button" parent="VBoxContainer"]
layout_mode = 2
text = "Host"

[node name="JoinButton" type="Button" parent="VBoxContainer"]
layout_mode = 2
text = "Join"

[node name="JoinDialog" type="AcceptDialog" parent="."]
title = "Enter join code"
size = Vector2i(300, 100)

[node name="CodeInput" type="LineEdit" parent="JoinDialog"]
offset_left = 8.0
offset_top = 8.0
offset_right = 290.0
offset_bottom = 40.0
max_length = 6
placeholder_text = "ABCDEF"
```

- [ ] **Step 5: Run scene-load check + tests**

```
godot --headless --path . --quit
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
```

Expected: scene loads, 111/111 tests pass (106 prior + 5 new).

- [ ] **Step 6: Commit**

```
feat(client): MainMenu scene with Host/Join and CLI flag support

Title screen Control scene with Host button, Join button + AcceptDialog
for 6-char code entry, and CLI flag handling. --host-locally auto-fires
host on _ready; --join-code=ABC234 auto-fires join. Transitions to
lobby.tscn on state_changed(LOBBY).

normalize_code_input is a pure-function static method tests can drive
without instantiating the scene; it uppercases and strips edges,
rejecting non-6-char inputs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 5: Lobby scene

The lobby scene is the largest piece. Splitting into 4 tasks: skeleton, local-player controls, host-only controls, pause overlay.

### Task 5: Lobby scene skeleton + slot rendering

**Files:**
- Create: `scripts/ui/lobby.gd`
- Create: `scenes/lobby.tscn`
- Create: `tests/unit/test_lobby_logic.gd`

- [ ] **Step 1: Write failing tests**

`tests/unit/test_lobby_logic.gd`:
```gdscript
extends GutTest

const Lobby = preload("res://scripts/ui/lobby.gd")
const NetSession = preload("res://scripts/net/net_session.gd")
const PlayerSlot = preload("res://scripts/data/player_slot.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")

func _make_session():
    var t = FakeTransport.new()
    var s = FakeSignalingClient.new()
    var session = NetSession.new(t, s)
    session.host_session()
    s.emit_code_issued("ABC234")
    return session

func test_format_slot_for_empty_returns_placeholder():
    assert_eq(Lobby.format_slot_label(null), "(empty)")

func test_format_slot_for_filled_includes_name_and_color():
    var s = PlayerSlot.new()
    s.name = "Maya"
    s.color_index = 3
    s.ready = false
    assert_true("Maya" in Lobby.format_slot_label(s))
    assert_true("color 3" in Lobby.format_slot_label(s))

func test_format_slot_marks_ready():
    var s = PlayerSlot.new()
    s.name = "Maya"
    s.color_index = 3
    s.ready = true
    assert_true("READY" in Lobby.format_slot_label(s))

func test_format_slot_marks_host():
    var s = PlayerSlot.new()
    s.name = "Host"
    s.is_host = true
    assert_true("(host)" in Lobby.format_slot_label(s))

func test_format_slot_marks_disconnected():
    var s = PlayerSlot.new()
    s.name = "Maya"
    s.connected = false
    assert_true("disconnected" in Lobby.format_slot_label(s).to_lower())
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement script (skeleton)**

`scripts/ui/lobby.gd`:
```gdscript
# Lobby scene. Renders 8 player-slot widgets, hosts the code display,
# wires local-player controls (name/color/ready), and shows the pause
# overlay when state == PAUSED. Host-only Start + Kick buttons added
# in later tasks.
extends Control

const MAX_SLOTS := 8
const NetSessionState = preload("res://scripts/data/net_session_state.gd")

var session  # NetSession-like

@onready var _code_label: Label = $VBoxContainer/CodeLabel if has_node("VBoxContainer/CodeLabel") else null
@onready var _slot_container: HBoxContainer = $VBoxContainer/SlotContainer if has_node("VBoxContainer/SlotContainer") else null

func _ready() -> void:
    if session == null:
        if get_tree().root.has_node("NetSessionMain"):
            session = get_tree().root.get_node("NetSessionMain").session
    if session == null:
        push_warning("Lobby has no session")
        return

    session.players_changed.connect(_refresh)
    session.state_changed.connect(_on_state_changed)
    session.match_starting.connect(_on_match_starting)

    _refresh()

func _refresh() -> void:
    if _code_label != null and session.is_host:
        _code_label.text = "Code: %s" % session.code
        _code_label.visible = true
    elif _code_label != null:
        _code_label.visible = false

    if _slot_container == null:
        return
    # Render exactly MAX_SLOTS labels; fill from session.players, blank rest.
    for i in MAX_SLOTS:
        var label_node: Label = _slot_container.get_node_or_null("Slot%d" % i)
        if label_node == null:
            continue
        var slot = session.players[i] if i < session.players.size() else null
        label_node.text = format_slot_label(slot)

func _on_state_changed(new_state: int) -> void:
    pass  # filled in by Task 8 (pause overlay)

func _on_match_starting(_match_start) -> void:
    get_tree().change_scene_to_file("res://scenes/placeholder_match.tscn")

static func format_slot_label(slot) -> String:
    if slot == null:
        return "(empty)"
    var parts: Array = []
    parts.append(slot.name if not slot.name.is_empty() else "(unnamed)")
    if slot.is_host:
        parts.append("(host)")
    parts.append("color %d" % slot.color_index)
    if slot.ready:
        parts.append("READY")
    if not slot.connected:
        parts.append("disconnected")
    return " ".join(parts)
```

- [ ] **Step 4: Implement scene (skeleton — 8 slot labels)**

`scenes/lobby.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/lobby.gd" id="1"]

[node name="Lobby" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="VBoxContainer" type="VBoxContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 16.0
offset_top = 16.0
offset_right = -16.0
offset_bottom = -16.0

[node name="CodeLabel" type="Label" parent="VBoxContainer"]
layout_mode = 2
text = "Code: ------"

[node name="SlotContainer" type="HBoxContainer" parent="VBoxContainer"]
layout_mode = 2

[node name="Slot0" type="Label" parent="VBoxContainer/SlotContainer"]
layout_mode = 2
text = "(empty)"
custom_minimum_size = Vector2(140, 60)

[node name="Slot1" type="Label" parent="VBoxContainer/SlotContainer"]
layout_mode = 2
text = "(empty)"
custom_minimum_size = Vector2(140, 60)

[node name="Slot2" type="Label" parent="VBoxContainer/SlotContainer"]
layout_mode = 2
text = "(empty)"
custom_minimum_size = Vector2(140, 60)

[node name="Slot3" type="Label" parent="VBoxContainer/SlotContainer"]
layout_mode = 2
text = "(empty)"
custom_minimum_size = Vector2(140, 60)

[node name="Slot4" type="Label" parent="VBoxContainer/SlotContainer"]
layout_mode = 2
text = "(empty)"
custom_minimum_size = Vector2(140, 60)

[node name="Slot5" type="Label" parent="VBoxContainer/SlotContainer"]
layout_mode = 2
text = "(empty)"
custom_minimum_size = Vector2(140, 60)

[node name="Slot6" type="Label" parent="VBoxContainer/SlotContainer"]
layout_mode = 2
text = "(empty)"
custom_minimum_size = Vector2(140, 60)

[node name="Slot7" type="Label" parent="VBoxContainer/SlotContainer"]
layout_mode = 2
text = "(empty)"
custom_minimum_size = Vector2(140, 60)
```

- [ ] **Step 5: Verify scene loads + tests pass**

```
godot --headless --path . --quit
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
```

Expected: 116/116 tests pass (111 prior + 5 new).

- [ ] **Step 6: Commit**

```
feat(client): Lobby scene skeleton with 8-slot rendering

Control scene with code display (host-only), HBox of 8 Slot labels, and
script that re-renders on players_changed. format_slot_label is a pure
static method that produces a one-line summary including name, host
indicator, color index, ready flag, and disconnect indicator. Real
local-player controls and host buttons added in subsequent tasks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 6: Lobby local-player controls

Add the name input, color picker, and ready checkbox. Wire to `session.set_name`, `set_color`, `set_ready`.

**Files:**
- Modify: `scripts/ui/lobby.gd`
- Modify: `scenes/lobby.tscn`
- Modify: `tests/unit/test_lobby_logic.gd`

- [ ] **Step 1: Append tests**

In `tests/unit/test_lobby_logic.gd`:
```gdscript
func test_on_name_submitted_calls_set_name():
    var session = _make_session()
    var lobby = Lobby.new()
    lobby.session = session
    lobby._on_name_submitted("Maya")
    var slot = session.players[0]
    assert_eq(slot.name, "Maya")

func test_on_color_picked_calls_set_color():
    var session = _make_session()
    var lobby = Lobby.new()
    lobby.session = session
    lobby._on_color_picked(4)
    var slot = session.players[0]
    assert_eq(slot.color_index, 4)

func test_on_ready_toggled_calls_set_ready():
    var session = _make_session()
    var lobby = Lobby.new()
    lobby.session = session
    lobby._on_ready_toggled(true)
    var slot = session.players[0]
    assert_true(slot.ready)
```

- [ ] **Step 2: Run, watch fail**

Expected: 3 new tests fail.

- [ ] **Step 3: Implement script handlers**

Add to `scripts/ui/lobby.gd`:
```gdscript
@onready var _name_input: LineEdit = $VBoxContainer/LocalPanel/NameInput if has_node("VBoxContainer/LocalPanel/NameInput") else null
@onready var _color_picker: OptionButton = $VBoxContainer/LocalPanel/ColorPicker if has_node("VBoxContainer/LocalPanel/ColorPicker") else null
@onready var _ready_check: CheckBox = $VBoxContainer/LocalPanel/ReadyCheck if has_node("VBoxContainer/LocalPanel/ReadyCheck") else null

# Inside _ready, after the session-signal wiring, add:
#     if _name_input != null:
#         _name_input.text_submitted.connect(_on_name_submitted)
#     if _color_picker != null:
#         _color_picker.item_selected.connect(_on_color_picked)
#     if _ready_check != null:
#         _ready_check.toggled.connect(_on_ready_toggled)

func _on_name_submitted(value: String) -> void:
    session.set_name(value)

func _on_color_picked(index: int) -> void:
    session.set_color(index)

func _on_ready_toggled(pressed: bool) -> void:
    session.set_ready(pressed)
```

Place the `@onready` lines near the top with the other ones, and the inline _ready additions inside the existing _ready function (after the `_refresh()` call but inside the `if session != null:` block).

- [ ] **Step 4: Update scene**

In `scenes/lobby.tscn`, add a LocalPanel after SlotContainer:
```
[node name="LocalPanel" type="HBoxContainer" parent="VBoxContainer"]
layout_mode = 2

[node name="NameLabel" type="Label" parent="VBoxContainer/LocalPanel"]
layout_mode = 2
text = "Name:"

[node name="NameInput" type="LineEdit" parent="VBoxContainer/LocalPanel"]
layout_mode = 2
custom_minimum_size = Vector2(160, 0)
max_length = 16
placeholder_text = "your name"

[node name="ColorLabel" type="Label" parent="VBoxContainer/LocalPanel"]
layout_mode = 2
text = "Color:"

[node name="ColorPicker" type="OptionButton" parent="VBoxContainer/LocalPanel"]
layout_mode = 2
item_count = 8
popup/item_0/text = "Red"
popup/item_1/text = "Orange"
popup/item_2/text = "Yellow"
popup/item_3/text = "Green"
popup/item_4/text = "Cyan"
popup/item_5/text = "Blue"
popup/item_6/text = "Purple"
popup/item_7/text = "Pink"

[node name="ReadyCheck" type="CheckBox" parent="VBoxContainer/LocalPanel"]
layout_mode = 2
text = "Ready"
```

- [ ] **Step 5: Verify scene loads + tests pass**

Expected: 119/119 tests pass.

- [ ] **Step 6: Commit**

```
feat(client): Lobby local-player controls (name/color/ready)

LineEdit for name, OptionButton with 8 named colors, CheckBox for ready.
Wired to session.set_name / set_color / set_ready. Handlers exposed as
testable methods (_on_name_submitted etc.).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 7: Lobby host-only controls (Start + Kick)

**Files:**
- Modify: `scripts/ui/lobby.gd`
- Modify: `scenes/lobby.tscn`
- Modify: `tests/unit/test_lobby_logic.gd`

- [ ] **Step 1: Append tests**

```gdscript
func test_start_button_visible_only_for_host():
    var session = _make_session()
    # session.is_host == true after host_session()
    assert_true(Lobby.should_show_start_button(session))

func test_start_button_hidden_for_joiner():
    var t = FakeTransport.new()
    var s = FakeSignalingClient.new()
    var joiner = NetSession.new(t, s)
    joiner.join_session("ABC234")
    assert_false(Lobby.should_show_start_button(joiner))

func test_start_button_enabled_only_when_all_ready_and_2_plus_players():
    var session = _make_session()
    # Just host, not ready
    assert_false(Lobby.is_start_button_enabled(session))
    # Add a joiner
    session._transport.emit_peer_joined(2)
    session.receive_player_info(2, "Maya", 3)
    assert_false(Lobby.is_start_button_enabled(session))  # nobody ready
    session.receive_set_ready(1, true)
    session.receive_set_ready(2, true)
    assert_true(Lobby.is_start_button_enabled(session))

func test_on_start_pressed_calls_start_match():
    var session = _make_session()
    session._transport.emit_peer_joined(2)
    session.receive_player_info(2, "Maya", 3)
    session.receive_set_ready(1, true)
    session.receive_set_ready(2, true)
    var lobby = Lobby.new()
    lobby.session = session
    var emitted = [null]
    session.match_starting.connect(func(ms): emitted[0] = ms)
    lobby._on_start_pressed()
    assert_not_null(emitted[0])

func test_on_kick_pressed_calls_kick():
    var session = _make_session()
    session._transport.emit_peer_joined(2)
    session.receive_player_info(2, "Maya", 3)
    var lobby = Lobby.new()
    lobby.session = session
    lobby._on_kick_pressed(2)
    assert_null(_find_slot(session, 2))

func _find_slot(session, peer_id: int):
    for s in session.players:
        if s.peer_id == peer_id:
            return s
    return null
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

Add to `scripts/ui/lobby.gd`:
```gdscript
@onready var _start_button: Button = $VBoxContainer/HostControls/StartButton if has_node("VBoxContainer/HostControls/StartButton") else null

# In _ready, after the local-player wiring, add:
#     if _start_button != null:
#         _start_button.pressed.connect(_on_start_pressed)

# In _refresh, at the end:
func _refresh_host_controls() -> void:
    if _start_button == null:
        return
    _start_button.visible = should_show_start_button(session)
    _start_button.disabled = not is_start_button_enabled(session)

# Modify _refresh to call _refresh_host_controls() at the end.

func _on_start_pressed() -> void:
    session.start_match()

func _on_kick_pressed(peer_id: int) -> void:
    session.kick(peer_id)

static func should_show_start_button(session) -> bool:
    return session != null and session.is_host

static func is_start_button_enabled(session) -> bool:
    if session == null:
        return false
    if not session.is_host:
        return false
    if session.players.size() < 2:
        return false
    for p in session.players:
        if not p.ready:
            return false
    return true
```

For per-slot kick buttons: this requires turning each slot from a Label into a small Control container (Label + Kick Button). For Plan D's MVP, keep slots as Labels and instead make `_refresh` build kick buttons in a parallel container when the user is host. That's complex for a text-format .tscn — instead, add a single "Kick last joiner" debug button for host that prompts a peer_id. **Defer real per-slot kick UI to a future polish task** and just document `_on_kick_pressed` as a public method called by future widgets.

(The test `test_on_kick_pressed_calls_kick` still passes because we expose the method.)

Update the .tscn:
```
[node name="HostControls" type="HBoxContainer" parent="VBoxContainer"]
layout_mode = 2

[node name="StartButton" type="Button" parent="VBoxContainer/HostControls"]
layout_mode = 2
text = "Start Match"
disabled = true
```

- [ ] **Step 4: Verify scene loads + tests pass**

Expected: 124/124 tests pass.

- [ ] **Step 5: Commit**

```
feat(client): Lobby host-only Start button + kick method

Start button visible only for host, gated on 2+ players all ready.
should_show_start_button and is_start_button_enabled are pure static
methods tests can verify without instantiating the scene. _on_kick_pressed
public method exposed for future per-slot kick widgets; the visible UI
keeps Labels for slots in this plan, with per-slot kick deferred.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 8: Lobby pause overlay

**Files:**
- Modify: `scripts/ui/lobby.gd`
- Modify: `scenes/lobby.tscn`
- Modify: `tests/unit/test_lobby_logic.gd`

- [ ] **Step 1: Append tests**

```gdscript
func test_pause_overlay_hidden_in_lobby_state():
    var session = _make_session()
    assert_false(Lobby.should_show_pause_overlay(session.state))

func test_pause_overlay_shown_in_paused_state():
    assert_true(Lobby.should_show_pause_overlay(3))  # NetSessionState.State.PAUSED == 3

func test_format_pause_message_lists_disconnected_player():
    var s1 = PlayerSlot.new()
    s1.name = "Host"; s1.connected = true
    var s2 = PlayerSlot.new()
    s2.name = "Maya"; s2.connected = false
    var msg = Lobby.format_pause_message([s1, s2])
    assert_true("Maya" in msg)

func test_format_pause_message_handles_no_disconnected():
    var s1 = PlayerSlot.new()
    s1.name = "Host"; s1.connected = true
    var msg = Lobby.format_pause_message([s1])
    assert_true("paused" in msg.to_lower())
```

- [ ] **Step 2: Run, watch fail**

- [ ] **Step 3: Implement**

Add to `scripts/ui/lobby.gd`:
```gdscript
@onready var _pause_overlay: PanelContainer = $PauseOverlay if has_node("PauseOverlay") else null
@onready var _pause_label: Label = $PauseOverlay/VBox/PauseLabel if has_node("PauseOverlay/VBox/PauseLabel") else null

# In _on_state_changed, replace the empty body:
func _on_state_changed(new_state: int) -> void:
    if _pause_overlay != null:
        _pause_overlay.visible = should_show_pause_overlay(new_state)
        if _pause_label != null and _pause_overlay.visible:
            _pause_label.text = format_pause_message(session.players)

static func should_show_pause_overlay(state: int) -> bool:
    return state == NetSessionState.State.PAUSED

static func format_pause_message(players: Array) -> String:
    var disconnected: Array = []
    for p in players:
        if not p.connected:
            disconnected.append(p.name)
    if disconnected.is_empty():
        return "Session paused..."
    return "Paused — waiting for %s (30s)..." % ", ".join(disconnected)
```

- [ ] **Step 4: Update scene**

Add to `scenes/lobby.tscn` (as sibling of `VBoxContainer`, NOT inside it):
```
[node name="PauseOverlay" type="PanelContainer" parent="."]
visible = false
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -200.0
offset_top = -60.0
offset_right = 200.0
offset_bottom = 60.0

[node name="VBox" type="VBoxContainer" parent="PauseOverlay"]
layout_mode = 2

[node name="PauseLabel" type="Label" parent="PauseOverlay/VBox"]
layout_mode = 2
text = "Session paused..."
horizontal_alignment = 1
```

- [ ] **Step 5: Verify scene loads + tests pass**

Expected: 128/128 tests pass.

- [ ] **Step 6: Commit**

```
feat(client): Lobby pause overlay shown when session state is PAUSED

PanelContainer overlay made visible by _on_state_changed when the
session enters PAUSED. format_pause_message lists disconnected player
names. Real 30s countdown is driven by the production Timer; this UI
just shows the static pause text.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Phase 6: Configuration + manual playtest

### Task 9: project.godot main scene + scene-load smoke test

**Files:**
- Modify: `project.godot`

- [ ] **Step 1: Set main scene**

Edit `project.godot`. Find or create the `[application]` section. Set:
```
[application]

config/name="Risk Royal"
run/main_scene="res://scenes/main_menu.tscn"
config/features=PackedStringArray("4.6", "Forward Plus")
```

Merge sensibly with any existing `[application]` section (preserve `config/features` and `config/name` if already set).

- [ ] **Step 2: Verify the project boots into MainMenu**

```
godot --headless --path . --quit
```

Expected: no errors. Optionally run in a real window:
```
godot --path .
```
to confirm visually. Close the window.

- [ ] **Step 3: Run full test suite**

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
```

Expected: 128/128 still passing.

- [ ] **Step 4: Commit**

```
chore(client): set MainMenu as run/main_scene in project.godot

The project now boots into the Risk Royal main menu. Unit tests
remain at 128/128.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 10: CLI flag smoke test (headless launch)

Verify `--host-locally` and `--join-code=` actually work via the running engine. This is more of an integration verification than a unit test — uses real signaling server.

**Files:** No code changes; this is a verification step that produces evidence.

- [ ] **Step 1: Start the signaling server**

```powershell
Start-Process -FilePath "node" -ArgumentList "index.js" -WorkingDirectory "server" -NoNewWindow -RedirectStandardOutput "server.log" -RedirectStandardError "server.err"
Start-Sleep -Seconds 2
Get-Content "server.log" -Tail 3
```

Expected: `signaling server listening on :8080`.

- [ ] **Step 2: Launch a host instance with --host-locally and a 5-second timeout**

```powershell
$hostProc = Start-Process -FilePath "godot" -ArgumentList "--path", ".", "--", "--host-locally" -PassThru -RedirectStandardOutput "host.log" -NoNewWindow
Start-Sleep -Seconds 5
$hostProc | Stop-Process -Force
Get-Content "host.log" -Tail 20
```

Expected: log shows the engine loading MainMenu, NetSessionMain bootstrapping, NetSession transitioning to LOBBY after the server issues a code. Look for log line like `signaling server listening` (from server) plus Godot scene load logs.

- [ ] **Step 3: Stop signaling server + cleanup**

```powershell
Get-Process node -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item "server.log","server.err","host.log" -ErrorAction SilentlyContinue
```

- [ ] **Step 4: Document results in PLAYTEST_CHECKLIST.md**

Create `docs/PLAYTEST_CHECKLIST.md`:
```markdown
# Risk Royal Manual Playtest Checklist

Last run: <DATE>
Plan reference: docs/superpowers/specs/2026-05-10-networking-lobby-foundation-design.md §9.3

## CLI Smoke Tests

- [x] `--host-locally`: host instance reached LOBBY state on its own (Task 10)
- [ ] `--join-code=ABC234`: TODO — needs a host running first

## Spec §9.3 Scenarios

See Task 11.
```

- [ ] **Step 5: Commit**

```
docs(client): add playtest checklist with CLI smoke results

Initial entry: --host-locally flag verified through headless engine
launch with running signaling server.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 11: Spec §9.3 manual playtest checklist

The 11 scenarios from spec §9.3. These require running the game with a window, not headless. The implementer should attempt as many as feasible on this single machine; mark "needs network peer" for those requiring a second physical machine on a different network. Document results in `docs/PLAYTEST_CHECKLIST.md`.

**Files:** Modify `docs/PLAYTEST_CHECKLIST.md`.

- [ ] **Step 1: Start signaling server in a separate terminal**

```
cd server
node index.js
```

- [ ] **Step 2: Run scenarios 1, 3, 4, 5, 6, 7, 8, 9, 10 on this machine**

These scenarios all work with two Godot instances on the same machine. Open the project in Godot, click Run, then open it a second time in another Godot window. Or use:

```
godot --path . &
godot --path . &
```

(Two windows, both connecting to localhost:8080 signaling.)

For each scenario, run it and record pass/fail/notes.

Scenarios:
1. **Host + 1 join, same LAN** — host clicks Host, gets code; second instance clicks Join, enters code. Both should see each other's slots within 5s. **Pass criteria:** both lobbies show 2 player slots.
3. **8-player full lobby** — open 8 instances total, all join the same code. **Pass:** all 8 visible; host can use the kick method via debug (no UI in this plan); slots reorder cleanly when one leaves.
4. **Color collision** — two clients pick the same color within ~200ms (rapid clicking). **Pass:** one reverts; final state agrees across all peers.
5. **Ready toggle storm** — all clients spam the ready toggle for 5s. **Pass:** final state agrees; no stuck UI.
6. **Client drop mid-lobby** — kill one Godot instance via task manager. **Pass:** other clients see the pause overlay; slot removed on timeout (30s).
7. **Client reconnect** — kill, restart instance, rejoin with the same code (no reconnect-token UI in this plan; this scenario partially blocked — record as "partial, reconnect-token UX is Plan E").
8. **Host drop** — kill the host process. **Pass:** all clients show pause; return to main menu after 30s (`session_ended("host_lost")` fires).
9. **Match start handoff** — all ready, host clicks Start. **Pass:** all clients see PlaceholderMatch scene with the MatchStart payload displayed.
10. **Invalid code** — type a random unused code. **Pass:** "Code not found" error or similar; can retry.

- [ ] **Step 3: Skip scenarios 2 and 11 (different-network, strict-NAT)**

These require a second physical machine on a different network. Mark them as "deferred — requires real second device on different network/strict NAT."

- [ ] **Step 4: Record all results in PLAYTEST_CHECKLIST.md**

Update `docs/PLAYTEST_CHECKLIST.md` with each scenario's outcome. Be honest — failures are valuable data for the next plan.

- [ ] **Step 5: Commit**

```
docs(client): document spec section 9.3 manual playtest results

Manual run-through of the 11 lobby playtest scenarios. Single-machine
scenarios verified; multi-network scenarios (2, 11) deferred for a
later test pass with a second physical device.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 12: Tag the sub-project #1 milestone

After all 11 tasks done and the playtest is documented (even with some "deferred" entries):

- [ ] **Step 1: Run full test suite one last time**

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=tests/integration -gexit
```

Expected: 128/128 unit + 1/1 integration tests pass.

- [ ] **Step 2: Tag**

```
git tag lobby-ui-v0.1
git tag subproject-1-complete
```

The second tag marks the end of Sub-Project #1 (Networking & Lobby Foundation) per the original MVP decomposition.

- [ ] **Step 3: No commit needed**

Tags are local-only. Push with `--tags` when ready.

---

## Done

When all task checkboxes are checked, Plan D delivers:

1. Three Godot scenes (MainMenu, Lobby, PlaceholderMatch) with corresponding scripts.
2. CLI flags `--host-locally` and `--join-code=` working in headless launches.
3. Manual playtest documented in `docs/PLAYTEST_CHECKLIST.md`.
4. 128 unit tests + 1 integration test passing.
5. Sub-project #1 (Networking & Lobby Foundation) complete — a playable lobby that hosts/joins, configures players, and hands off to the next scene.

**Next step:** Brainstorm sub-project #2 (Match Loop & Economy Core) per the MVP decomposition. The `MatchStart` payload delivered by Plan D's PlaceholderMatch is the contract handoff point.
