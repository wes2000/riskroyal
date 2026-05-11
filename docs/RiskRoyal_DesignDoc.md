# Risk Royal - Game Design Document

Working title: Risk Royal  
Genre: Multiplayer party battle casino / push-your-luck arena  
Players: 2-8, strongest at 4-6  
Session length: 20-35 minutes  
Currency: Fictional in-game chips only  
Core fantasy: A chaotic casino game show where friends gamble, sabotage, bounty-hunt, and survive a rotating set of high-suspense events.

## 1. High Concept

Risk Royal is a multiplayer battle casino party game where every round is a different high-drama gambling event. Players are not sitting quietly at tables playing traditional casino games. They are contestants inside a loud, hostile, theatrical casino arena where the House keeps changing the rules.

The game is built around the emotional structure of crash-style rocket games:

- The reward visibly grows.
- Everyone knows greed is dangerous.
- Players must choose when to stop before disaster hits.
- The table watches every decision.
- Losing is public, funny, and painful.
- Winning makes you powerful, but also paints a target on your back.

Rocket Clash is the signature event, but it is only one part of Risk Royal. The larger game is about rotating events, bounties, power cards, Heat, chip economy, and social rivalry.

The intended table feeling is:

- "Cash out, cash out, cash out!"
- "No way you stay in."
- "I am putting a bounty on you."
- "The House just cursed the leader."
- "I should have left three seconds ago."
- "You absolute menace."

## 2. Design Pillars

### 2.1 Public Suspense

Every event should have a visible, shared source of tension. The rocket climbs, the bomb pot ticks, the elevator rises, the roulette ball slows, the vault alarm meter fills, or the jackpot token heats up. Players and spectators should understand the danger immediately.

The best Risk Royal moments come when everyone is watching the same threat and different players make different choices.

### 2.2 Greed Is Always Tempting

Stopping early should feel smart but slightly disappointing. Staying in should feel thrilling but obviously dangerous. The game should constantly ask:

"Do you want the safe reward now, or do you want the reward that would make everyone hate you?"

### 2.3 Losing Should Be Entertaining

Busts, crashes, explosions, alarms, and traps should not simply say "you lose." They should create a table moment. A player who crashes should see the missed value, get roasted by the announcer, maybe trigger a revenge effect, and still feel involved.

### 2.4 Victory Creates Heat

A player who wins big should not simply snowball in peace. Big wins create Heat. Heat increases bounty value, draws House attention, unlocks risky bonus opportunities, and encourages other players to attack.

### 2.5 Power Should Create Table Talk

Power cards should create threats, deals, bluffs, and revenge. The strongest cards are not just mathematically useful. They create sentences players want to say out loud:

- "I can save you if you do not target me."
- "I know what you picked."
- "I am forcing you up one more floor."
- "Your cash-out is delayed."
- "I am copying your bet."

### 2.6 Comebacks Require Risk

Behind players should stay alive emotionally, but the game should not hand them free wins. Comeback mechanics should feel like terrible, beautiful casino offers:

- Borrow chips, but gain Debt.
- Take a black-market card, but become cursed.
- Enter a risky side bet for a bonus Crown.
- Attack the leader for a bounty, but expose yourself.

### 2.7 Fictional Casino, Real Party

Risk Royal should use casino aesthetics, terminology, and tension, but it should be designed around fictional stakes and party-game fun. The game should avoid real-money gambling systems, cash-out economies, crypto hooks, loot-box monetization, or anything that turns the fantasy into actual gambling.

## 3. Target Experience

### 3.1 Audience

Risk Royal is for players who like:

- Party games with yelling and betrayal.
- Push-your-luck mechanics.
- Mario Party-style board-game chaos.
- Jackbox-style social spectacle.
- Short competitive matches.
- Risky comeback moments.
- Watching friends make terrible decisions.

### 3.2 Tone

The tone should be glamorous, dangerous, comedic, and theatrical. Think neon casino game show, not realistic gambling simulator.

The House is a character. It should feel like an untrustworthy host that wants drama more than fairness. The House can taunt players, trigger modifiers, raise bounties, and offer bad deals.

Example host lines:

- "A cautious exit. Respectable. Boring, but respectable."
- "The leader has been marked. Try to act surprised."
- "That was not greed. That was performance art."
- "Debt is just confidence with paperwork."
- "The House approves of this betrayal."

## 4. Core Match Structure

### 4.1 Match Overview

A standard match consists of 10 Events.

- Events 1-3: Opening Floor
- Events 4-8: High Roller Floor
- Event 9: Last Chance
- Event 10: Final Table

Players compete for Crowns. Chips are the main resource used to enter events, place bets, buy power cards, and apply pressure. Crowns determine the winner. This separation keeps players from hoarding chips and forces them to take meaningful risks.

### 4.2 Core Loop

Each event follows this structure:

1. House Reveal
2. Ante Up
3. Event Selection or Confirmation
4. Bet and Loadout Phase
5. Main Event
6. Resolution
7. Bounty and Heat Update
8. Shop / Black Market
9. House Twist

#### 4.2.1 House Reveal

The game shows:

- Current standings.
- Current chip counts.
- Crown totals.
- Heat levels.
- Active bounties.
- Current Debt.
- Next event or event selection method.
- Active House Twist.

The reveal should be short, punchy, and readable in under 10 seconds.

#### 4.2.2 Ante Up

All players pay an ante to enter the event. Antes scale by match phase.

Example:

- Opening Floor: 25 chips
- High Roller Floor: 50 chips
- Last Chance: 100 chips
- Final Table: custom rules

If a player cannot pay the ante, they may:

- Enter Debt.
- Sell a power card.
- Accept a House Deal.
- Skip the event and become a spectator saboteur with limited influence.

Skipping should be rare and generally undesirable. It is better to keep players involved through Debt or comeback mechanics.

#### 4.2.3 Event Selection

Events can be selected through multiple systems:

- Casino Wheel: a giant wheel chooses the next event.
- Lowest Picks: the lowest-ranked player chooses from 3 options.
- Winner Bans: the current leader bans one event but gains Heat.
- Chip Vote: players secretly spend chips to vote on the next event.
- Host's Choice: the House selects an event based on match state.

Recommended default:

- Most events are selected by Casino Wheel.
- Every third event gives the lowest Crown player a choice between 3 events.
- The leader may occasionally ban one event in exchange for Heat.

This keeps the game readable while giving trailing players a lever.

#### 4.2.4 Bet and Loadout Phase

Players choose:

- Optional wager amount.
- Target player, if the event supports attacks.
- Power cards to equip.
- Optional insurance or side bet.
- Whether to accept any House Deal.

This phase should be timed. Recommended duration: 20-30 seconds.

The UI should show each player as:

- Ready.
- Still choosing.
- Has placed a wager.
- Has active bounty.
- Has suspiciously many power cards.

Some choices are public, some are secret. The game should deliberately mix both:

- Public: ante paid, visible bounties, equipped defensive shields.
- Secret: exact wager, target, certain sabotage cards, vault depth.

#### 4.2.5 Main Event

