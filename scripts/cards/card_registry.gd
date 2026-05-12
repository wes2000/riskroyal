# Power card registry. Pure static; no instance state. Each card effect
# under scripts/cards/effects/<id>.gd exposes a `static const CARD_META:
# Dictionary` plus a `static apply(context, target_peer_id, params)`.
#
# Sub-project #4 Plan A ships 6 cards (Insurance, Heat Shield, Multiplier
# Booster, Double or Nothing, Late Cash, Underdog Odds). Plan B appends
# the remaining 6 (Cash-Out Jammer, Emergency Eject, Heat Spike, Wager Tax,
# Place Bounty, Copycat Bet).
#
# See docs/superpowers/specs/2026-05-12-power-cards-and-bounties-design.md
# for the full contract.
extends Object

const Insurance = preload("res://scripts/cards/effects/insurance.gd")
const HeatShield = preload("res://scripts/cards/effects/heat_shield.gd")
const MultiplierBooster = preload("res://scripts/cards/effects/multiplier_booster.gd")
const DoubleOrNothing = preload("res://scripts/cards/effects/double_or_nothing.gd")
const LateCash = preload("res://scripts/cards/effects/late_cash.gd")
const UnderdogOdds = preload("res://scripts/cards/effects/underdog_odds.gd")

# CARDS dict assembled from each effect file's CARD_META + apply Callable.
# Lazy-built on first lookup. Each entry adds an "effect" Callable to the
# CARD_META so callers can do `card.effect.call(ctx, target, params)`.
static var _cards_cache: Dictionary = {}

static func _build_cards() -> Dictionary:
	return {
		"insurance": _entry(Insurance.CARD_META, Callable(Insurance, "apply")),
		"heat_shield": _entry(HeatShield.CARD_META, Callable(HeatShield, "apply")),
		"multiplier_booster": _entry(MultiplierBooster.CARD_META, Callable(MultiplierBooster, "apply")),
		"double_or_nothing": _entry(DoubleOrNothing.CARD_META, Callable(DoubleOrNothing, "apply")),
		"late_cash": _entry(LateCash.CARD_META, Callable(LateCash, "apply")),
		"underdog_odds": _entry(UnderdogOdds.CARD_META, Callable(UnderdogOdds, "apply")),
	}

static func _entry(meta: Dictionary, effect: Callable) -> Dictionary:
	var e = meta.duplicate(true)
	e["effect"] = effect
	return e

static func _get_cards() -> Dictionary:
	if _cards_cache.is_empty():
		_cards_cache = _build_cards()
	return _cards_cache

static func get_card(card_id: String) -> Dictionary:
	return _get_cards().get(card_id, {})

static func apply_card(card_id: String, context, target_peer_id: int, params = null) -> Dictionary:
	var card = get_card(card_id)
	if card.is_empty():
		return {"applied": false, "type": "unknown_card"}
	return card.effect.call(context, target_peer_id, params)

# Pool used for starter-pack distribution at match start. Excludes the
# sabotage category to keep event 1 calmer.
static func starter_pool() -> Array:
	var pool: Array = []
	for id in _get_cards().keys():
		var c = _get_cards()[id]
		if c.rarity == "common" and c.category != "sabotage":
			pool.append(id)
	return pool

# Pool used for SHOP offers. Currently all known cards.
static func shop_pool() -> Array:
	return _get_cards().keys()

# Heat-bounty value scaler per design doc §6.5. 0-2 = base, 3-5 = +25%,
# 6-8 = +50%, 9-10 = +100%.
static func heat_multiplier(heat: int) -> float:
	if heat <= 2:
		return 1.0
	if heat <= 5:
		return 1.25
	if heat <= 8:
		return 1.5
	return 2.0
