extends GutTest

const BountyResolver = preload("res://scripts/match/bounty_resolver.gd")
const Bounty = preload("res://scripts/match/bounty.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")
const EventResult = preload("res://scripts/events/event_result.gd")

func _new_state(player_count: int) -> RefCounted:
	var s = MatchState.new()
	for i in player_count:
		var p = MatchPlayer.new()
		p.peer_id = i + 1
		p.seat_index = i
		p.name = "P%d" % (i + 1)
		p.chips = 500
		s.players.append(p)
	return s

func _bust_entry() -> Dictionary:
	return {"chip_delta": -100, "crown_delta": 0, "heat_delta": 0, "bust": true, "cash_out_at": 0.0}

func _surv_entry(cash: float) -> Dictionary:
	return {"chip_delta": 100, "crown_delta": 0, "heat_delta": 0, "bust": false, "cash_out_at": cash}

# P1 places a personal bounty on P3. P3 busts. P1 + P2 survive.
# Only P1 (placer) should claim, not P2.
func test_personal_bounty_pays_placer_only():
	var s = _new_state(3)
	var b = Bounty.new()
	b.origin = "placed"; b.target = 3; b.condition = "bust"
	b.reward_chips = 200
	b.claim_mode = "placer"
	b.placed_by = 1
	s.bounties = [b]
	var r = EventResult.new()
	r.event_id = "rocket_clash"
	r.per_player[1] = _surv_entry(2.0)
	r.per_player[2] = _surv_entry(1.5)
	r.per_player[3] = _bust_entry()
	var awards = BountyResolver.resolve(s, r)
	assert_eq(awards.size(), 1, "exactly one award for placer claim_mode")
	assert_eq(int(awards[0].claimant_peer_id), 1, "placer P1 receives the bounty")
	assert_eq(int(awards[0].reward_chips), 200, "full reward, no split")
	assert_eq(s.players[0].chips, 700, "P1 chips updated (500 + 200)")
	assert_eq(s.players[1].chips, 500, "P2 chips unchanged — not a public bounty")

# P1 places personal bounty on P3. Both P1 and P3 bust.
# Placer didn't survive, no claim, no payout.
func test_personal_bounty_no_award_if_placer_busted():
	var s = _new_state(3)
	var b = Bounty.new()
	b.origin = "placed"; b.target = 3; b.condition = "bust"
	b.reward_chips = 200
	b.claim_mode = "placer"
	b.placed_by = 1
	s.bounties = [b]
	var r = EventResult.new()
	r.event_id = "rocket_clash"
	r.per_player[1] = _bust_entry()
	r.per_player[2] = _surv_entry(1.5)
	r.per_player[3] = _bust_entry()
	var awards = BountyResolver.resolve(s, r)
	assert_eq(awards.size(), 1, "one award entry (unclaimed)")
	assert_eq(int(awards[0].claimant_peer_id), 0, "unclaimed when placer busted")
	assert_eq(int(awards[0].reward_chips), 0)
	assert_eq(s.players[1].chips, 500, "P2 chips unchanged — not eligible for personal")

# Default claim_mode=survivors still splits across survivors (legacy behavior).
func test_survivors_claim_mode_unchanged_default():
	var s = _new_state(3)
	var b = Bounty.new()
	b.origin = "leader"; b.target = 3; b.condition = "bust"
	b.reward_chips = 200
	# claim_mode = "survivors" by default
	s.bounties = [b]
	var r = EventResult.new()
	r.event_id = "rocket_clash"
	r.per_player[1] = _surv_entry(2.0)
	r.per_player[2] = _surv_entry(1.5)
	r.per_player[3] = _bust_entry()
	var awards = BountyResolver.resolve(s, r)
	assert_eq(awards.size(), 2, "two survivors split the bounty")
	var total = 0
	for a in awards:
		total += int(a.reward_chips)
	assert_eq(total, 200, "split sums to full reward (no chips lost)")

# Saboteur claim_mode: bust_after_sabotage condition + failure_caused_by routes
# the full reward to the saboteur.
func test_saboteur_claim_mode_routes_to_failure_cause():
	var s = _new_state(3)
	var b = Bounty.new()
	b.origin = "placed"; b.target = 3; b.condition = "bust_after_sabotage"
	b.reward_chips = 200
	b.claim_mode = "saboteur"
	b.placed_by = 0
	s.bounties = [b]
	var r = EventResult.new()
	r.event_id = "rocket_clash"
	r.per_player[1] = _surv_entry(2.0)
	r.per_player[2] = _surv_entry(1.5)
	r.per_player[3] = _bust_entry()
	# Attribution: P2 sabotaged P3 into busting.
	r.per_player[3]["sabotaged_by"] = [2]
	r.per_player[3]["failure_caused_by"] = 2
	var awards = BountyResolver.resolve(s, r)
	assert_eq(awards.size(), 1)
	assert_eq(int(awards[0].claimant_peer_id), 2, "saboteur P2 receives reward")
	assert_eq(int(awards[0].reward_chips), 200)

# bust_after_sabotage condition: if target busted but no sabotage was recorded,
# the bounty is unclaimed.
func test_bust_after_sabotage_skips_when_no_sabotage_recorded():
	var s = _new_state(3)
	var b = Bounty.new()
	b.origin = "placed"; b.target = 3; b.condition = "bust_after_sabotage"
	b.reward_chips = 200
	b.claim_mode = "survivors"  # default split, but condition gates it
	s.bounties = [b]
	var r = EventResult.new()
	r.event_id = "rocket_clash"
	r.per_player[1] = _surv_entry(2.0)
	r.per_player[2] = _surv_entry(1.5)
	r.per_player[3] = _bust_entry()
	# No sabotaged_by/failure_caused_by recorded.
	var awards = BountyResolver.resolve(s, r)
	assert_eq(awards.size(), 1)
	assert_eq(int(awards[0].claimant_peer_id), 0, "unclaimed: bust without sabotage")
