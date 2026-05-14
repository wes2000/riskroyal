extends GutTest

const StatusGrid = preload("res://scripts/ui/status_grid.gd")

# --- format_status: Rocket Clash ---

func test_format_status_rocket_clash_in():
	var s = StatusGrid.format_status("rocket_clash", {"busted": false, "cashed_out": false})
	assert_eq(s, "IN", "default Rocket Clash state is IN")

func test_format_status_rocket_clash_cashed():
	var s = StatusGrid.format_status("rocket_clash", {"busted": false, "cashed_out": true})
	assert_eq(s, "CASHED")

func test_format_status_rocket_clash_busted():
	var s = StatusGrid.format_status("rocket_clash", {"busted": true, "cashed_out": false})
	assert_eq(s, "BUSTED")

# --- format_status: Bomb Pot ---

func test_format_status_bomb_pot_in():
	var s = StatusGrid.format_status("bomb_pot", {"busted": false, "pulled_out": false})
	assert_eq(s, "IN")

func test_format_status_bomb_pot_pulled():
	var s = StatusGrid.format_status("bomb_pot", {"busted": false, "pulled_out": true})
	assert_eq(s, "PULLED")

func test_format_status_bomb_pot_busted():
	var s = StatusGrid.format_status("bomb_pot", {"busted": true, "pulled_out": false})
	assert_eq(s, "BUSTED")

# --- format_status: Card Cannon ---

func test_format_status_card_cannon_drawing():
	var s = StatusGrid.format_status("card_cannon", {"busted": false, "locked": false})
	assert_eq(s, "DRAWING")

func test_format_status_card_cannon_locked():
	var s = StatusGrid.format_status("card_cannon", {"busted": false, "locked": true})
	assert_eq(s, "LOCKED")

func test_format_status_card_cannon_busted():
	var s = StatusGrid.format_status("card_cannon", {"busted": true, "locked": false})
	assert_eq(s, "BUSTED")

# --- format_status: unknown event / empty fallback ---

func test_format_status_unknown_event_returns_empty():
	var s = StatusGrid.format_status("", {})
	assert_eq(s, "", "empty event_id yields empty status (renders nothing)")