The event plays out in real time. Events should usually last 20-75 seconds.

The ideal event length:

- Short enough that busted players are not bored.
- Long enough for suspense to build.
- Clear enough that spectators can follow.

#### 4.2.6 Resolution

Resolution should happen in a satisfying sequence:

1. Busts and failures.
2. Successful cash-outs or locked results.
3. Winnings.
4. Damage or battle effects.
5. Bounty claims.
6. Heat changes.
7. Crown awards.
8. Painful reveals.

"Painful reveals" are important. If a player cashed out early, show how much higher they could have gone. If they crashed, show the value they almost had. If someone sabotaged them, reveal the culprit at the most dramatic possible moment unless the card is meant to stay hidden.

#### 4.2.7 Shop / Black Market

After each event, players can buy power cards.

Shop options:

- 3 shared cards everyone can buy from until sold out.
- 1 personal offer per player.
- 1 black-market offer for players in Debt or behind on Crowns.

The shop should support quick decisions. Recommended duration: 25-35 seconds.

#### 4.2.8 House Twist

The House may apply a modifier for the next event. Twists should be short, readable, and dramatic.

Examples:

- No Insurance
- Double Bounty Round
- Leader Starts Cursed
- Sudden Death Jackpot
- Everyone Gets One Sabotage
- Lowest Chips Picks The Game
- Audience Favorite Gets A Shield

## 5. Player Resources

### 5.1 Chips

Chips are the main currency.

Uses:

- Pay antes.
- Place wagers.
- Buy power cards.
- Place bounties.
- Buy insurance.
- Pay off Debt.
- Activate certain event actions.

Chips should move constantly. Players should rarely feel totally comfortable.

Recommended starting chips:

- 2 players: 800 each
- 3-4 players: 700 each
- 5-6 players: 600 each
- 7-8 players: 500 each

### 5.2 Crowns

Crowns are the victory score. The player with the most Crowns after the Final Table wins.

Crowns are earned through bold public accomplishments.

Example Crown awards:

- Win an event: +1 Crown
- Complete bonus objective: +1 Crown
- Claim a major bounty: +1 Crown
- Win while under a curse: +1 Crown
- Survive Last Chance while in Debt: +1 Crown
- Win Final Table: +3 Crowns

Crowns should be hard enough to earn that every one feels meaningful.

### 5.3 Heat

Heat is a threat meter attached to each player. It represents how much attention they have drawn from the House and the table.

Gain Heat by:

- Winning an event.
- Cashing out at a high multiplier.
- Claiming bounties.
- Using aggressive power cards.
- Holding the chip lead.
- Winning consecutive events.

Lose Heat by:

- Busting.
- Paying a cooling fee.
- Taking damage.
- Being targeted by a bounty.
- Using certain defensive cards.

Heat effects:

- Increases bounty value on that player.
- Unlocks high-risk high-reward shop offers.
- Makes some House Twists target the player.
- May increase rewards if they survive.

Heat should be a double-edged status:

- Low Heat: safer, less targeted, fewer elite opportunities.
- High Heat: dangerous, valuable, powerful, vulnerable.

Suggested Heat scale:

- 0-2: Quiet
- 3-5: Noticed
- 6-8: Hot Seat
- 9-10: Public Enemy

### 5.4 Reputation / HP

There are two possible approaches:

#### Option A: No HP, Crowns Only

Players cannot be eliminated. They compete for Crowns and chips. This is better for casual party play because everyone stays involved.

#### Option B: Reputation HP

Players have Reputation, which acts like HP. If Reputation hits zero, they enter Debt Panic or become a Shadow Bettor.

Recommended default: Use Reputation but avoid hard elimination.

Reputation uses:

- Represents standing with the casino crowd.
- Damage from events lowers Reputation.
- Low Reputation makes you vulnerable to certain penalties.
- Zero Reputation triggers a comeback state instead of removal.

Suggested starting Reputation: 100.

At 0 Reputation:

- Player becomes "Disgraced."
- They cannot win normal event Crowns until they recover.
- They get access to dangerous black-market cards.
- They can restore Reputation by winning a comeback side objective.

This keeps the battle feeling without making players sit out.

### 5.5 Debt

Debt is a comeback resource and punishment state.

Players can enter Debt when:

- They cannot pay an ante.
- They accept a House Loan.
- They buy a black-market card they cannot afford.
- They trigger a failed double-or-nothing.

Debt effects:

- A percentage of future winnings is garnished.
- Certain cards become unavailable.
- Some black-market cards become available.
- The player becomes eligible for underdog bonuses.
- Too much Debt may trigger a Debt Duel.

Debt should feel tempting in the moment and painful later.

### 5.6 Power Cards

Power cards are single-use abilities. Players hold a limited hand and equip a smaller active loadout per event.

Recommended:

- Hand size: 5
- Active event slots: 2
- Passive slot: 1

This creates planning without overwhelming the event.

## 6. Battle Layer

The battle layer connects all mini-games. Without it, Risk Royal is only a playlist of gambling events. With it, each event affects rivalries, standings, and future choices.

### 6.1 Battle Outcomes

Events can produce:

- Chips
- Crowns
- Reputation damage
- Heat
- Bounty claims
- Power card draws
- Debt changes
- Temporary curses
- Shop discounts
- Event selection control

### 6.2 Targeting

Some events allow direct targeting. Others are indirect.

Direct targeting examples:

- Card Cannon: locked score fires at a chosen player.
- Rocket Clash: cash-out energy becomes an attack.
- Hot Potato Jackpot: pass the token to a chosen player.

Indirect targeting examples:

- Vault Crack: greedy players trigger shared punishment.
- Roulette Rush: players curse zones others are betting on.
- Shark Tank: players distract sharks toward rival chips.

The game should alternate between direct and indirect events to avoid constant pile-ons.

### 6.3 Damage

Damage should be easy to understand. If using Reputation:

- Small hit: 5-10 damage
- Medium hit: 15-25 damage
- Huge hit: 30-40 damage
- Catastrophic hit: 50+ damage, rare

Damage should usually be tied to risk. Safe cash-outs can chip away. Greedy successes can swing the table.

### 6.4 Bounties

Bounties are central to Risk Royal. They create social permission to attack the leader, punish annoying players, and generate short-term table villains.

Types of bounties:

- Leader Bounty: automatically placed on first place.
- Heat Bounty: placed on highest Heat player.
- Revenge Bounty: placed by a player who was targeted.
- House Bounty: triggered by a twist.
- Player Bounty: bought with chips.
- Event Bounty: tied to a specific action.

Example bounties:

- "Make Alex bust this event: +150 chips."
- "Beat Maya's cash-out multiplier: +1 Crown."
- "Hit the leader for 20+ damage: draw 2 cards."
- "Force Jordan into Debt: +1 Crown and +100 chips."
- "Survive longer than the hottest player: clear 2 Heat."

Bounty rules:

- Only one major bounty per player at a time.
- Minor bounties can stack, but rewards should be smaller.
- If multiple players contribute to a bounty, reward can split or go to the closer.
- A player may place a bounty on themselves through certain cards for high-risk rewards.

