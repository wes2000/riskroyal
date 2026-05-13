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

## Sub-project #4 Plan B additions

| # | Scenario | Pass criteria |
|---|----------|---------------|
| 6 | Cash-Out Jammer delays target's cash-out 750ms | Target tries to cash at 2.5x; their button press lags 750ms; resolved multiplier may differ from snapshot but stays within plus-or-minus 25% tolerance |
| 7 | Emergency Eject auto-triggers at 3.0x | Player loads Emergency Eject in BET_LOADOUT; rocket reaches 3.0x without manual cash-out; auto-cash fires at 3.0x; chip gain reflects 3.0x times wager |
| 8 | Place Bounty + bust target | Player A plays Place Bounty on Player B (150 chip cost); Player B busts in the rocket; bounty payout flows to whoever busted them (or unclaimed if B was sole busted) |

## Sub-project #5 additions

| # | Scenario | Pass criteria |
|---|----------|---------------|
| 9 | Bomb Pot: pull out before bomb | All players see consistent pot growth; player pulls out at ~8s; locked share visible in painful_reveal; bomb fires at hidden time; remaining players bust |
| 10 | Bomb Pot: last-puller wins Crown | 3 players; 2 pull out at 6s and 9s; 3rd at 12s; 3rd player receives crown_delta=1 + heat_delta=1 (or 0 with Heat Shield) |
| 11 | Bomb Pot: instabust at 5s | Run match repeatedly; ~5% of Bomb Pot rounds detonate at exactly the 5s window; nobody can pull out in time -> all bust |
| 12 | Card Cannon: lock at 21 wins triple payout | Player draws and locks at exactly 21; chip_delta = wager * 3.0; crown_delta=1 if highest |
| 13 | Card Cannon: bust at 22+ loses wager | Player draws past 21; chip_delta = -wager; no Crown |
| 14 | Card Cannon: Insurance halves bust | Player loads Insurance in BET_LOADOUT; busts in Card Cannon; chip_delta = -wager/2 |
| 15 | 3-event rotation produces variety | 5-event Quick Clash visits at least 2 of the 3 events (uniform random; ~60% probability of all 3) |
