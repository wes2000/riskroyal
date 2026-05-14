# Risk Royal Public Alpha Validation

Validation date: 2026-05-14  
Scope: Compare current Godot alpha against `docs/RiskRoyal_DesignDoc.md`, with emphasis on mechanics translation and intended game feel.

## Verdict

The alpha successfully implements the MVP skeleton of Risk Royal, but it does not yet fully deliver the intended "battle casino party game" feel.

What is working:

- A 5-event Quick Clash match loop exists.
- The 9-phase event structure is represented in code.
- The MVP event pool exists: Rocket Clash, Bomb Pot, Card Cannon.
- Chips, Crowns, Heat, wagers, shop offers, bounties, power cards, House Twists, status overlays, announcer hooks, and painful reveal hooks are present.
- The three implemented events all contain real push-your-luck decisions.

What is not yet working at the intended feel level:

- Busting currently pushes the local player into spectator mode for the rest of the match, which conflicts with the core "lose funny, stay involved, claw back" design.
- Bomb Pot and Card Cannon produce painful reveal payloads, but the resolution overlay only formats Rocket Clash's painful reveal shape.
- Heat is too flat: event winners generally gain +1 Heat regardless of how greedy or dramatic the play was.
- Bounties are mostly "target failed while I survived," not "I caused that failure," so the social attack fantasy is weaker than intended.
- Card Cannon is mechanically functional, but it currently lacks the face-card combat identity from the design doc.
- Debt, Reputation/HP, black market, Last Chance, and Royal Run are not present. That is acceptable for MVP, but it means the public alpha is a Quick Clash prototype rather than the full Risk Royal experience.

## Implemented Systems

### Match Structure

Implemented:

- `HOUSE_REVEAL`
- `ANTE`
- `EVENT_SELECTION`
- `BET_LOADOUT`
- `MAIN_EVENT`
- `RESOLUTION`
- `BOUNTY_HEAT_UPDATE`
- `SHOP`
- `HOUSE_TWIST`
- `MATCH_END`

The current config is a 5-event Quick Clash:

- `ANTE_BY_EVENT_INDEX = [25, 25, 25, 50, 100]`
- Event pool:
  - Rocket Clash
  - Bomb Pot
  - Card Cannon
- `QUICK_CLASH_EVENT_COUNT = 5`

Design fidelity:

- Strong MVP translation.
- Not the full 10-event structure from the design doc.
- No Last Chance or Final Table/Royal Run yet.

### Core Resources

Implemented:

- Chips
- Crowns
- Heat
- Power cards
- Bounties

Not implemented:

- Debt
- Reputation/HP
- Black-market offers
- Crown-target match mode
- Final Table resource conversion

Design fidelity:

- Good MVP resource foundation.
- Missing the comeback economy that was supposed to keep losing players emotionally alive.

## Major Design Fidelity Findings

### 1. Busting Becomes Match-Long Spectator Mode

Severity: High

The design repeatedly emphasizes that losing should be funny, painful, and public, but not a reason to become irrelevant. The code currently emits `local_player_spectator_mode_entered` whenever the local player busts during a resolution step. `MatchScene` then hides the core play widgets and explicitly says reversal is not supported for the rest of the match.

Why this hurts the intended game:

- One bad Rocket Clash can prevent the player from meaningfully playing later events.
- Comeback mechanics cannot matter if the UI removes the player's ability to participate.
- The table emotion shifts from "that was hilarious, get revenge next round" to "you are done playing."

Recommended fix:

- Treat event busts as event-local only.
- Spectator mode should be for disconnected players, eliminated optional modes, or players who are inactive for the current event only.
- Restore play widgets at the next `HOUSE_REVEAL` or `ANTE` if the player can participate.

### 2. Painful Reveals Are Rocket-Only In The Resolution UI

Severity: High

Rocket Clash has a formatted painful reveal showing the crash multiplier and cash-outs. Bomb Pot and Card Cannon both produce event-specific reveal payloads, but `ResolutionOverlay` only recognizes the Rocket Clash payload shape. Other events fall back to a generic "Painful reveal: P0 wins" style output.

Why this hurts the intended game:

- Bomb Pot should show bomb time, last safe pull, and missed share value.
- Card Cannon should show bust cards, locked scores, and near-21 regret.
- The "emotionally damage people, but in a fun way" pillar disappears for two of the three alpha events.

Recommended fix:

- Add `_format_painful_reveal_bomb_pot(payload)`.
- Add `_format_painful_reveal_card_cannon(payload)`.
- Include next-card or missed-value data where possible.

### 3. Heat Does Not Scale With Drama

Severity: Medium

The design says big wins and greedy plays should create Heat. Current event result logic generally gives the event winner +1 Heat, reduced to 0 by Heat Shield. A 1.2x Rocket Clash win and a 12x Rocket Clash win both have the same Heat impact.

Why this hurts the intended game:

- Players do not become table villains because of visibly greedy success.
- Bounties do not escalate strongly from dramatic plays.
- "Victory creates Heat" exists mechanically, but not emotionally.

Recommended fix:

- Rocket Clash Heat should scale by cash-out band.
- Bomb Pot Heat should scale by pull-out lateness or pot share.
- Card Cannon Heat should scale for 19-21 locks, especially perfect 21.
- Give high-Heat players survival bonuses so Heat feels dangerous and desirable.

### 4. Bounties Lack Attribution

Severity: Medium

Bounties resolve when the target busts and the claimant survived. That means all surviving non-target players can claim or split the bounty, even if no one meaningfully caused the bust.

Why this hurts the intended game:

- "I am coming for you" is less sharp.
- Sabotage and targeting are less connected to rewards.
- Bounty play feels more passive than social.

