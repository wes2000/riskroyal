# Parses Godot OS.get_cmdline_args() into a flag dictionary.
# Recognized flags:
#   --host-locally           : auto-host on MainMenu boot
#   --join-code=CODE         : auto-join with CODE on MainMenu boot
# Unknown args are ignored.
extends Object

static func parse(argv: Array) -> Dictionary:
	var result := {
		"host_locally": false,
		"join_code": "",
	}
	for arg in argv:
		if typeof(arg) != TYPE_STRING:
			continue
		if arg == "--host-locally":
			result["host_locally"] = true
		elif arg.begins_with("--join-code="):
			result["join_code"] = arg.substr("--join-code=".length())
	return result

static func from_cmdline() -> Dictionary:
	return parse(OS.get_cmdline_args())
