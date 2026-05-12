# Risk Royal Manual Playtest Checklist

Last run: 2026-05-11
Plan reference: docs/superpowers/specs/2026-05-10-networking-lobby-foundation-design.md §9.3

## CLI Smoke Tests (Task 10)

- [~] `--host-locally`: PARTIAL. Headless Godot launched against a running
  signaling server boots the engine and reaches the `NetSessionMain` autoload
  `_ready()`, but the autoload errors at the line
  `multiplayer.multiplayer_peer = _transport.get_multiplayer_peer()` with
  `Supplied MultiplayerPeer must be connecting or connected` (Godot
  SceneMultiplayer::set_multiplayer_peer). Result: the signaling server only
  logs the `listening` event; no `host_issued` event is observed because the
  host process never gets far enough to call `host_locally()`.
  Evidence:
    - server.log: single `{"event":"listening","port":8080}` line.
    - host.log: Godot engine banner + D3D12 init + game_helper mcp register.
    - host.err: the SceneMultiplayer error with GDScript backtrace pointing
      at `res://scripts/net/net_session_main.gd:32`.
  Implication: the `--host-locally` CLI path (CliArgs.from_cmdline + MainMenu
  auto-host) could not be exercised end-to-end here. Needs follow-up: either
  defer the `multiplayer.multiplayer_peer = ...` assignment until the
  WebRTCMultiplayerPeer is in a CONNECTING state, or create the peer in
  CONNECTING mode at autoload time. Track as a Task 11 prerequisite.
- [ ] `--join-code=ABC234`: TODO - needs a host running first; deferred to Task 11.

## Spec §9.3 Scenarios (Task 11)

| #  | Scenario                                | Status   | Notes                                                            |
|----|-----------------------------------------|----------|------------------------------------------------------------------|
| 1  | Host + 1 join, same LAN                 | TODO     | Run in Task 11 after the NetSessionMain bootstrap fix.           |
| 2  | Host + 1 join, different networks       | DEFERRED | Requires second physical machine on different network.           |
| 3  | 8-player full lobby                     | TODO     | Run in Task 11.                                                  |
| 4  | Color collision                         | TODO     | Run in Task 11.                                                  |
| 5  | Ready toggle storm                      | TODO     | Run in Task 11.                                                  |
| 6  | Client drop mid-lobby                   | TODO     | Run in Task 11.                                                  |
| 7  | Client reconnect                        | PARTIAL  | No reconnect-token UI in Plan D; defer full test to a future plan. |
| 8  | Host drop                               | TODO     | Run in Task 11.                                                  |
| 9  | Match start handoff                     | TODO     | Run in Task 11.                                                  |
| 10 | Invalid code                            | TODO     | Run in Task 11.                                                  |
| 11 | Strict-NAT failure                      | DEFERRED | Requires real strict-NAT environment.                            |