### 6.5 Heat and Bounty Interaction

Heat should automatically increase bounty value.

Example:

- Heat 0-2: no bonus
- Heat 3-5: bounty value +25%
- Heat 6-8: bounty value +50%
- Heat 9-10: bounty value +100%, player receives a survival bonus if they endure

This creates a delicious dilemma:

- Everyone wants to hit the hot player.
- The hot player can profit if they survive the attention.

### 6.6 The House

The House is the system-level antagonist and show host. It should:

- Announce events.
- Trigger twists.
- Offer loans and deals.
- Mark leaders.
- Punish stalling.
- Celebrate bold plays.
- Mock greedy failures.

The House should feel biased toward drama, not toward any specific player.

## 7. Power-Up System

### 7.1 Power Card Categories

#### Sabotage

Sabotage cards disrupt opponents.

Examples:

- Cash-Out Jammer: target player's cash-out input is delayed by 0.75 seconds.
- Door Jam: target cannot exit the Lucky Elevator for one floor.
- Bet Tax: steal 20% of target's winnings if they succeed.
- Signal Scramble: briefly hides a target's event UI details.
- Forced Reroll: target must reroll one locked choice.
- Heat Spike: target gains +2 Heat.
- Bad Luck Tag: target's next bust penalty is increased.

Design note: Sabotage should be annoying, but not feel like the entire game was taken away. Use short delays, visible tells, counters, and limited card slots.

#### Defense

Defense cards protect the player from risk or sabotage.

Examples:

- Insurance: recover 50% of wager on bust.
- Emergency Eject: automatically cash out at the last safe moment, but at reduced reward.
- Bodyguard: block the next sabotage card.
- Shield Chips: prevent chip loss up to a cap.
- Reputation Guard: reduce next incoming damage by 50%.
- Debt Buffer: prevent going into Debt once.
- Counterfeit Receipt: cancel a tax or steal effect.

#### Greed

Greed cards increase reward but raise risk.

Examples:

- Double or Nothing: double event reward, but bust penalty doubles.
- Multiplier Booster: increase payout multiplier by 25% if successful.
- Late Fee: staying in past a threshold adds bonus reward.
- All-In Spark: wager all chips for a Crown opportunity.
- Jackpot Siphon: steal from the event pot if you survive.
- Crown Gamble: risk 1 Crown to earn 2 Crowns on a top finish.

#### Social

Social cards manipulate information, bounties, or player relationships.

Examples:

- Place Bounty: add a bounty to a chosen player.
- Copycat Bet: copy another player's wager after seeing they are confident.
- Reveal Intent: reveal a target's chosen wager or vault depth.
- Swap Seats: swap event position with another player.
- Pact Token: both players gain a bonus if neither targets the other this event.
- Public Vote: table votes between two punishments or rewards.

#### Comeback

Comeback cards help trailing players but usually include risk.

Examples:

- Underdog Odds: if you are last, your next successful reward is boosted.
- Revenge Strike: hit the last player who damaged you.
- Debt Forgiveness: clear some Debt if you win the next event.
- Cursed Leader Tax: drain chips from the leader if they win again.
- Last Chance Ticket: enter a bonus Crown side objective.
- Black-Market Shield: strong defense, but gain Debt if it triggers.

### 7.2 Power Card Rarity

Suggested rarity levels:

- Common: simple, low-impact, cheap.
- Rare: meaningful swing, situational.
- Royal: high-impact, dramatic, expensive or risky.
- Black Market: powerful but cursed, usually available to trailing players or players in Debt.

### 7.3 Counterplay

Every frustrating card type should have counterplay:

- Sabotage can be blocked by defensive cards.
- High-value bounties are visible.
- Delays are short and telegraphed.
- Forced movement effects are limited to specific windows.
- Major steals are capped.
- Royal cards are rare and usually announced.

### 7.4 Card Timing Windows

Power cards should be tied to clear timing windows:

- Pre-Event: insurance, bounty, curse, wager modification.
- Early Event: reveal, peek, setup, light sabotage.
- Danger Window: emergency defense, cash-out interaction, forced stay.
- Resolution: steal, tax, block damage, claim bonus.
- Shop: discounts, trades, Debt conversion.

The UI should clearly show when cards can be used. A card that cannot currently be played should be dimmed with a simple timing icon.

## 8. House Twists

House Twists are temporary modifiers that keep the match from becoming predictable.

### 8.1 Twist Goals

Twists should:

- Change the next decision.
- Increase table talk.
- Create comeback chances.
- Punish runaway leaders.
- Make familiar events feel different.

Twists should not:

- Make results feel arbitrary.
- Require long explanations.
- Fully invalidate player skill.
- Stack into unreadable chaos.

### 8.2 Twist Examples

#### Double Bounty Round

All bounty rewards are doubled. New bounties cost 25% less.

Best used when:

- One player is clearly ahead.
- The table needs a target.

#### No Insurance

Insurance and emergency save cards cannot be used next event.

Best used when:

- The previous events were too safe.
- Players are hoarding defensive cards.

#### Leader Starts Cursed

The leading player begins the next event with a visible curse.

Possible curses:

- Higher ante.
- Reduced cash-out reward.
- +1 second delay before first card use.
- Extra Heat on success.

#### Everyone Gets One Sabotage

Each player receives a temporary weak sabotage card that expires after the event.

This should be messy but controlled. Use a weak card, not a round-ending effect.

#### Sudden Death Jackpot

A bonus Crown appears, but only for players who take a specific risk.

Example:

- Cash out above 5.0x.
- Stay in Bomb Pot past 80% danger.
- Take the elevator above Floor 8.

#### Lowest Chips Picks The Game

The poorest player chooses the next event from 3 options.

This is a clean comeback mechanic that gives agency without free resources.

#### Audience Favorite Gets A Shield

The player with the most recent dramatic failure receives a temporary shield.

This is more casual and comedic. It can be driven by in-game criteria, not actual audience voting.

#### Tax Season

The richest player pays chips into the next event pot.

Should be moderate, not devastating.

#### Debt Night

Loans are larger, but Debt penalties are harsher.

#### Royal Favor

The player with the fewest Crowns gets first shop pick and a discount.

#### Hot Streak

Consecutive event winners gain bonus rewards but also +2 Heat.

#### House Error

One random rule is bent in the players' favor. Example: first bust gets half refund, or all cash-outs round up.

## 9. Event Design Standards

Every mini-game should define:

- Core suspense object
- Player decision
- Risk curve
- Bust condition
- Reward formula
- Battle output
- Power card hooks
- Spectator readability
- Painful reveal
- Comeback angle

Events should vary by dominant skill:

- Timing
- Bluffing
- Pattern reading
- Risk evaluation
- Social targeting
- Resource management
- Reaction speed

No event should require advanced gambling knowledge. Traditional casino inspiration is fine, but the interaction should be obvious.

## 10. Mini-Game: Rocket Clash

### 10.1 Fantasy

Players launch rockets in a neon casino arena. The rocket climbs higher and higher, multiplying rewards. Each player can eject at any time. If they eject before the rocket fails, they bank reward and battle energy. If they wait too long, they explode and get nothing.

