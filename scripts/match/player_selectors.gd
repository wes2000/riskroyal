# Static-only chip-extremum helpers. Extracted from the 3 near-clone
# functions in BountyResolver + HouseTwistController. Follows the
# sub-project #4 collaborator pattern.
#
# direction: "max" or "min"; tie_break: if true, lower seat_index wins
# ties; if false, first-encountered traversal order wins (matches the
# legacy BountyResolver.find_chip_leader_peer_id behavior).
extends Object

static func find_chips_extremum(state, direction: String, tie_break: bool) -> int:
	if state.players.is_empty():
		return 0
	var best = state.players[0]
	for p in state.players:
		var wins: bool = false
		if direction == "max":
			wins = p.chips > best.chips
		else:
			wins = p.chips < best.chips
		if wins:
			best = p
		elif tie_break and p.chips == best.chips and p.seat_index < best.seat_index:
			best = p
	return best.peer_id
