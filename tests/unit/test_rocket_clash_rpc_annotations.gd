extends GutTest

# Guard tests against the C1 regression: host's own @rpc receivers must
# use call_local so the host's _rpc_* methods execute when the host calls
# rpc(...). With call_remote, the host's own state never gets the local
# write and BET_LOADOUT hangs / cash-out is lost.

func test_match_controller_rpc_set_wager_uses_call_local():
	var src = FileAccess.get_file_as_string("res://scripts/match/match_controller.gd")
	# Find the _rpc_set_wager declaration line preceded by its @rpc annotation.
	var idx = src.find("func _rpc_set_wager")
	assert_true(idx > 0, "_rpc_set_wager must exist")
	# The 200 chars before should contain the @rpc annotation.
	var preamble = src.substr(max(0, idx - 200), 200)
	assert_true(preamble.contains("call_local"), "_rpc_set_wager must use call_local for host self-dispatch (C1 fix)")
	assert_false(preamble.contains("call_remote"), "_rpc_set_wager must NOT use call_remote")

func test_rocket_clash_rpc_cash_out_requested_uses_call_local():
	var src = FileAccess.get_file_as_string("res://scripts/events/rocket_clash/rocket_clash_event.gd")
	var idx = src.find("func _rpc_cash_out_requested")
	assert_true(idx > 0, "_rpc_cash_out_requested must exist")
	var preamble = src.substr(max(0, idx - 200), 200)
	assert_true(preamble.contains("call_local"), "_rpc_cash_out_requested must use call_local for host self-dispatch (C1 fix)")
	assert_false(preamble.contains("call_remote"), "_rpc_cash_out_requested must NOT use call_remote")