This is the signature Risk Royal event.

### 10.2 Core Suspense

The rocket's altitude/multiplier rises in real time while a hidden crash point approaches.

Players see:

- Current multiplier
- Their potential payout
- Other players still in
- Other players who cashed out
- Their active cards
- Heat and bounty indicators

### 10.3 Basic Rules

1. All players pay ante.
2. Players optionally place additional wager.
3. Rocket launches at 1.00x.
4. Multiplier increases over time.
5. Players may cash out/eject at any time.
6. If a player cashes out before crash, they earn wager x multiplier.
7. If still active when rocket crashes, they lose their wager and gain no battle energy.
8. Successful players convert multiplier into battle output.
9. The crash point is revealed.

### 10.4 Reward Formula

Simple version:

Reward = Wager x Cash-Out Multiplier

Battle Energy = floor(Cash-Out Multiplier x 10)

Damage option:

- 1.00x-1.49x: 5 damage
- 1.50x-2.49x: 10 damage
- 2.50x-4.99x: 20 damage
- 5.00x-9.99x: 35 damage
- 10.00x+: 50 damage and +1 Heat

### 10.5 Risk Curve

The crash distribution should produce frequent low and mid results, with rare dramatic highs.

Design goal:

- 1.00x-1.50x: common
- 1.51x-2.50x: common
- 2.51x-5.00x: exciting
- 5.01x-10.00x: rare
- 10.00x+: legendary

The player should never feel sure, but should learn the emotional rhythm.

### 10.6 Battle Variants

#### Attack Mode

Successful cash-out lets player attack a target. Higher multiplier deals more damage.

#### Shield Mode

Cash-out creates a shield for the next event. Higher multiplier creates stronger shield.

#### Bounty Mode

Players earn bonus rewards for outlasting or beating the target player's cash-out.

#### Team Rocket

Players can link rockets. If both survive to a threshold, both get bonus. If one crashes, both lose a portion.

### 10.7 Power Card Hooks

- Emergency Eject: auto cash-out at reduced reward before crash.
- Afterburner: multiplier climbs faster for the player, increasing reward and stress.
- Cash-Out Jammer: target's cash-out is delayed briefly.
- Black Box: if you crash, recover a small reward if the rocket would have gone much higher.
- Fuel Leak: target gains more multiplier but crash penalty increases.
- Copy Eject: cash out at the same multiplier as a chosen player if they exit first.
- Heat Shield: reduce Heat gained from a high cash-out.

### 10.8 Painful Reveal

After crash:

- Show the actual crash multiplier.
- Show each player's cash-out.
- Show "You left X chips on the table" for early cash-outs.
- Show "You were 0.12x away" for near crashes.
- Show biggest coward / biggest legend awards, lightly.

### 10.9 Crown Objectives

- Cash out above 5.0x and survive.
- Be the last surviving player to cash out.
- Beat the leader's cash-out.
- Cash out within 0.25x of the crash.

## 11. Mini-Game: Bomb Pot

### 11.1 Fantasy

A glowing prize pot sits at the center of the arena with a hidden bomb inside. The longer players keep their hands in the pot, the larger the prize grows. Players can grab shares and pull out, but anyone still grabbing when the bomb detonates loses their stake.

### 11.2 Core Suspense

The pot grows every second while the bomb timer is hidden. The room hears ticking, sees sparks, and watches who still has their hands in.

### 11.3 Basic Rules

1. All players ante into a shared pot.
2. The pot begins growing.
3. Players can "grab" to claim a share rate.
4. Players can pull out to lock their current share.
5. The hidden bomb explodes at an unknown time.
6. Players still grabbing when it explodes lose their wager and locked pending share.
7. Players who pulled out safely collect.

### 11.4 Share System

There are two possible versions.

#### Version A: Personal Meter

Each player fills their own share meter while active.

- Staying longer fills more.
- Pulling out locks the meter.
- Explosion wipes active meters.

#### Version B: Shared Pot Drain

The pot grows and active players drain from it.

- More active players means each gets a smaller share rate.
- As players leave, remaining players drain faster.
- This creates pressure to outwait others.

Recommended: Shared Pot Drain. It creates more table tension.

### 11.5 Risk Curve

The bomb has a hidden detonation window.

Example:

- Cannot explode during first 5 seconds.
- Low chance from 5-10 seconds.
- Rising chance from 10-20 seconds.
- Extreme danger after 20 seconds.

The UI can show danger through sparks and audio, but never exact odds.

### 11.6 Battle Outputs

Bomb Pot can output:

- Chips based on share.
- Reputation damage to players caught in explosion.
- Bonus Heat for the last safe player.
- Bounty reward for making a target bust.

### 11.7 Power Card Hooks

- Shove: force target's hand back into the pot for 1 second.
- Lockout: prevent target from grabbing for 1 second.
- Blast Suit: survive explosion but collect reduced reward.
- Fake Tick: play false danger audio to scare players.
- Sticky Fingers: increase share drain while active.
- Pot Siphon: steal a portion from the locked safest player.
- Fuse Peek: get a vague read: "cold", "warm", or "critical."

### 11.8 Painful Reveal

After explosion:

- Show how much each player locked.
- Show how much each busted player would have earned if they left 1 second earlier.
- Show "last safe grab" player.
- Show exact bomb timer.

### 11.9 Crown Objectives

- Be the final player to pull out before explosion.
- Lock at least 40% of pot.
- Make the bounty target bust.
- Survive with Blast Suit and still profit.

## 12. Mini-Game: Lucky Elevator

### 12.1 Fantasy

Players ride a golden elevator up a casino tower. Each floor increases rewards, but some floors contain traps. Players may exit at any floor. Staying on the elevator creates bigger rewards and stronger attacks, but the doors may open to disaster.

### 12.2 Core Suspense

The elevator climbs one floor at a time. The doors open, the floor result is revealed, and players decide whether to exit or continue.

### 12.3 Basic Rules

1. Players enter elevator.
2. Floor 1 is always safe.
3. Each new floor has a reward multiplier and possible hazard.
4. Players may exit after each floor reveal.
5. If a hazard triggers, players still inside suffer penalty or bust.
6. Players who exit lock current floor reward.

### 12.4 Floor Types

- Safe Floor: increases reward.
- Bonus Floor: grants chips or card draw.
- Trap Floor: damages or busts riders.
- Tax Floor: charges chips to continue.
- Split Floor: players choose left/right elevator route.
- Duel Floor: remaining players vote or challenge.
- Royal Floor: rare floor with Crown objective.

### 12.5 Reward Formula

Reward increases by floor.

Example:

- Floor 1: 1.1x
- Floor 2: 1.3x
- Floor 3: 1.6x
- Floor 4: 2.0x
- Floor 5: 2.6x
- Floor 6: 3.3x
- Floor 7: 4.2x
- Floor 8: 5.3x
- Floor 9: 6.7x
- Floor 10: 8.5x

Damage or attack power can scale similarly.

### 12.6 Trap Logic

