class_name MarketSystem
extends Node
## The commodity board: prices, the player's positions, and the guild's suspicion.
## Registered as the `Market` autoload (class/singleton names differ for the usual
## reason), so positions and heat survive the player-death reload and level changes
## exactly like PlayerProgression and Reputation. Nothing is written to disk.
##
## PRICES ONLY MOVE WHEN SOMETHING HAPPENS. There is no per-frame drift and no
## random walk: price = base * (1 + the sum of every active effect), where an effect
## is one MarketEvent fading linearly over its decay_days. Every price on the board
## is therefore traceable to a specific piece of news, which is the whole point --
## the player is meant to read the board as a list of things somebody did.
##
## Three rules worth keeping:
##  * POSITIONS ARE PAPER, not items. Nothing here touches PlayerInventory; a
##    holding is a number of units and a cost basis, so speculating never competes
##    with your backpack for slots.
##  * THE COUNTER IS NOT HERE. TradeExchange owns spread, position caps and the
##    actual gold movement, the same way ShopKeeper owns a shop's transaction while
##    PlayerInventory just owns the goods. This file is the model.
##  * EVENTS DON'T KNOW WHO CAUSED THEM. apply_event() is told `player_caused` by
##    its caller, because "warehouse burns" is insider trading when the player lit
##    it and ordinary news when it burned on its own.

## Any price moved -- the market screen rebuilds on this.
signal board_changed
## An event landed. `player_caused` is what separates news from a confession.
signal event_fired(event: MarketEvent, player_caused: bool)
signal holdings_changed(commodity_id: StringName, units: int)
signal heat_changed(heat: int, delta: int)
## The guild acted on its suspicion. `level` is 1 warning / 2 fine / 3 suspension.
signal investigated(level: int, message: String)
## A scheduled event was booked or arrived, so any rumour list should refresh.
signal rumours_changed

## WorldClock schedule tag for a market event booked days ahead.
const SCHEDULE_TAG := &"market_event"
const HEAT_MAX := 100

@export_group("Prices")
## Hard bounds on the multiplier, so a pile-up of events can't take a price to zero
## or to the moon.
@export var min_price_factor: float = 0.15
@export var max_price_factor: float = 4.0
## Headlines kept for the market screen's news column.
@export var news_limit: int = 8

@export_group("Ambient events")
## Chance per day that the world produces news the player had nothing to do with.
## This is what makes a held position risky and a broker worth talking to.
@export_range(0.0, 1.0, 0.05) var ambient_event_chance: float = 0.35
## Ambient events are booked this many days ahead rather than landing at once, so
## the rumour has time to reach the player before the price moves.
@export var ambient_lead_days_min: int = 2
@export var ambient_lead_days_max: int = 4

@export_group("Insider heat")
## Faction that takes the reputation hit when the guild acts. Must match the
## exchange's `faction` (and the brokers' NpcProfile.faction) so trading dirty costs
## standing where it hurts -- the project's existing tag is "Merchant's Guild".
@export var guild_faction: StringName = &"Merchant's Guild"
## Heat added when the player is caught fully positioned for their own sabotage.
@export var insider_heat_max: int = 45
## Position size (in units) that counts as "fully positioned" for the above.
@export var heat_reference_units: int = 20
## Heat bled off per day. Lie low and the guild loses interest.
@export var heat_decay_per_day: int = 4
## Thresholds for the guild's three escalating responses.
@export var warn_heat: int = 35
@export var fine_heat: int = 65
@export var suspend_heat: int = 95
## Fraction of the player's purse taken as a fine at level 2.
@export_range(0.0, 1.0, 0.05) var fine_fraction: float = 0.25
## Days barred from trading at level 3.
@export var suspension_days: int = 5
## Standing lost with `guild_faction` at each level.
@export var warn_reputation_penalty: int = 5
@export var fine_reputation_penalty: int = 10
@export var suspend_reputation_penalty: int = 20

## Current suspicion, 0..HEAT_MAX.
var heat: int = 0
## Day the player may trade again. 0 = not suspended.
var barred_until_day: int = 0

var _commodities: Dictionary = {}          ## id -> Commodity
var _order: Array[StringName] = []         ## stable display order
var _effects: Array[Dictionary] = []       ## live price moves (see _add_effect)
var _holdings: Dictionary = {}             ## id -> units (int)
var _basis: Dictionary = {}                ## id -> total gold paid (float)
var _news: Array[Dictionary] = []          ## most recent first
var _pending: Array[Dictionary] = []       ## booked-but-unfired events
## Highest guild response already served at the current heat, so escalation happens
## once per level rather than every time heat ticks up past a threshold.
var _action_level: int = 0


