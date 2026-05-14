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

## Sub-project #6 Plan A additions

| # | Scenario | Pass criteria |
|---|----------|---------------|
| 16 | Double Bounty Round doubles payouts | Twist announced at start of event 2-5; bounty resolution awards 300 chips instead of 150 (Leader bounty) and proportionally for Heat bounties |
| 17 | No Insurance disables card | Player has Insurance in loadout; twist announced; submit_card_play("insurance") returns rejection toast "Insurance disabled this event"; Insurance modifier never set in event_modifiers |
| 18 | Leader Cursed reduces survivor reward | Chip leader identified at HOUSE_TWIST; after event, leader's chip_delta is 75% of what their wager × multiplier would normally produce; non-leaders unaffected |
| 19 | Power Surge deals bonus cards | Every active peer receives +1 random non-sabotage common card at HOUSE_TWIST; the announce broadcast _rpc_house_twist_announced carries params.cards_dealt {peer_id → card_id}; each client mirrors the card into MatchPlayer.hand |
| 20 | No-repeat event selection | Across a 5-event Quick Clash, no two consecutive events share the same event_id |
| 21 | No twist on event 1 | First event's HOUSE_REVEAL sees state.house_twist == {} (no twist banner shown) |

## Sub-project #6 Plan B additions

| # | Scenario | Pass criteria |
|---|----------|---------------|
| 22 | Lowest Chips Picks: picker UI on lowest-chips peer | At HOUSE_TWIST → EVENT_SELECTION, the lowest-chips player's screen shows EventPickerOverlay with 3 buttons (Rocket Clash / Bomb Pot / Card Cannon); other peers see "Waiting for P<n> to pick the next event..." |
| 23 | Lowest Chips Picks: pick propagates | Picker clicks one of the 3 buttons → all peers' state.current_event_id matches the picked path; EventPickerOverlay hides; MAIN_EVENT loads the chosen event |
| 24 | Lowest Chips Picks: 10s timeout fallback | Picker does nothing for 10 seconds → host picks uniformly from options + broadcasts _rpc_event_picker_resolved with reason="timeout"; toast or banner mentions the timeout |
| 25 | Sudden Death + Rocket Clash: cash_out_over_5x | Twist announced (state.house_twist.type == "sudden_death_jackpot"); after EVENT_SELECTION picks Rocket Clash, state.house_twist.params.condition == "cash_out_over_5x"; any survivor who cashes > 5.0× earns +1 crown_delta (stacks with regular Crown to 2 if they also win highest cash-out) |
| 26 | Sudden Death + Bomb Pot: pull_out_after_80_pct | Same flow → condition = "pull_out_after_80_pct"; pullers whose pull-out timestamp >= 80% of bomb-time earn +1 crown_delta |
| 27 | Sudden Death + Card Cannon: locked_at_perfect | Same flow → condition = "locked_at_perfect"; any survivor who locks exactly 21 earns +1 crown_delta |

## Sub-project #7 Plan B — visible-info polish