Trap chance rises with floor count, but should be modified by route and twists.

Example:

- Floors 1-2: safe
- Floors 3-4: low hazard
- Floors 5-7: medium hazard
- Floors 8+: high hazard

Some traps do not fully bust players but create decisions:

- Lose chips or continue cursed.
- Take damage or exit now.
- Sacrifice a card to avoid bust.

### 12.7 Battle Outputs

- Exited players gain chips and floor energy.
- Floor energy can be converted to attack, shield, or card draw.
- Last rider gains Heat.
- Busting riders take Reputation damage.

### 12.8 Power Card Hooks

- Door Jam: target cannot exit on the next floor.
- Peek Floor: see the next floor category.
- Express Pass: skip a dangerous floor but reduce reward.
- Force Up: push a target one floor higher.
- Emergency Stairs: exit after a trap is revealed, but pay a fee.
- Elevator Music: scramble hazard audio cues.
- Lobby Swap: swap your floor reward with another player's.

### 12.9 Painful Reveal

After event:

- Show next floor for players who exited.
- Show "you escaped before Trap Floor" or "you left before Bonus Floor."
- Show highest floor reached.
- Show who got forced upward.

### 12.10 Crown Objectives

- Exit Floor 7 or higher.
- Be the only player to survive a trap floor.
- Force the leader to ride one extra floor and bust them.
- Reach Royal Floor.

## 13. Mini-Game: Roulette Rush

### 13.1 Fantasy

A giant physical roulette arena spins under the players. A glowing ball races around the rim. Players place bets on zones, colors, symbols, or moving segments, but they can move their bet while the ball slows. Moving late costs energy or chips.

This should feel more like a sports arena than a table game.

### 13.2 Core Suspense

The ball visibly slows while players scramble to commit, adjust, or sabotage zones.

### 13.3 Basic Rules

1. Wheel begins spinning.
2. Players place initial bets on zones.
3. Ball enters the wheel.
4. Players may move bets during the spin.
5. Moving gets more expensive as the ball slows.
6. Once lock-in hits, bets freeze.
7. Ball lands; matching bets win.
8. Power effects and curses resolve.

### 13.4 Bet Types

- Color: lower reward, safer.
- Zone: medium reward.
- Exact Tile: high reward.
- Moving Bonus: bet on a moving lit segment.
- Rival Bet: bet against another player's zone.
- Chaos Bet: random high-risk bet assigned by House.

### 13.5 Movement Cost

Players can reposition their bet marker.

Cost examples:

- Early spin: free
- Mid spin: 10 chips
- Late spin: 25 chips
- Final seconds: 50 chips or 1 Heat

This creates a great panic moment where players must decide whether correcting is worth it.

### 13.6 Battle Outputs

- Correct bets win chips.
- Exact hits can fire attacks.
- Failed high-risk bets may take damage.
- Players who stayed on original bet may gain bonus.
- Players who moved too much may gain Heat or pay extra.

### 13.7 Power Card Hooks

- Bump Ball: slightly alter ball path.
- Freeze Zone: prevent bets from entering/leaving a zone.
- Duplicate Bet: copy your marker to an adjacent zone.
- Curse Color: if that color wins, rewards are reduced or damage triggers.
- Magnet Tile: slightly improves a tile's chance, visible to all.
- Late Lock: keep your betting open 1 second longer.
- False Tell: create fake slowdown cues.

### 13.8 Fairness Note

Any physical manipulation must be readable and bounded. Players should feel that power cards influenced the result, not that the game lied.

If the game uses simulated physics, the final outcome should be determined or constrained in a way that avoids exploitative randomness and supports replay consistency.

### 13.9 Painful Reveal

After landing:

- Show original bet vs final moved bet.
- Show what the player would have won if they had stayed.
- Show late movement cost.
- Show all ball bumps and curses used.

### 13.10 Crown Objectives

- Hit an exact tile.
- Win without moving your bet.
- Win after moving in the final second.
- Correctly bet against the leader.

## 14. Mini-Game: Card Cannon

### 14.1 Fantasy

Players draw cards from a shared cannon deck. Each card increases their cannon charge. They can lock in at any time. Higher scores fire stronger shots, but drawing too high causes the cannon to overload and bust. Face cards trigger wild battle effects.

It has blackjack DNA, but should feel like a combat showpiece, not a casino table.

### 14.2 Core Suspense

Players draw one card at a time while their cannon charge grows. Everyone sees who is close to overloading.

### 14.3 Basic Rules

1. Each player starts at 0 charge.
2. Players draw cards in simultaneous rounds.
3. After each draw, players can lock or draw again.
4. Target score is 21 by default.
5. Going over 21 overloads and busts.
6. Locked scores fire at targets.
7. Higher locked score deals more damage and earns more chips.

### 14.4 Card Values

- Number cards: face value.
- Ace: 1 or 11, chosen automatically for best non-bust score.
- Jack: 10 and light sabotage.
- Queen: 10 and shield effect.
- King: 10 and bonus damage.
- Joker, optional: wild chaos card.

### 14.5 Face Card Effects

Face cards create the battle identity.

Examples:

- Jack: Jam a target's next power card.
- Queen: Gain 10 shield.
- King: Your cannon shot gains +5 damage.
- Ace: Flexible value and reduce Heat by 1 if locked safely.
- Joker: choose draw 2 / swap score / curse leader.

### 14.6 Score Bands

- 1-10: weak shot, safe payout.
- 11-15: medium shot.
- 16-18: strong shot.
- 19-20: heavy shot.
- 21: perfect shot, bonus Crown objective.
- Bust: cannon explodes, take damage.

### 14.7 Battle Outputs

Locked score can convert to:

- Direct damage.
- Shield.
- Chip reward.
- Card draw.
- Bounty claim progress.

Recommended default: locked score fires at a target for damage equal to score, with caps and modifiers.

### 14.8 Power Card Hooks

- Loaded Deck: next draw is guaranteed 1-6.
- Cut the Deck: force target to draw from a separate danger deck.
- Safety Valve: prevent bust once, but lock at 15.
- Ricochet: if your shot hits, splash 5 damage to another target.
- Mirror Shot: copy the leader's locked score if yours is lower.
- Misfire: target's next face card effect fails.
- Royal Reload: draw one extra card after locking, optional high risk.

### 14.9 Painful Reveal

After resolution:

- Show next card for players who locked early.
- Show bust card for overloaded players.
- Show who would have hit 21.
- Show face card chains.

### 14.10 Crown Objectives

- Lock exactly 21.
- Defeat a bounty target with cannon damage.
- Win the event without drawing a face card.
- Survive after using Royal Reload.

## 15. Mini-Game: Shark Tank

### 15.1 Fantasy

Players throw chip bundles onto floating platforms in a massive aquarium. The longer chips stay in the tank, the more they multiply. Sharks circle and lunge. Players can pull chips out, distract sharks, or push rival chips into danger.

This event should be visually readable, chaotic, and funny.

### 15.2 Core Suspense

Chips sit on moving safe platforms while shark attack patterns become more dangerous. Players decide when to pull out or interfere.