func _ready() -> void:
	for c in MockMarket.commodities():
		_commodities[c.id] = c
		_order.append(c.id)
	var clock := _clock()
	if clock:
		clock.day_passed.connect(_on_day_passed)
		clock.scheduled_fired.connect(_on_scheduled_fired)


# --- The board -----------------------------------------------------------------

## Every commodity, in authored order. Live objects -- treat as read-only.
func commodities() -> Array[Commodity]:
	var out: Array[Commodity] = []
	for id in _order:
		out.append(_commodities[id])
	return out


func commodity(id: StringName) -> Commodity:
	return _commodities.get(id, null)


## Combined multiplier on base price from every active effect.
func price_factor(id: StringName) -> float:
	var total := 0.0
	for effect in _effects:
		if effect["commodity"] == id:
			total += float(effect["magnitude"]) * _effect_strength(effect)
	return clampf(1.0 + total, min_price_factor, max_price_factor)


## Current price of one unit, in gold. Never below 1.
func price(id: StringName) -> int:
	var c: Commodity = commodity(id)
	if c == null:
		return 0
	return maxi(roundi(c.base_price * price_factor(id)), 1)


## Signed percentage away from base, for the board's "+34%" column.
func price_delta_percent(id: StringName) -> float:
	return (price_factor(id) - 1.0) * 100.0


## Remaining share of an effect's magnitude, fading linearly to 0 on its last day.
func _effect_strength(effect: Dictionary) -> float:
	var total: int = maxi(int(effect["decay_days"]), 1)
	return clampf(float(effect["days_left"]) / float(total), 0.0, 1.0)


