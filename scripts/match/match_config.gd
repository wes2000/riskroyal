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
	"res://scripts/events/test_event/test_event.tscn",
]

const QUICK_CLASH_EVENT_COUNT: int = 5

const RESOLUTION_STEP_DELAY_MS: int = 600

const EVENT_TIMEOUT_SEC: int = 120

# Small delay used to pace no-op phase transitions (HOUSE_REVEAL, BET_LOADOUT,
# BOUNTY_HEAT_UPDATE->SHOP, SHOP, HOUSE_TWIST) so HUD updates animate rather
# than blurring past in one frame.
const NO_OP_PHASE_DELAY_MS: int = 300

static func starting_chips_for_player_count(count: int) -> int:
	return STARTING_CHIPS_BY_PLAYER_COUNT.get(count, 500)
