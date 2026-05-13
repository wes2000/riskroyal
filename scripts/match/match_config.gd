# Match-level constants. See spec section 6.2.
extends Object

const STARTING_CHIPS_BY_PLAYER_COUNT: Dictionary = {
	2: 800,
	3: 700,
	4: 700,
	5: 600,
	6: 600,
	7: 500,
	8: 500,
}

const ANTE_BY_EVENT_INDEX: Array = [25, 25, 25, 50, 100]

const HEAT_MAX: int = 10

const EVENT_POOL: Array = [
	"res://scenes/events/rocket_clash/rocket_clash_event.tscn",
	"res://scenes/events/bomb_pot/bomb_pot_event.tscn",
	"res://scenes/events/card_cannon/card_cannon_event.tscn",
]

const QUICK_CLASH_EVENT_COUNT: int = 5

const RESOLUTION_STEP_DELAY_MS: int = 600

const EVENT_TIMEOUT_SEC: int = 120

const EVENT_PICKER_TIMEOUT_SEC: int = 10

# Small delay used to pace no-op phase transitions (HOUSE_REVEAL, BET_LOADOUT,
# BOUNTY_HEAT_UPDATE->SHOP, SHOP, HOUSE_TWIST) so HUD updates animate rather
# than blurring past in one frame.
const NO_OP_PHASE_DELAY_MS: int = 300

# BET_LOADOUT phase timeout. Sub-project #3 upgrades BET_LOADOUT from a
# no-op pass-through to a real phase with wager input.
const BET_LOADOUT_TIMEOUT_SEC: int = 15

# Rocket Clash: max extra wager = player.chips × this factor. 1.0 means
# a player can wager up to their full chip stack on top of the ante.
const ROCKET_CLASH_MAX_WAGER_FACTOR: float = 1.0

# Rocket Clash: multiplier(t) = exp(ROCKET_GROWTH_RATE × elapsed_sec).
# 0.06/sec gives 2x at ~12s, 5x at ~27s, 10x at ~38s. Tunable.
const ROCKET_GROWTH_RATE: float = 0.06

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

# Sub-project #5 (Bomb Pot + Card Cannon)
# Bomb Pot
const BOMB_POT_POT_GROWTH_PER_SEC: float = 50.0   # chips/sec total distributed
const BOMB_POT_MIN_DETONATION_SEC: float = 5.0
const BOMB_POT_MAX_DETONATION_SEC: float = 25.0
const BOMB_POT_INSTABUST_PROB: float = 0.05       # 5% chance bomb fires at MIN
# Card Cannon
const CARD_CANNON_TARGET_SCORE: int = 21
const CARD_CANNON_PAYOUT_BAND_LOW: float = 0.5    # scores 1-10
const CARD_CANNON_PAYOUT_BAND_MEDIUM: float = 1.0 # scores 11-15
const CARD_CANNON_PAYOUT_BAND_STRONG: float = 1.5 # scores 16-18
const CARD_CANNON_PAYOUT_BAND_HEAVY: float = 2.0  # scores 19-20
const CARD_CANNON_PAYOUT_BAND_PERFECT: float = 3.0 # score 21

static func starting_chips_for_player_count(count: int) -> int:
	return STARTING_CHIPS_BY_PLAYER_COUNT.get(count, 500)
