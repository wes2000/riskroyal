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
