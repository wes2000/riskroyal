extends GutTest

const SoundManager = preload("res://scripts/audio/sound_manager.gd")
const MatchController = preload("res://scripts/match/match_controller.gd")
const FakeMultiplayerNode = preload("res://tests/fakes/fake_multiplayer_node.gd")

func test_signal_to_cue_name_maps_4_signals():
	assert_eq(SoundManager.signal_to_cue_name("player_busted"), "bust")
	assert_eq(SoundManager.signal_to_cue_name("crown_awarded"), "crown_win")
	assert_eq(SoundManager.signal_to_cue_name("house_twist_announced"), "twist_stinger")
	assert_eq(SoundManager.signal_to_cue_name("match_ended"), "match_end")
	assert_eq(SoundManager.signal_to_cue_name("unknown_signal"), "",
		"unmapped signal returns empty")

func test_bind_controller_subscribes_4_signals():
	var fake = FakeMultiplayerNode.new()
	var c = MatchController.new(true, fake)
	var sm = SoundManager.new()
	sm.bind_controller(c)
	assert_true(c.player_busted.is_connected(sm._on_player_busted_for_sfx),
		"player_busted is wired")
	assert_true(c.crown_awarded.is_connected(sm._on_crown_awarded_for_sfx),
		"crown_awarded is wired")
	assert_true(c.house_twist_announced.is_connected(sm._on_house_twist_for_sfx),
		"house_twist_announced is wired")
	assert_true(c.match_ended.is_connected(sm._on_match_ended_for_sfx),
		"match_ended is wired")
	sm.free()