- [ ] **Scenario 28: StatusGrid populates correctly for each of the 3 events.** Run a Quick Clash. During Rocket Clash, verify the StatusGrid chips flip from IN to CASHED / BUSTED as players cash out or crash. During Bomb Pot, chips flip from IN to PULLED / BUSTED. During Card Cannon, chips flip from DRAWING to LOCKED / BUSTED.
- [ ] **Scenario 29: BetLoadoutOverlay shows countdown + per-peer readied checkmarks.** At BET_LOADOUT entry, verify the countdown label ticks `[15s]` → `[1s]`. As each peer hits Ready, verify their chip in the readied row flips to `✓ P2` (or whichever peer name).
- [ ] **Scenario 30: EventPickerOverlay countdown ticks down visibly.** Trigger a `lowest_chips_picks` house twist. Verify the picker peer sees the countdown label tick `[10s]` → `[1s]` during the pick window. Verify it hides when the picker chooses (or the timeout fallback fires).
- [ ] **Scenario 31: `crown_delta=2` renders prominently in resolution overlay.** Trigger a Sudden Death Jackpot house twist and have a survivor meet the condition (cash out >5x in Rocket Clash, pull out after 80% in Bomb Pot, lock at exactly 21 in Card Cannon). Verify the resolution overlay shows `P3 gets 👑👑 2 CROWNS (Sudden Death stack!)` for that survivor.
- [ ] **Scenario 32: Announcer fires on all 4 trigger types.** Across a single match, verify the top banner pops on: (a) HOUSE_TWIST announcement at end of event 1, (b) any player ejection during a main event, (c) the Crown award at the resolution step, (d) the match-end winner reveal. Each fade auto-dismisses after ~3 seconds.
- [ ] **Scenario 33: PainfulReveal animations appear on bust (RED) and crown (GOLD) moments only.** Verify the bust reveal uses red text+chip with a 2-second slide-in + dissolve. Verify the crown reveal uses gold text+chip with a 1.5-second pulse. Verify NEITHER fires on house twist nor match-end (those are Announcer-only).
- [ ] **Scenario 34: LoadoutOverlay drag-to-slot works end-to-end + Cash-Out Jammer target picker functional.** Drag a card from the hand row into LoadoutSlot0; verify the slot label updates and the host acknowledges via `_rpc_loadout_acknowledged`. During the rocket, select Cash-Out Jammer from the drawer; verify the target picker modal opens with peer-name+chips buttons; click a peer; verify the play succeeds (the target's cash-out is jammed).

## Sub-project #7 Plan C — feel + audio + a11y

- [ ] **Scenario 35: SFX cues fire on the right events.** Run a Quick Clash. Verify each of the 6 SFX plays at the right time: chip_transfer on chip-delta animations, bust on player ejection, crown_win at RESOLUTION when a Crown is awarded, match_end at MATCH_END, button_press on any UI button click, twist_stinger when the HOUSE_TWIST banner appears. With no user-supplied .ogg files, all cues should be the procedural synth versions (audible but utilitarian).
- [ ] **Scenario 36: Announcer slide-in + bounce + slide-out plays smoothly.** Trigger any Announcer event (bust, crown, twist, match end). Verify the banner slides DOWN from off-screen top with a subtle bounce, holds for ~2.5s, then slides UP off-screen while fading. Total ~3.1s per message.
- [ ] **Scenario 37: PainfulReveal bust animation (RED snap + shake).** Cause a peer to bust during a main event. Verify the bust reveal: scales from 0 to 1.2 over 0.15s, settles to 1.0 over 0.1s, shakes briefly (±5px), holds red 1.2s, fades 0.3s.
- [ ] **Scenario 38: PainfulReveal crown animation (GOLD sparkle + double-pulse).** Cause a Crown award at RESOLUTION. Verify the crown reveal: scales 0 to 1.0 + rotates -15° to +15° over 0.2s (sparkle entry), settles rotation, pulses 1.0 → 1.15 → 1.0 → 1.15 → 1.0 over 0.6s, fades 0.3s.
- [ ] **Scenario 39: crown_delta=2 stack animation.** Trigger a Sudden Death Jackpot twist + a survivor meeting the condition. Verify the resolution overlay row: first crown icon appears immediately, 0.3s pause, second crown icon slides in from below over 0.4s, then "(Sudden Death stack!)" suffix fades in over 0.3s.
- [ ] **Scenario 40: SpectatorOverlay shows on local bust + hides play widgets.** As the local player, deliberately bust during a main event. Verify: SpectatorOverlay appears on the right 40% of the screen showing a sorted leaderboard, play widgets (BetLoadoutOverlay, LoadoutOverlay, EventPickerOverlay, CashOutCardDrawer, target picker) become hidden, and the always-visible widgets (StatusGrid, Announcer, PainfulReveal) shrink to the left 60%. Spectator mode persists for the rest of the match.
- [ ] **Scenario 41: Color-blind icon cues visible alongside colors.** Verify Announcer bust messages show "✗ P2 EJECTED! -100 chips" (X-mark prefix). Verify crown messages show "👑 P3 WINS THE CROWN!" (crown prefix). Verify PainfulReveal bust reveals show "✗ P2 LOST $100 ↓" (X-mark prefix + down arrow suffix). The icons appear alongside the RED / GOLD modulate so color-blind players have shape cues too.
- [ ] **Scenario 42: Text-scale toggle persists across restarts.** Open Settings via the settings button in the top-right corner. Click "1.25x" — verify UI text scales up. Close + restart the game. Verify the 1.25x scale is still applied on the very first frame.
- [ ] **Scenario 43: Per-event spectator info updates in real time.** In spectator mode, verify the EventStatusLabel updates: during Rocket Clash shows "P3 riding @ 4.2x"; during Bomb Pot shows "P3 in, 5s to bomb"; during Card Cannon shows "P3 score: 17/21". The label refreshes as the watched player's state changes.
