extends GutTest

func test_lobby_uses_match_scene_path():
	# Verify the scene path string in lobby.gd. This is a guard against
	# future regression to placeholder_match.tscn.
	var lobby_source = FileAccess.get_file_as_string("res://scripts/ui/lobby.gd")
	assert_true(lobby_source.contains("res://scenes/match_scene.tscn"))
	assert_false(lobby_source.contains("res://scenes/placeholder_match.tscn"))

func test_match_scene_file_exists():
	assert_true(ResourceLoader.exists("res://scenes/match_scene.tscn"))