### 15.3 Basic Rules

1. Players toss chip bundles into the tank.
2. Bundles land on platforms.
3. Bundle value grows over time.
4. Sharks periodically lunge at platforms or lanes.
5. Players can pull bundles out to lock value.
6. Bundles hit by sharks are lost.
7. Players can use actions to move, distract, or defend.

### 15.4 Platform Types

- Stable Platform: slow, predictable, low multiplier.
- Fast Platform: moves quickly, higher growth.
- Cracked Platform: high growth but may sink.
- Golden Platform: rare bonus multiplier.
- Crowded Platform: multiple players' chips share space and can be shoved.

### 15.5 Shark Behavior

Shark attacks should be semi-readable:

- Sharks telegraph direction briefly.
- Higher-value bundles attract more attention.
- Chum effects can redirect sharks.
- Late event increases shark frequency.

The game should allow skillful observation without making the outcome fully controllable.

### 15.6 Battle Outputs

- Surviving bundles pay chips.
- High-value bundle survival grants Heat.
- Losing bundles can deal Reputation damage.
- Players can earn bounties by causing rival bundles to be eaten.

### 15.7 Power Card Hooks

- Chum Toss: attract a shark toward a chosen lane.
- Reinforced Case: protect one chip bundle from one bite.
- Harpoon Scare: delay the next shark lunge.
- Platform Shove: nudge a rival bundle.
- Decoy Bundle: create a fake target for sharks.
- Deep Dive: move your bundle to a high-growth dangerous platform.
- Feeding Frenzy: increase all multipliers and shark speed.

### 15.8 Painful Reveal

After event:

- Show bundle values at time of loss.
- Show how much a player could have won by pulling earlier.
- Show shark target influence.
- Award "most delicious chips" for biggest lost bundle.

### 15.9 Crown Objectives

- Pull out the highest-value surviving bundle.
- Save a bundle after a shark telegraph.
- Cause the leader's bundle to be eaten.
- Survive on a cracked platform for 10 seconds.

## 16. Mini-Game: Vault Crack

### 16.1 Fantasy

Players drill into a shared casino vault. Deeper layers contain bigger rewards, but if too many players drill too deep, the alarm triggers. Cautious players can profit when greedy players set off security.

Vault Crack is a bluffing and table-reading event.

### 16.2 Core Suspense

Players secretly choose how deep to drill. The group result determines whether the vault opens cleanly or the alarm triggers.

### 16.3 Basic Rules

1. Vault has several depth levels.
2. Each player secretly chooses a depth.
3. Deeper depth means higher potential reward.
4. Each depth adds alarm pressure.
5. If total alarm pressure exceeds threshold, alarm triggers.
6. If no alarm, players receive rewards based on depth.
7. If alarm triggers, greedy players are punished and cautious players may steal.

### 16.4 Depth Levels

Example:

- Level 1: Petty Cash, low reward, low pressure.
- Level 2: Silver Drawer, modest reward.
- Level 3: Gold Cage, strong reward.
- Level 4: Diamond Core, huge reward.
- Level 5: Royal Reserve, Crown objective, massive pressure.

### 16.5 Alarm Pressure

Each depth adds pressure:

- Level 1: +1
- Level 2: +2
- Level 3: +4
- Level 4: +7
- Level 5: +11

Alarm threshold scales by player count.

Example:

- 3 players: 10
- 4 players: 14
- 5 players: 18
- 6 players: 22

This makes group greed dangerous.

### 16.6 Resolution

If alarm does not trigger:

- Everyone gets depth reward.
- Deepest successful player gains Heat.
- Tied deepest players split bonus.

If alarm triggers:

- Players at high depth lose wager or take damage.
- Players at low depth may steal a portion.
- Players who predicted alarm may gain bonus.

### 16.7 Bluffing Layer

Before locking depth, players may emote, threaten, lie, or use social cards.

Possible UI features:

- "I am going shallow" preset line.
- "Someone is lying" callout.
- Public fake lock-in animation.
- Optional voice chat friendliness.

### 16.8 Battle Outputs

- Chips from vault rewards.
- Damage from alarms.
- Steals from greedy players.
- Crown for successful Royal Reserve.
- Bounties for exposing or punishing a target.

### 16.9 Power Card Hooks

- Depth Peek: see one target's chosen depth.
- Silent Drill: your depth adds less alarm pressure.
- Alarm Rig: secretly lower threshold.
- Security Badge: ignore alarm punishment once.
- False Blueprint: show fake depth to a target.
- Greed Magnet: if target chooses Level 4+, you steal from them.
- Safecracker: improve reward from shallow depth.

### 16.10 Painful Reveal

After event:

- Reveal all chosen depths one by one.
- Show total alarm pressure.
- Show threshold.
- Show who caused the alarm by going too deep.
- Show what would have happened if one player chose lower.

### 16.11 Crown Objectives

- Successfully drill Royal Reserve.
- Predict an alarm and profit.
- Be the only shallow player when alarm triggers.
- Catch the leader drilling deep.

## 17. Mini-Game: Hot Potato Jackpot

### 17.1 Fantasy

A glowing jackpot token passes between players. While holding it, a player's potential payout increases. If the hidden timer pops while they hold it, the token detonates and they pay out to others or take damage.

This event should be pure yelling.

### 17.2 Core Suspense

The token gets hotter, louder, and more valuable. Players want to hold it long enough to profit, then dump it onto someone else before it pops.

### 17.3 Basic Rules

1. Token starts with a random player.
2. Token value increases while held.
3. Holder may pass to another player.
4. Some passes can be blocked, reversed, or faked.
5. Hidden timer eventually pops.
6. Player holding token on pop busts.
7. Other players receive rewards based on involvement.

### 17.4 Passing Rules

Possible simple model:

- Pass has a short wind-up.
- Target can block if they have a block charge.
- Holder cannot pass back to the same player immediately unless using a card.
- Fakes consume time but can bait blocks.

### 17.5 Actions

Players can:

- Hold: build value.
- Pass: send token to a target.
- Fake Pass: bait a block.
- Block: reject incoming pass, cooldown-based.
- Reverse: send token back, card-based.
- Force Hold: prevent a player from passing briefly.

### 17.6 Battle Outputs

- Holder who busts loses chips or Reputation.
- Recent holders may earn partial jackpot if they survived.
- Player who passed it to the busting holder gets bonus.
- Longest safe hold gains Heat and chips.

### 17.7 Power Card Hooks

- Sticky Token: target cannot pass for 1 second.
- Reverse Pass: bounce token back.
- Fake Out: your next fake pass looks real.
- Quick Hands: reduce pass wind-up.
- Jackpot Leech: earn chips while another player holds.
- Panic Block: free block when token is critical.
- Hot Seat: force token to start on the leader.

### 17.8 Painful Reveal

After detonation:

- Show hidden timer.
- Show holder timeline.
- Show who held longest.
- Show who passed it to the victim.
- Show jackpot value one second before pop.

### 17.9 Crown Objectives

- Pass token to bounty target when it pops.
- Hold token for 5 total seconds and survive.
- Successfully reverse a critical token.
- Win without blocking.

