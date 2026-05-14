extends GutTest

const SpectatorOverlay = preload("res://scripts/ui/spectator_overlay.gd")

func _player(peer_id: int, name: String, crowns: int, chips: int) -> Dictionary:
	return {"peer_id": peer_id, "name": name, "crowns": crowns, "chips": chips}

func test_format_leaderboard_empty_returns_empty():
	var out = SpectatorOverlay.format_leaderboard([])
	assert_eq(out.size(), 0)

func test_format_leaderboard_single_player():
	var out = SpectatorOverlay.format_leaderboard([_player(1, "P1", 0, 500)])
	assert_eq(out.size(), 1)
	assert_eq(int(out[0].rank), 1)
	assert_eq(int(out[0].peer_id), 1)
	assert_eq(int(out[0].crowns), 0)
	assert_eq(int(out[0].chips), 500)

func test_format_leaderboard_sorts_by_crowns_then_chips():
	# P2 has more crowns -> rank 1
	# P3 and P1 tie on crowns; P3 has more chips -> rank 2
	# P1 -> rank 3
	var players: Array = [
		_player(1, "P1", 1, 400),
		_player(2, "P2", 2, 100),
		_player(3, "P3", 1, 600),
	]
	var out = SpectatorOverlay.format_leaderboard(players)
	assert_eq(out.size(), 3)
	assert_eq(int(out[0].peer_id), 2, "P2 (2 crowns) ranks first")
	assert_eq(int(out[0].rank), 1)
	assert_eq(int(out[1].peer_id), 3, "P3 (1 crown, 600 chips) ranks second by chip tiebreak")
	assert_eq(int(out[1].rank), 2)
	assert_eq(int(out[2].peer_id), 1, "P1 (1 crown, 400 chips) ranks third")
	assert_eq(int(out[2].rank), 3)
