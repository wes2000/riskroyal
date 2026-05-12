extends GutTest

const PlayerPanel = preload("res://scripts/ui/player_panel.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func test_format_chip_text():
	assert_eq(PlayerPanel.format_chip_text(0), "0 chips")
	assert_eq(PlayerPanel.format_chip_text(1234), "1234 chips")

func test_format_crown_text():
	assert_eq(PlayerPanel.format_crown_text(0), "0 Crowns")
	assert_eq(PlayerPanel.format_crown_text(1), "1 Crown")
	assert_eq(PlayerPanel.format_crown_text(3), "3 Crowns")

func test_heat_band_quiet():
	assert_eq(PlayerPanel.heat_band(0), "Quiet")
	assert_eq(PlayerPanel.heat_band(2), "Quiet")

func test_heat_band_noticed():
	assert_eq(PlayerPanel.heat_band(3), "Noticed")
	assert_eq(PlayerPanel.heat_band(5), "Noticed")

func test_heat_band_hot_seat():
	assert_eq(PlayerPanel.heat_band(6), "Hot Seat")
	assert_eq(PlayerPanel.heat_band(8), "Hot Seat")

func test_heat_band_public_enemy():
	assert_eq(PlayerPanel.heat_band(9), "Public Enemy")
	assert_eq(PlayerPanel.heat_band(10), "Public Enemy")