## Live effects touching a commodity, for the screen's per-good breakdown.
func effects_for(id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for effect in _effects:
		if effect["commodity"] == id:
			out.append(effect.duplicate())
	return out


## Recent headlines, most recent first.
func news() -> Array[Dictionary]:
	return _news.duplicate(true)


# --- Events --------------------------------------------------------------------

## Applies an event to the board. `player_caused` decides whether it also counts as
## insider trading -- pass false for world-driven news.
func apply_event(event: MarketEvent, player_caused: bool = false) -> void:
	if event == null:
		push_warning("MarketSystem.apply_event called with no event.")
		return
	var c: Commodity = commodity(event.commodity)
	if c == null:
		push_warning("MarketSystem: event '%s' names unknown commodity '%s'."
			% [event.id, event.commodity])
		return

	# Ambient news is scaled by how jumpy the good is; a player's sabotage lands as
	# authored, because they aimed it.
	var magnitude := event.magnitude
	if not player_caused:
		magnitude *= c.volatility

	_add_effect(event.commodity, magnitude, event.decay_days, event)
	# The rival moves the other way -- this is what makes sabotage profitable
	# without short-selling. See Commodity.rival.
	if event.rival_scale > 0.0 and not String(c.rival).is_empty() and _commodities.has(c.rival):
		_add_effect(c.rival, -magnitude * event.rival_scale, event.decay_days, event)

	_record_news(event, magnitude, player_caused)
	_check_insider(event, magnitude, player_caused)
	event_fired.emit(event, player_caused)
	board_changed.emit()


func _add_effect(id: StringName, magnitude: float, decay_days: int, event: MarketEvent) -> void:
	if is_zero_approx(magnitude):
		return
	_effects.append({
		"commodity": id,
		"magnitude": magnitude,
		"decay_days": maxi(decay_days, 1),
		"days_left": maxi(decay_days, 1),
		"headline": event.headline,
		"event_id": event.id,
		# Stamped so today's decay pass skips an effect that landed today -- a
		# scheduled event fires before day_passed, and would otherwise lose a day
		# of its life the moment it arrived.
		"created_day": _today(),
	})


func _record_news(event: MarketEvent, magnitude: float, player_caused: bool) -> void:
	_news.push_front({
		"day": _today(),
		"headline": event.headline,
		"detail": event.detail,
		"commodity": event.commodity,
		"magnitude": magnitude,
		"player_caused": player_caused,
	})
	while _news.size() > news_limit:
		_news.pop_back()


## Books an event for a future day through the WorldClock schedule. Returns the
## schedule id, or -1 with no clock.
func schedule_event(event: MarketEvent, days_from_now: int) -> int:
	var clock := _clock()
	if clock == null or event == null:
		return -1
	var id := clock.schedule(days_from_now, SCHEDULE_TAG, {"event": event})
	_pending.append({"schedule_id": id, "event": event, "due_day": clock.day + maxi(days_from_now, 1)})
	rumours_changed.emit()
	return id


func _on_scheduled_fired(tag: StringName, payload: Dictionary) -> void:
	if tag != SCHEDULE_TAG:
		return
	var event: MarketEvent = payload.get("event", null)
	for i in _pending.size():
		if _pending[i]["event"] == event:
			_pending.remove_at(i)
			break
	rumours_changed.emit()
	apply_event(event, false)


## Rumour lines for events booked but not yet landed -- what a broker passes on.
## Deliberately vague about timing: the hint is the edge, not a countdown.
func rumours() -> Array[String]:
	var out: Array[String] = []
	for entry in _pending:
		var event: MarketEvent = entry["event"]
		if event and not event.rumour.is_empty():
			out.append(event.rumour)
	return out


# --- The calendar --------------------------------------------------------------

func _on_day_passed(_day: int) -> void:
	_decay_effects()
	_decay_heat()
	_roll_ambient()
	board_changed.emit()


func _decay_effects() -> void:
	var today := _today()
	var i := _effects.size() - 1
	while i >= 0:
		# Skip anything that landed today (see _add_effect).
		if int(_effects[i]["created_day"]) < today:
			_effects[i]["days_left"] = int(_effects[i]["days_left"]) - 1
			if int(_effects[i]["days_left"]) <= 0:
				_effects.remove_at(i)
		i -= 1


func _roll_ambient() -> void:
	if ambient_event_chance <= 0.0 or randf() > ambient_event_chance:
		return
	var pool := MockMarket.ambient_events()
	if pool.is_empty():
		return
	# Don't book something already pending or still moving the board -- two blights
	# in one week reads as a bug rather than as weather.
	var candidates: Array[MarketEvent] = []
	for event in pool:
		if not _is_event_live(event.id):
			candidates.append(event)
	if candidates.is_empty():
		return
	var chosen: MarketEvent = candidates[randi() % candidates.size()]
	schedule_event(chosen, randi_range(ambient_lead_days_min, maxi(ambient_lead_days_max, ambient_lead_days_min)))


func _is_event_live(event_id: StringName) -> bool:
	for effect in _effects:
		if effect["event_id"] == event_id:
			return true
	for entry in _pending:
		var event: MarketEvent = entry["event"]
		if event and event.id == event_id:
			return true
	return false


# --- Positions -----------------------------------------------------------------

func holdings(id: StringName) -> int:
	return int(_holdings.get(id, 0))


## Total units held across the whole board.
func total_units() -> int:
	var total := 0
	for id in _holdings:
		total += int(_holdings[id])
	return total


## Average gold paid per unit held, or 0.0 with no position.
func average_cost(id: StringName) -> float:
	var units := holdings(id)
	if units <= 0:
		return 0.0
	return float(_basis.get(id, 0.0)) / float(units)


## What the position would fetch at today's price, ignoring the exchange's cut.
func position_value(id: StringName) -> int:
	return holdings(id) * price(id)


## Gold up or down on an open position at today's price.
func unrealised_profit(id: StringName) -> int:
	if holdings(id) <= 0:
		return 0
	return position_value(id) - roundi(float(_basis.get(id, 0.0)))


## Records a purchase. Called by TradeExchange AFTER it has taken payment -- this
## does not touch gold.
func add_position(id: StringName, units: int, gold_paid: int) -> void:
	if units <= 0 or not _commodities.has(id):
		return
	_holdings[id] = holdings(id) + units
	_basis[id] = float(_basis.get(id, 0.0)) + float(gold_paid)
	holdings_changed.emit(id, holdings(id))


## Records a sale and returns the cost basis released, so the caller can report
## realised profit. Does not touch gold.
func remove_position(id: StringName, units: int) -> int:
	var held := holdings(id)
	if units <= 0 or held < units:
		return 0
	var basis: float = float(_basis.get(id, 0.0))
	var released: float = basis * (float(units) / float(held))
	_holdings[id] = held - units
	_basis[id] = basis - released
	if holdings(id) <= 0:
		_holdings.erase(id)
		_basis.erase(id)
	holdings_changed.emit(id, holdings(id))
	return roundi(released)


# --- Insider heat --------------------------------------------------------------
# What stops "buy, then burn it down" from being a free money printer. Causing an
# event you are positioned to profit from is noticed; the guild escalates from a
# warning to a fine to a suspension, and heat bleeds off if you lie low.

## Raises suspicion if the player held a position that profits from an event they
## caused. Holding the RIVAL counts too -- that's the whole trick, so it's exactly
## what the guild watches for.
func _check_insider(event: MarketEvent, magnitude: float, player_caused: bool) -> void:
	if not player_caused or is_zero_approx(magnitude):
		return
	var c: Commodity = commodity(event.commodity)
	var profiting_id: StringName = &""
	if magnitude > 0.0:
		profiting_id = event.commodity
	elif c and not String(c.rival).is_empty() and event.rival_scale > 0.0:
		profiting_id = c.rival  # the good they hit fell, so its pair rose
	if String(profiting_id).is_empty():
		return

	var units := holdings(profiting_id)
	if units <= 0:
		return  # sabotage with no position is just arson
	var severity := clampf(float(units) / float(maxi(heat_reference_units, 1)), 0.0, 1.0)
	add_heat(roundi(insider_heat_max * severity))


## Adds (or with a negative amount, removes) suspicion and lets the guild react.
func add_heat(amount: int) -> void:
	if amount == 0:
		return
	var before := heat
	heat = clampi(heat + amount, 0, HEAT_MAX)
	var applied := heat - before
	if applied == 0:
		return
	heat_changed.emit(heat, applied)
	_check_investigation()


func _decay_heat() -> void:
	if heat > 0:
		add_heat(-heat_decay_per_day)


## The response level the current heat warrants: 0 none, 1 warning, 2 fine,
## 3 suspension.
func heat_level() -> int:
	if heat >= suspend_heat:
		return 3
	if heat >= fine_heat:
		return 2
	if heat >= warn_heat:
		return 1
	return 0


func _check_investigation() -> void:
	var level := heat_level()
	if level <= _action_level:
		# Cooled off below a threshold -- that response can be served again later.
		_action_level = level
		return
	_action_level = level
	match level:
		1:
			_penalise(warn_reputation_penalty,
				"The guild's clerks have started keeping a separate ledger on you.")
		2:
			var state := _player_state()
			var fine := 0
			if state:
				fine = roundi(state.gold * fine_fraction)
				if fine > 0:
					state.spend_gold(fine)
			_penalise(fine_reputation_penalty,
				"Fined %d gold for trading on foreknowledge." % fine if fine > 0
				else "Fined for trading on foreknowledge -- you had nothing to take.")
		3:
			var clock := _clock()
			barred_until_day = (clock.day if clock else 0) + suspension_days
			# Dropped to just under the fine threshold, so a suspension is a reset
			# rather than a permanent ban.
			heat = fine_heat - 1
			heat_changed.emit(heat, 0)
			_action_level = 2
			_penalise(suspend_reputation_penalty,
				"Barred from the exchange until day %d." % barred_until_day)


func _penalise(reputation_cost: int, message: String) -> void:
	var reputation := _reputation()
	if reputation and reputation_cost != 0:
		reputation.adjust(guild_faction, -reputation_cost)
	investigated.emit(heat_level(), message)


## True while the guild has the player's trading privileges suspended.
func is_barred() -> bool:
	return barred_until_day > 0 and _today() < barred_until_day


# --- Plumbing ------------------------------------------------------------------

func _today() -> int:
	var clock := _clock()
	return clock.day if clock else 0


func _clock() -> WorldClockSystem:
	return get_node_or_null("/root/WorldClock") as WorldClockSystem


func _player_state() -> PlayerStateSystem:
	return get_node_or_null("/root/PlayerState") as PlayerStateSystem


func _reputation() -> ReputationSystem:
	return get_node_or_null("/root/Reputation") as ReputationSystem


## Wipes positions, prices and suspicion. No UI yet -- here so a future new-game has
## one call, matching ReputationSystem.reset() / SkillSystem.reset().
func reset() -> void:
	_effects.clear()
	_holdings.clear()
	_basis.clear()
	_news.clear()
	_pending.clear()
	heat = 0
	barred_until_day = 0
	_action_level = 0
	board_changed.emit()
	rumours_changed.emit()