Recommended fix:

- Track the last player who applied a relevant sabotage to the target.
- Add bounty conditions beyond `bust`, such as:
  - beat target's cash-out
  - make target bust after your sabotage
  - deal the finishing hit
  - outlast target in a named event
- Split passive "public enemy" bounties separately from player-placed attack bounties.

### 5. Card Cannon Is Missing Its Combat Personality

Severity: Medium

Card Cannon currently works as an independent draw/lock/bust event with score-band payouts. It does not yet have the design doc's face-card battle effects, shared deck pressure, target firing, shields, steals, swaps, or cannon damage fantasy.

Why this hurts the intended game:

- It plays closer to a payout table than a battle casino event.
- Players have fewer reasons to yell at each other during the event.
- The mini-game variety is lower than intended.

Recommended fix:

- Add face-card effects.
- Add target selection for locked shots.
- Add visible cannon charge and firing results.
- Consider a shared deck or visible discard feed to create table-wide suspense.

## Event Validation

### Rocket Clash

Design intent:

- Rocket climbs.
- Cash out before crash.
- Higher cash-out means better reward.
- Crash means losing wager.
- Reveal missed potential.

Current implementation:

- Strongly implemented.
- Uses exponential multiplier growth.
- Uses hidden crash point with 5% instabust.
- Supports manual cash-out, Emergency Eject, Cash-Out Jammer, multiplier modifiers, insurance, leader curse, sudden death bonus, Heat Shield, painful reveal.

Fidelity:

- This is the closest event to the original fantasy.
- Main gap: no battle output/damage target layer yet.
- Heat should scale with cash-out height.

### Bomb Pot

Design intent:

- Pot grows.
- Players pull out before hidden bomb.
- Last safe greed should feel amazing.
- Anyone still in when it blows loses.

Current implementation:

- Shared Pot Drain exists.
- Hidden bomb time exists.
- Pull-out action exists.
- Last puller gets Crown and Heat.
- Sudden Death condition for late pull-out exists.

Fidelity:

- Strong mechanical translation.
- Needs better presentation and painful reveal formatting.
- Current inter-player sabotage hooks from the design are mostly absent.

### Card Cannon

Design intent:

- Draw, stop, or bust.
- Higher score means stronger battle output.
- Face cards trigger cannon/shield/steal/swap effects.
- It should feel like combat, not just blackjack.

Current implementation:

- Draw/lock/bust loop exists.
- Score bands produce payouts.
- Perfect 21 matters.
- Insurance and modifiers apply.

Fidelity:

- Functional, but currently the least "battle casino" of the MVP events.
- Needs target firing and card personality.

## Power Cards

Implemented 12-card MVP:

- Insurance
- Heat Shield
- Multiplier Booster
- Double or Nothing
- Late Cash
- Underdog Odds
- Heat Spike
- Wager Tax
- Place Bounty
- Copycat Bet
- Cash-Out Jammer
- Emergency Eject

Design fidelity:

- Good coverage of Defense, Greed, Sabotage, Social, Comeback.
- The best-feeling cards are likely Cash-Out Jammer, Emergency Eject, Place Bounty, Double or Nothing, and Copycat Bet because they create readable table drama.
- Some cards are primarily economic modifiers and may not be visible enough during play.

Recommended next step:

- Add stronger public feedback when cards are played.
- Tie card effects to event-specific drama, not just result math.

## House Twists

Implemented 6-twist MVP:

- Double Bounty
- No Insurance
- Leader Cursed
- Power Surge
- Lowest Chips Picks
- Sudden Death Jackpot

Design fidelity:

- Strong MVP translation.
- Lowest Chips Picks and Sudden Death Jackpot are especially aligned with the design.
- The twist layer helps the alpha feel more like a casino show.

Recommended next step:

- Make twist announcements more theatrical.
- Ensure each twist visibly changes how players behave in the next event.

## Automated Validation

Commands run:

```powershell
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/integration -gexit
```

Results:

- Unit command exited with code 0, but emitted Godot runtime errors.
- Integration command exited with code 0 and no visible output.

Notable unit-run errors:

- Duplicate `event_complete` signal connections in `MatchController._process_main_event`.
- RPC calls to self or unknown peers during some in-tree controller tests.
- A GUT loader static-init script error.
- Resource/RID leak warnings at exit.

Interpretation:

- The test suite is not clean enough to use as a confident public-alpha validation gate.
- Some errors may be test harness artifacts, but they still reduce confidence in multiplayer/state-machine reliability.

## Alpha Readiness Assessment

Ready to show as:

- A promising Quick Clash prototype.
- A systems alpha.
- A proof that Rocket/Bomb/Card can support the Risk Royal loop.

Not ready to claim as:

- The full design-doc Risk Royal experience.
- A validated battle casino party game with complete comeback fantasy.
- A polished public alpha without caveats.

## Recommended Priority Fixes

1. Fix match-long spectator mode after event bust.
2. Add Bomb Pot and Card Cannon painful reveal formatting.
3. Make Heat scale with greedy/dramatic success.
4. Clean up automated test runtime errors.
5. Add attribution-aware bounty conditions.
6. Upgrade Card Cannon with target firing and face-card effects.
7. Add at least one comeback path for broke players, even before full Debt exists.

## Bottom Line

The code translated the design document's MVP systems, but not all of the intended feeling yet.

The alpha has the bones: rotating events, wagers, Crowns, Heat, bounties, cards, twists, and public outcomes. Rocket Clash is especially on target. But the current build still needs a few high-impact changes before it consistently creates the intended Risk Royal table emotion: greed, regret, revenge, comeback pressure, and friends yelling because the next round still matters.

