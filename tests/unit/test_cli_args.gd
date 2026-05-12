extends GutTest

const CliArgs = preload("res://scripts/util/cli_args.gd")

func test_empty_argv_yields_no_flags():
	var r = CliArgs.parse([])
	assert_false(r.host_locally)
	assert_eq(r.join_code, "")

func test_host_locally_flag():
	var r = CliArgs.parse(["--host-locally"])
	assert_true(r.host_locally)

func test_join_code_flag():
	var r = CliArgs.parse(["--join-code=ABC234"])
	assert_eq(r.join_code, "ABC234")

func test_unknown_flags_ignored():
	var r = CliArgs.parse(["--unknown", "positional", "--some-other=value"])
	assert_false(r.host_locally)
	assert_eq(r.join_code, "")

func test_combined_flags():
	var r = CliArgs.parse(["--host-locally", "--join-code=XYZ789", "--unrelated"])
	assert_true(r.host_locally)
	assert_eq(r.join_code, "XYZ789")

func test_join_code_passes_raw_string():
	var r = CliArgs.parse(["--join-code=abc234"])
	assert_eq(r.join_code, "abc234")
