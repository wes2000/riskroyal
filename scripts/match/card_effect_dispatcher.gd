# Card effect dispatcher. Extracted from MatchController in Plan B
# Phase 7. Receives a MatchState + effect dict + peer_id + is_host flag
# and mutates state accordingly. Caller (MatchController) handles the
# RPC sender side: this dispatcher is pure state mutation. Cards that
# need outbound RPCs after state mutation (place_bounty, copycat_bet,
# double_or_nothing) are routed through MatchController's wrapper, which
# inspects effect.type after calling this and broadcasts host-only.
extends Object

const Bounty = preload("res://scripts/match/bounty.gd")
const MatchConfig = preload("res://scripts/match/match_config.gd")

static func apply(state, peer_id: int, effect: Dictionary, is_host: bool) -> void:
	if not effect.get("applied", false):
		return
	var t = effect.get("type", "")
	match t:
		"insurance_pre":
			# Sub-project #6 Plan A: No Insurance twist short-circuits.
			if state.house_twist.get("type", "") == "no_insurance":
				return
			_ensure_modifiers(state, peer_id)
			state.event_modifiers[peer_id]["insurance_pre"] = true
		"heat_shield":
			_ensure_modifiers(state, peer_id)
			state.event_modifiers[peer_id]["heat_shield"] = true
		"wager_multiplier":
			_ensure_modifiers(state, peer_id)
			state.event_modifiers[peer_id]["wager_multiplier"] = float(effect.get("multiplier", 1.0))
		"late_cash_bonus":
			_ensure_modifiers(state, peer_id)
			state.event_modifiers[peer_id]["late_cash_bonus"] = true
			state.event_modifiers[peer_id]["late_cash_threshold"] = float(effect.get("threshold", 5.0))
			state.event_modifiers[peer_id]["late_cash_bonus_chips"] = int(effect.get("bonus_chips", 200))
		"underdog_multiplier":
			_ensure_modifiers(state, peer_id)
			state.event_modifiers[peer_id]["underdog_multiplier"] = float(effect.get("multiplier", 1.5))
		"double_or_nothing":
			var new_wager = int(effect.get("new_wager", 0))
			state.pending_wagers[peer_id] = new_wager
		"post_event_heat_delta":
			state.pending_card_effects.append({
				"type": "heat_delta",
				"target": int(effect.get("target", 0)),
				"delta": int(effect.get("delta", 0)),
			})
		"post_event_wager_tax":
			state.pending_card_effects.append({
				"type": "wager_tax",
				"source": int(effect.get("source", 0)),
				"target": int(effect.get("target", 0)),
			})
		"place_bounty":
			# Host-only state mutation; caller's wrapper handles _rpc_bounties_placed.
			# Phase C Change 4 (§8.6): forward claim_mode (defaults to "placer"
			# for the Place Bounty card so the placer claims solo on success).
			if is_host:
				var b = Bounty.new()
				b.origin = "placed"
				b.target = int(effect.get("target", 0))
				b.condition = "bust"
				b.reward_chips = int(effect.get("reward_chips", MatchConfig.BOUNTY_BASE_REWARD))
				b.placed_by = int(effect.get("placed_by", 0))
				b.placed_at_event = int(effect.get("placed_at_event", state.event_index))
				b.placed_at_target_heat = int(effect.get("placed_at_target_heat", 0))
				b.claim_mode = String(effect.get("claim_mode", "placer"))
				state.bounties.append(b)
		"copycat_bet":
			var caller = int(effect.get("source", peer_id))
			var new_wager = int(effect.get("new_wager", 0))
			state.pending_wagers[caller] = new_wager
		"cash_out_delay":
			# Phase C Change 4 (§8.4): preserve source for attribution.
			state.pending_card_effects.append({
				"type": "cash_out_delay",
				"source": int(effect.get("source", 0)),
				"target": int(effect.get("target", 0)),
				"delay_ms": int(effect.get("delay_ms", 750)),
			})
		"auto_eject_loaded":
			_ensure_modifiers(state, peer_id)
			state.event_modifiers[peer_id]["auto_eject_loaded"] = true
			state.event_modifiers[peer_id]["auto_eject_threshold"] = float(effect.get("threshold", 3.0))
		_:
			push_warning("CardEffectDispatcher: unhandled effect type: %s" % t)

static func _ensure_modifiers(state, peer_id: int) -> void:
	if not state.event_modifiers.has(peer_id):
		state.event_modifiers[peer_id] = {}
