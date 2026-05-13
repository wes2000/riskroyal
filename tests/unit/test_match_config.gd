extends GutTest

const MatchConfig = preload("res://scripts/match/match_config.gd")

func test_starting_chips_per_player_count():
	assert_eq(MatchConfig.STARTING_CHIPS_BY_PLAYER_COUNT[2], 800)
	assert_eq(MatchConfig.STARTING_CHIPS_BY_PLAYER_COUNT[4], 700)
	assert_eq(MatchConfig.STARTING_CHIPS_BY_PLAYER_COUNT[6], 600)
	assert_eq(MatchConfig.STARTING_CHIPS_BY_PLAYER_COUNT[8], 500)

func test_ante_schedule():
	assert_eq(MatchConfig.ANTE_BY_EVENT_INDEX, [25, 25, 25, 50, 100])

func test_heat_max():
	assert_eq(MatchConfig.HEAT_MAX, 10)

func test_event_pool_contains_rocket_clash():
	assert_true(MatchConfig.EVENT_POOL.has("res://scenes/events/rocket_clash/rocket_clash_event.tscn"))
	# TestEvent stays in the codebase for unit tests (via _event_factory test
	# seam), but is no longer in the production pool.
	assert_false(MatchConfig.EVENT_POOL.has("res://scripts/events/test_event/test_event.tscn"))

func test_quick_clash_event_count():
	assert_eq(MatchConfig.QUICK_CLASH_EVENT_COUNT, 5)

func test_resolution_step_delay_ms():
	assert_eq(MatchConfig.RESOLUTION_STEP_DELAY_MS, 600)

func test_event_timeout_sec():
	assert_eq(MatchConfig.EVENT_TIMEOUT_SEC, 120)

func test_starting_chips_for_lookup_helper():
	assert_eq(MatchConfig.starting_chips_for_player_count(4), 700)
	assert_eq(MatchConfig.starting_chips_for_player_count(8), 500)
	# Falls back to 500 for unsupported counts (e.g. > 8 or < 2)
	assert_eq(MatchConfig.starting_chips_for_player_count(99), 500)
	assert_eq(MatchConfig.starting_chips_for_player_count(1), 500)
