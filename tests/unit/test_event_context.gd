extends GutTest

const EventContext = preload("res://scripts/events/event_context.gd")
const MatchPlayer = preload("res://scripts/match/match_player.gd")

func test_defaults():
	var c = EventContext.new()
	assert_eq(c.players.size(), 0)
	assert_eq(c.event_index, 0)
	assert_eq(c.rng_seed, 0)
	assert_eq(c.wagers, {})

func test_round_trip():
	var c = EventContext.new()
	var p = MatchPlayer.new()
	p.peer_id = 2; p.name = "Maya"
	c.players = [p]
	c.event_index = 3
	c.rng_seed = 0xCAFE
	c.wagers = {2: 50}
	var d = c.to_dict()
	var c2 = EventContext.from_dict(d)
	assert_eq(c2.event_index, 3)
	assert_eq(c2.rng_seed, 0xCAFE)
	assert_eq(c2.wagers, {2: 50})
	assert_eq(c2.players.size(), 1)
	assert_eq(c2.players[0].name, "Maya")