## 18. Additional Mini-Game Concepts

### 18.1 Dice Drop Derby

Players drop giant dice down a pegboard. They can cash out on intermediate shelves or let dice fall deeper for bigger multipliers. Certain pegs belong to players and trigger battle effects.

Core decision: collect now or let the dice fall into more dangerous lanes.

### 18.2 Slot Storm

A giant slot machine spins reels that affect everyone. Players can lock individual reels for themselves, sabotage others' locks, or ride for a better combo. The longer they wait to lock, the more volatile the machine becomes.

Core decision: lock a mediocre combo or chase a jackpot.

### 18.3 Crown Ladder

Players climb a ladder with hidden break points. Each rung adds reward. Players can jump off and bank, or climb. Other players can shake the ladder at a cost.

Core decision: stop before the ladder breaks.

### 18.4 Mine Cart Money Run

Players ride mine carts through branching tracks. They choose track switches with different reward and hazard profiles. Sabotage can change upcoming switches.

Core decision: choose safe visible track or unknown rich tunnel.

### 18.5 Auction Ambush

Players bid chips for mystery crates. Some contain rewards, some contain traps, some contain power cards. Players can inspect, bluff, or force others to buy.

Core decision: read the table and avoid overpaying.

## 19. Match Phases in Detail

### 19.1 Opening Floor

Events 1-3.

Purpose:

- Teach the event rotation.
- Create early rivalries.
- Let players earn first cards.
- Avoid immediate crushing losses.

Rules:

- Low antes.
- Lower bust damage.
- Basic power cards only.
- House Twists are mild.
- Bounties are small.

Recommended twist examples:

- Power Surge
- Lowest Chips Gets Discount
- Small Leader Bounty

### 19.2 High Roller Floor

Events 4-8.

Purpose:

- Raise stakes.
- Let Heat and bounties matter.
- Introduce stronger cards.
- Create major swings.

Rules:

- Higher antes.
- Bigger bounties.
- Rare and Royal cards appear.
- House targets hot players more often.
- Event bonus objectives become more valuable.

Recommended twist examples:

- Double Bounty Round
- No Insurance
- Tax Season
- Hot Streak

### 19.3 Last Chance

Event 9.

Purpose:

- Give trailing players a risky route back.
- Give leaders a chance to defend.
- Set up the Final Table.

Rules:

- Lowest Crown players receive dangerous offers.
- Leader starts with a bounty.
- Bonus Crown objective is active.
- Debt can be cleared through success.

Example Last Chance offers:

- Risk 200 chips to compete for +2 Crowns.
- Enter event cursed; if you win, clear Debt.
- Challenge the leader; winner steals 1 Crown.

### 19.4 Final Table

Event 10.

Purpose:

- End with a spectacle.
- Convert the match's story into a final showdown.
- Give chips, cards, Heat, and Crowns all a role.

Recommended finale: The Royal Run.

## 20. Finale: The Royal Run

### 20.1 Overview

The Royal Run is a three-stage finale using rapid versions of existing events.

Stages:

1. Risk Trial
2. Bounty Trial
3. Crown Trial

Players carry limited resources between stages. There is no full shop, only quick choices.

### 20.2 Entry

All players enter, but standings matter.

Starting bonuses:

- Most Crowns: starts with shield or extra Crown lead.
- Most Chips: can buy one finale card.
- Highest Heat: has a bounty but earns survival bonus.
- Lowest Crowns: receives a risky comeback objective.

### 20.3 Stage 1: Risk Trial

A pure push-your-luck event, often Rocket Clash or Lucky Elevator.

Goal:

- Bank finale energy.
- Avoid early bust.

### 20.4 Stage 2: Bounty Trial

A direct battle event, often Card Cannon or Hot Potato Jackpot.

Goal:

- Resolve bounties.
- Let players attack the leader.

### 20.5 Stage 3: Crown Trial

A final high-stakes event with a bonus Crown objective.

Possible formats:

- Rocket Clash to highest safe cash-out.
- Vault Crack with public Crown pressure.
- Roulette Rush exact tile jackpot.

### 20.6 Winning

At the end:

- Add Crown rewards.
- Apply finale bounties.
- Resolve ties by chips, then Heat survival, then final event placement.

Final Table should award enough Crowns to matter, but not erase the whole match.

Recommended:

- Win Royal Run: +3 Crowns
- Second place: +1 Crown
- Complete finale objective: +1 Crown
- Claim finale bounty: +1 Crown

## 21. Economy and Balance

### 21.1 Economic Goals

The economy should:

- Encourage spending.
- Prevent early elimination.
- Make risk meaningful.
- Keep chip leaders from becoming untouchable.
- Make Debt tempting but scary.

### 21.2 Chip Flow

Chip sources:

- Event winnings.
- Bounties.
- House Deals.
- Shop sellbacks.
- Comeback rewards.

Chip sinks:

- Antes.
- Wagers.
- Power cards.
- Bounty placement.
- Insurance.
- Taxes.
- Debt payments.

### 21.3 Anti-Snowball Tools

- Heat makes leaders valuable targets.
- Tax Season drains richest player moderately.
- Bounties create group incentives.
- Crowns are separate from chips.
- Shop offers defensive tools to trailing players.
- Final Table gives measured comeback paths.

### 21.4 Anti-Kingmaking Tools

Because this is a social party game, some kingmaking is inevitable and even funny. But the systems should reduce spite-only outcomes.

Tools:

- Reward players for self-beneficial attacks.
- Bounties should pay the attacker, not just harm the target.
- Too much targeting can give the target survival bonuses.
- Comeback players need to pursue Crowns, not only revenge.

## 22. UI / UX Direction

### 22.1 Main Match Screen

The main screen should prioritize:

- Current event spectacle.
- Player status panels.
- Pot / multiplier / danger display.
- Active bounties.
- Heat indicators.
- Power card prompts.

Avoid clutter. The spectacle should be central.

### 22.2 Player Panels

Each player panel should show:

- Name / avatar.
- Chips.
- Crowns.
- Heat.
- Reputation.
- Debt marker.
- Bounty marker.
- Active defensive effect.

### 22.3 Event Readability

Every event needs a clear "danger language."

Examples:

- Rocket Clash: shaking, flame color, altitude audio.
- Bomb Pot: ticking speed, sparks, pot glow.
- Lucky Elevator: warning lights, floor number, door sounds.
- Roulette Rush: ball speed, lock-in countdown.
- Shark Tank: shark telegraph lines, water movement.
- Vault Crack: alarm pressure meter after reveal.
- Hot Potato Jackpot: token glow, sound pitch, holder outline.

### 22.4 Results Screen

The results screen should be quick but juicy.

Show:

- Winner of event.
- Biggest payout.
- Biggest loss.
- Bounty claims.
- Heat changes.
- Crown changes.
- Painful reveal.
- Next House Twist.

### 22.5 Spectator Involvement

Busted players should have micro-actions or at least emotional engagement.

Options:

