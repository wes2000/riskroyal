extends GutTest

const TargetPicker = preload("res://scripts/ui/cash_out_card_drawer_target_picker.gd")

func test_format_peer_button_label():
	var lbl = TargetPicker.format_peer_button_label("P2", 450)
	assert_string_contains(lbl, "P2")
	assert_string_contains(lbl, "450")

func test_filter_eligible_targets_excludes_self_and_busted():
	var players: Array = [
		{"peer_id": 1, "name": "P1", "chips": 500, "is_active_this_event": true},
		{"peer_id": 2, "name": "P2", "chips": 450, "is_active_this_event": true},
		{"peer_id": 3, "name": "P3", "chips": 0, "is_active_this_event": false},
	]
	var out = TargetPicker.filter_eligible_targets(1, players)
	assert_eq(out.size(), 1, "self excluded; busted (is_active_this_event=false) excluded")
	assert_eq(int(out[0].peer_id), 2)
