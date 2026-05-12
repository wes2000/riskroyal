# Risk Royal Manual Playtest Checklist

Last run: 2026-05-11
Plan reference: docs/superpowers/specs/2026-05-10-networking-lobby-foundation-design.md §9.3

## CLI Smoke Tests (Task 10)

- [x] **Autoload bootstrap fix:** the SceneMultiplayer error
  `Supplied MultiplayerPeer must be connecting or connected` that fired on
  every Godot launch (from `multiplayer.multiplayer_peer = ...` in
  `_ready()`) was resolved by deferring that assignment into `_process()`
  with a `get_connection_status()` gate. Commit `c5224d7`. The error no
  longer appears in `host.err`; engine boots cleanly.
- [ ] `--host-locally`: harness can launch Godot headless but the process
  doesn't reach the MainMenu scene within reasonable wait windows when
  stdout/stderr are redirected via PowerShell `Start-Process -NoNewWindow`
  (only the engine banner is captured before the test timeout). The flag
  path itself (`CliArgs.from_cmdline()` → MainMenu `_ready` → `host_session`)
  is covered by unit tests (`test_cli_args.gd`, `test_main_menu_logic.gd`).
  End-to-end CLI flag verification deferred to a windowed manual run.
- [ ] `--join-code=ABC234`: same situation; verify alongside scenario 1 by
  launching one Godot instance with `--host-locally`, observing its code in
  the window, then launching a second with `--join-code=<that code>`.

## Spec §9.3 Scenarios (Task 11)

| #  | Scenario                                | Status   | Notes                                                            |
|----|-----------------------------------------|----------|------------------------------------------------------------------|
| 1  | Host + 1 join, same LAN                 | USER     | Run by launching two `godot --path .` windows on this machine; one clicks Host, second clicks Join with that code. |
| 2  | Host + 1 join, different networks       | DEFERRED | Requires second physical machine on different network.           |
| 3  | 8-player full lobby                     | USER     | Run by user with two `godot --path .` windows (or 8 windows for scenario 3). |
| 4  | Color collision                         | USER     | Run by user with two `godot --path .` windows (or 8 windows for scenario 3). |
| 5  | Ready toggle storm                      | USER     | Run by user with two `godot --path .` windows (or 8 windows for scenario 3). |
| 6  | Client drop mid-lobby                   | USER     | Run by user with two `godot --path .` windows (or 8 windows for scenario 3). |
| 7  | Client reconnect                        | PARTIAL  | No reconnect-token UI in Plan D; defer full test to a future plan. |
| 8  | Host drop                               | USER     | Run by user with two `godot --path .` windows (or 8 windows for scenario 3). |
| 9  | Match start handoff                     | USER     | Run by user with two `godot --path .` windows (or 8 windows for scenario 3). |
| 10 | Invalid code                            | USER     | Run by user with two `godot --path .` windows (or 8 windows for scenario 3). |
| 11 | Strict-NAT failure                      | DEFERRED | Requires real strict-NAT environment.                            |

## Sub-project #2: Match Loop & Economy Core (Plan B)

Plan reference: docs/superpowers/specs/2026-05-11-match-loop-and-economy-design.md §9.6
Implemented: 2026-05-11

Run by launching two `godot --path .` windows on this machine; click Host in one, Join with the host's code in the other.

| # | Scenario | Status | Notes |
|---|----------|--------|-------|
| 1 | Match runs all 5 events without errors | USER | Both peers should see PhaseIndicator advance through 5 × HOUSE_REVEAL → ... → HOUSE_TWIST cycle. |
| 2 | Player panels update on resource changes | USER | After each event, chip / Crown / Heat values update on both peers. |
| 3 | Phase indicator advances correctly | USER | Text reads "Event N/5: PHASE_NAME" throughout. |
| 4 | Resolution overlay shows substeps with readable pacing | USER | 5 substep lines appear with ~600ms between them. |
| 5 | Ante skip works when a player has 0 chips | USER | Set a player's chips to 0 via debug; ANTE phase marks them inactive; event continues with remaining players. |
| 6 | Match ends correctly; rankings displayed | USER | After event 5, MatchEndOverlay shows ranked players. |
| 7 | Back-to-Lobby returns all peers to Lobby scene | USER | Host clicks Back; both peers' scenes change to Lobby. |
| 8 | Quit returns the quitting peer to MainMenu | USER | Anyone clicks Quit; just that peer goes back to MainMenu; other peer stays in match (or shows host-disconnected message if host quit). |

## Sub-project #3: Rocket Clash (Plan A)

Plan reference: docs/superpowers/specs/2026-05-12-rocket-clash-event-design.md §9.6
Implemented: 2026-05-12

Run by launching two `godot --path .` windows on this machine.

| # | Scenario | Status | Notes |
|---|----------|--------|-------|
| 1 | Wager + rocket end-to-end | USER | Two windows; both wager; both cash out at different multipliers; both see consistent rankings. |
| 2 | Bust event | USER | Both hold past crash; both lose wager; no Crown awarded that event. |
| 3 | Solo survivor | USER | One cashes early, one busts; survivor gets Crown. |
| 4 | Wager defaults to 0 on timeout | USER | One player ignores BET_LOADOUT; verify their event still runs with wager=0. |
| 5 | Cash-out near crash | USER | Cash out within 0.1x of expected crash; verify host accepts within tolerance band. |
| 6 | Five-event match with mixed wagers | USER | Full Quick Clash; chips and Heat update correctly across all 5 events; final rankings sensible. |
