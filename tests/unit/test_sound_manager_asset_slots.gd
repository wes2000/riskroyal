extends GutTest

const SoundManager = preload("res://scripts/audio/sound_manager.gd")

func test_expected_slot_filenames_lists_all_six_cues():
	var names = SoundManager.expected_slot_filenames()
	assert_eq(names.size(), 6)
	assert_true("bust.ogg" in names)
	assert_true("crown_win.ogg" in names)
	assert_true("match_end.ogg" in names)
	assert_true("button_press.ogg" in names)
	assert_true("twist_stinger.ogg" in names)
	assert_true("chip_transfer.ogg" in names)

func test_cue_name_for_filename_strips_ogg_extension():
	assert_eq(SoundManager.cue_name_for_filename("bust.ogg"), "bust")
	assert_eq(SoundManager.cue_name_for_filename("crown_win.ogg"), "crown_win")
	assert_eq(SoundManager.cue_name_for_filename("not_a_slot.ogg"), "",
		"filename that doesn't match a known slot returns empty")
