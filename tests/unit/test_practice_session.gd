extends GutTest

const PracticeSession = preload("res://scripts/net/practice_session.gd")


func test_build_match_start_3_bots_yields_4_seats():
	var ms = PracticeSession.build_match_start(3, 42)
	assert_eq(ms.seats.size(), 4)


func test_build_match_start_host_seat_is_first():
	var ms = PracticeSession.build_match_start(3, 42)
	assert_true(ms.seats[0].is_host)
	assert_eq(ms.seats[0].peer_id, 1)
	assert_eq(ms.seats[0].name, "You")


func test_build_match_start_bot_peer_ids_start_at_1000():
	var ms = PracticeSession.build_match_start(3, 42)
	assert_eq(ms.seats[1].peer_id, 1000)
	assert_eq(ms.seats[2].peer_id, 1001)
	assert_eq(ms.seats[3].peer_id, 1002)


func test_build_match_start_bot_names():
	var ms = PracticeSession.build_match_start(3, 42)
	assert_eq(ms.seats[1].name, "Bot 1")
	assert_eq(ms.seats[2].name, "Bot 2")
	assert_eq(ms.seats[3].name, "Bot 3")


func test_build_match_start_uses_provided_seed():
	var ms = PracticeSession.build_match_start(2, 12345)
	assert_eq(ms.rng_seed, 12345)


func test_build_match_start_zero_seed_uses_time():
	var ms = PracticeSession.build_match_start(2, 0)
	assert_gt(ms.rng_seed, 0)


func test_build_match_start_host_peer_id_field():
	var ms = PracticeSession.build_match_start(2, 1)
	assert_eq(ms.host_peer_id, 1)


func test_build_match_start_1_bot_minimum():
	var ms = PracticeSession.build_match_start(1, 1)
	assert_eq(ms.seats.size(), 2)


func test_build_match_start_7_bots_maximum():
	var ms = PracticeSession.build_match_start(7, 1)
	assert_eq(ms.seats.size(), 8)


func test_build_match_start_mode_is_quick_clash():
	var ms = PracticeSession.build_match_start(3, 1)
	assert_eq(ms.mode, "quick_clash")


func test_build_match_start_bots_not_host():
	var ms = PracticeSession.build_match_start(3, 1)
	for i in range(1, ms.seats.size()):
		assert_false(ms.seats[i].is_host)


func test_build_match_start_seat_indices_sequential():
	var ms = PracticeSession.build_match_start(3, 1)
	for i in range(ms.seats.size()):
		assert_eq(ms.seats[i].seat_index, i)
