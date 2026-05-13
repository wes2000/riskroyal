# Underdog Odds card: if the player is currently last in chips, their
# chip gain this event is multiplied by 1.5 (only if they survive).
# Gates at apply-time on the caller's chip rank in context.players.
#
# IMPORTANT: This card reads caller.chips from ctx.players at apply time
# (BET_LOADOUT). Currently safe because no Plan A/B card mutates chips
# during BET_LOADOUT (Wager Tax, Heat Spike apply post-event; Copycat Bet
# only touches state.pending_wagers). Future BET_LOADOUT cards that touch
# p.chips will break this card's rank gate silently — snapshot chips into
# event_modifiers at HOUSE_REVEAL if that ever changes.
extends Object

const CARD_META: Dictionary = {
	"name": "Underdog Odds",
	"rarity": "common",
	"category": "social",
	"timing": "bet_loadout",
	"target_required": false,
	"cost_chips": 50,
	"description": "If you're last in chips, your reward this event x1.5.",
}

static func apply(context, target_peer_id: int, _params = null) -> Dictionary:
	# target_peer_id here is the caller's own peer_id (self-target convention).
	if context == null:
		return {"applied": false, "type": "underdog_multiplier"}
	var min_chips = -1
	for p in context.players:
		if min_chips < 0 or p.chips < min_chips:
			min_chips = p.chips
	var caller = null
	for p in context.players:
		if p.peer_id == target_peer_id:
			caller = p
			break
	if caller == null or caller.chips != min_chips:
		return {"applied": false, "type": "underdog_multiplier"}
	return {
		"type": "underdog_multiplier",
		"applied": true,
		"multiplier": 1.5,
	}
