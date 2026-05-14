extends GutTest

const MatchScene = preload("res://scripts/ui/match_scene.gd")

func test_event_bust_does_not_hide_widgets():
	# Alpha feel remediation Phase A Change 1: after decoupling event bust
	# from spectator mode, the apply_spectator_visibility helper is only
	# called from the drop path. When spectator_mode is false (the normal
	# state — which includes "this peer busted in the current event but is
	# still in the match"), play widgets must remain visible.
	var widgets = {
		"BetLoadoutOverlay": {"visible": true},
		"LoadoutOverlay": {"visible": true},
		"SpectatorOverlay": {"visible": false},
	}
	MatchScene.apply_spectator_visibility(widgets, false)
	assert_true(bool(widgets.BetLoadoutOverlay.visible),
		"play widgets stay visible when not in spectator mode")
	assert_true(bool(widgets.LoadoutOverlay.visible))
	assert_false(bool(widgets.SpectatorOverlay.visible),
		"SpectatorOverlay stays hidden when not in spectator mode")