- Cheer/boo effects with no gameplay impact.
- Bet small on remaining players.
- Trigger one weak "last laugh" sabotage if twist allows.
- Vote on cosmetic host callout.

## 23. Audio and Presentation

### 23.1 Announcer

The announcer is important. They should make events feel like a show and guide players through chaos.

Announcer responsibilities:

- Explain event objective in one sentence.
- Call out leader and bounties.
- React to high-risk decisions.
- Celebrate near misses.
- Mock catastrophic greed.
- Announce House Twists.

### 23.2 Sound Design

Sound should support suspense:

- Rising pitch as danger increases.
- Distinct cash-out sound.
- Heavy bust sound.
- Crowd swell for high multipliers.
- Card stingers for power plays.
- Dramatic silence before reveals.

### 23.3 Visual Style

Visual direction:

- Neon casino arena.
- Gold, red, teal, black, and white contrast.
- Big physical machines.
- Readable silhouettes.
- Exaggerated danger effects.
- The House as a theatrical presence.

Avoid making the game feel like a real gambling app. It should feel like a competitive arena game show.

## 24. Modes

### 24.1 Standard Match

10 events, 20-35 minutes. Main mode.

### 24.2 Quick Clash

5 events, 10-15 minutes. Good for casual play.

### 24.3 Long Night

15 events, 45-60 minutes. More bounties, more power cards, bigger swings.

### 24.4 Custom House Rules

Players can configure:

- Event pool.
- Starting chips.
- Crown target.
- Power card intensity.
- House Twist frequency.
- Real-time vs turn-based pacing.
- No sabotage mode.
- No Debt mode.
- Family-friendly host lines.

### 24.5 Tournament

Multiple matches where Crowns become season points.

## 25. Example Match Flow

### Event 1: Rocket Clash

Opening Floor. Low ante. Maya cashes out at 2.2x, Jordan crashes at 3.1x, Alex exits early at 1.4x. Maya gets first Crown and +2 Heat.

House callout: "Maya has discovered altitude and made it everyone else's problem."

### Event 2: Vault Crack

Lowest player chooses event. Jordan goes deep to recover, but two others also choose deep. Alarm triggers. Alex went shallow and steals from the greedy players.

Alex places a revenge bounty on Maya.

### Event 3: Bomb Pot

Maya stays in too long because of pride. Sam uses Fake Tick and scares Alex out early. Jordan gets last safe pull and recovers chips.

### Event 4: High Roller Begins

Antes rise. House Twist: Double Bounty Round. Maya is still ahead, so everyone has a reason to target her.

### Event 5: Card Cannon

Maya locks 20 and fires at Jordan. Jordan uses Mirror Shot, copies 20, and hits Maya back. Bounty claimed.

### Event 6: Shark Tank

Sam's huge bundle gets eaten because Alex used Chum Toss. Sam enters Debt and gains access to black-market offers.

### Event 7: Hot Potato Jackpot

Sam accepts a black-market Sticky Token. The token detonates on Maya. Table erupts. Sam clears some Debt.

### Event 8: Lucky Elevator

Alex leads in Crowns but gets Door Jammed on Floor 6 and busts on Floor 7. Heat shifts.

### Event 9: Last Chance

Jordan takes a dangerous +2 Crown offer in Rocket Clash. Cashes out at 5.4x, survives, jumps into contention.

### Event 10: Royal Run

Three rapid stages. Maya enters with Crowns, Alex with chips, Jordan with Heat, Sam with black-market cards. Final Crown Trial ends with Alex winning, but Jordan claims a bounty and ties. Tiebreaker goes to final event placement.

## 26. MVP Scope

### 26.1 Minimum Playable Version

For a first prototype, build:

- 4 player local or online lobby.
- Fictional chips.
- Crowns.
- Heat.
- Basic bounties.
- 3 mini-games:
  - Rocket Clash
  - Bomb Pot
  - Card Cannon
- Simple shop with 12 power cards.
- 6 House Twists.
- 5-event Quick Clash mode.

### 26.2 MVP Power Cards

Sabotage:

- Cash-Out Jammer
- Shove
- Misfire

Defense:

- Insurance
- Emergency Eject
- Bodyguard

Greed:

- Double or Nothing
- Multiplier Booster
- Jackpot Siphon

Social / Comeback:

- Place Bounty
- Copycat Bet
- Underdog Odds

### 26.3 MVP House Twists

- Double Bounty Round
- No Insurance
- Leader Starts Cursed
- Power Surge
- Lowest Chips Picks The Game
- Sudden Death Jackpot

### 26.4 MVP Success Criteria

The prototype is working if:

- Players understand each event within one round.
- Players yell during Rocket Clash.
- Players blame each other after power cards.
- The leader changes at least once per match.
- A trailing player still has hope before the finale.
- The results screen creates laughter or regret.

## 27. Future Expansion

### 27.1 More Events

Add:

- Lucky Elevator
- Roulette Rush
- Shark Tank
- Vault Crack
- Hot Potato Jackpot
- Dice Drop Derby
- Slot Storm

### 27.2 Character Abilities

Contestants could have light passive traits:

- The Banker: better Debt terms.
- The Daredevil: bonus above high multipliers.
- The Fixer: cheaper sabotage.
- The Bodyguard: stronger defense cards.
- The Showoff: gains rewards from Heat.

Keep abilities simple to preserve party readability.

### 27.3 Casino Arenas

Different arenas can change event pools and twist style:

- Neon Launchpad: Rocket-heavy, high multipliers.
- Sunken Casino: Shark Tank and treasure events.
- Royal Tower: Elevator and vault events.
- Back Alley House: black-market cards and Debt.
- Cosmic Casino: extreme twists and weird physics.

### 27.4 Seasonal Modifiers

Cosmetic and ruleset events:

- Double Crown Weekend, fictional only.
- Host Takeover.
- All Rocket Night.
- No Sabotage Challenge.
- Debt Spiral Mode.

## 28. Open Design Questions

- Should Reputation/HP be included in the default mode, or should Crowns and chips carry the entire match?
- How mean should sabotage be before casual players feel robbed?
- Should event outcomes be fully random, server-seeded, or partly skill-influenced?
- Should players choose targets before or after cash-out in Rocket Clash?
- Should black-market cards be exclusive to trailing players?
- How often should House Twists appear?
- Should the finale always be Royal Run, or should it rotate?
- How much information should players get about probabilities?

## 29. Recommended Direction

The strongest version of Risk Royal is:

A fictional-currency party battle casino where players compete for Crowns across rotating push-your-luck events. Every event creates a public suspense object, every big win creates Heat, every leader becomes a bounty target, and every player gets tools to betray, defend, gamble, or claw back through risky deals.

The game should not try to be a realistic casino. It should be a casino colosseum. The best moments should feel like a group of friends watching one person make a terrible decision in slow motion, then immediately using that decision as a weapon in the next round.

Rocket Clash should be the flagship event because it expresses the whole identity in its simplest form:

- Reward rises.
- Danger is hidden.
- Everyone watches.
- You choose when to stop.
- Greed writes the story.

Everything else in Risk Royal should remix that emotional arc.

