extends GutTest

const MatchScene = preload("res://scripts/ui/match_scene.gd")
const SettingsOverlay = preload("res://scripts/ui/settings_overlay.gd")

const TEST_CFG_PATH := "user://test_settings_wiring.cfg"

func after_each() -> void:
	if FileAccess.file_exists(TEST_CFG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG_PATH))

func test_apply_persisted_scale_on_start_uses_default_when_no_cfg():
	var s = MatchScene.read_initial_text_scale(TEST_CFG_PATH)
	assert_almost_eq(s, 1.0, 0.001)
