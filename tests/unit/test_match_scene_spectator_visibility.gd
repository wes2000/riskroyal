extends GutTest

const MatchScene = preload("res://scripts/ui/match_scene.gd")

func test_widgets_to_hide_on_spectator_lists_5_play_widgets():
	# Static lookup: the 5 widgets to hide when entering spectator mode.
	var names = MatchScene.widgets_to_hide_on_spectator()
	assert_eq(names.size(), 5)
	assert_true("BetLoadoutOverlay" in names)
	assert_true("LoadoutOverlay" in names)
	assert_true("EventPickerOverlay" in names)
	assert_true("CashOutCardDrawer" in names)
	assert_true("CashOutCardDrawerTargetPicker" in names)

func test_apply_spectator_visibility_marks_widgets_hidden():
	# Pure-helper version of the handler: takes a dict of widget refs
	# (each is a simple object with .visible) and the spectator-mode
	# flag, returns the same dict with .visible flipped.
	var widgets = {
		"BetLoadoutOverlay": {"visible": true},
		"LoadoutOverlay": {"visible": true},
		"SpectatorOverlay": {"visible": false},
	}
	MatchScene.apply_spectator_visibility(widgets, true)
	assert_false(bool(widgets.BetLoadoutOverlay.visible),
		"play widgets hidden")
	assert_false(bool(widgets.LoadoutOverlay.visible))
	assert_true(bool(widgets.SpectatorOverlay.visible),
		"SpectatorOverlay shown")
