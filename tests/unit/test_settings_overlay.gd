extends GutTest

const SettingsOverlay = preload("res://scripts/ui/settings_overlay.gd")

const TEST_CFG_PATH := "user://test_settings.cfg"

func after_each() -> void:
	if FileAccess.file_exists(TEST_CFG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG_PATH))

func test_load_persisted_scale_returns_1_0_on_fresh_start():
	var s = SettingsOverlay.load_persisted_scale(TEST_CFG_PATH)
	assert_almost_eq(s, 1.0, 0.001, "default scale is 1.0x when cfg doesn't exist")

func test_persist_then_load_round_trips():
	SettingsOverlay.persist_scale(1.25, TEST_CFG_PATH)
	var s = SettingsOverlay.load_persisted_scale(TEST_CFG_PATH)
	assert_almost_eq(s, 1.25, 0.001, "persisted scale loads back correctly")

func test_valid_scales_are_the_three_documented_options():
	var scales = SettingsOverlay.valid_scales()
	assert_eq(scales.size(), 3)
	assert_true(1.0 in scales)
	assert_true(1.25 in scales)
	assert_true(1.5 in scales)
