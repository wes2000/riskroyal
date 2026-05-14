# Parses Godot OS.get_cmdline_args() into a flag dictionary.
# Recognized flags:
#   --host-locally           : auto-host on MainMenu boot
#   --join-code=CODE         : auto-join with CODE on MainMenu boot
#   --practice-locally       : auto-fire Practice vs Bots on MainMenu boot
#   --practice-bots=N        : bot count for --practice-locally (default 3)
#   --practice-seed=N        : seed for --practice-locally (default 0 → time-based)
# Unknown args are ignored.
extends Object

static func parse(argv: Array) -> Dictionary:
	var result := {
		"host_locally": false,
		"join_code": "",
		"practice_locally": false,
		"practice_bots": 3,
		"practice_seed": 0,
	}
	for arg in argv:
		if typeof(arg) != TYPE_STRING:
			continue
		if arg == "--host-locally":
			result["host_locally"] = true
		elif arg.begins_with("--join-code="):
			result["join_code"] = arg.substr("--join-code=".length())
		elif arg == "--practice-locally":
			result["practice_locally"] = true
		elif arg.begins_with("--practice-bots="):
			result["practice_bots"] = int(arg.substr("--practice-bots=".length()))
		elif arg.begins_with("--practice-seed="):
			result["practice_seed"] = int(arg.substr("--practice-seed=".length()))
	return result

static func from_cmdline() -> Dictionary:
	return parse(OS.get_cmdline_args())
