class_name TradeExchange
extends Node
## Drop-in commodity broker. Add as a child of any NPC who should take positions
## for the player, exactly like ShopKeeper/QuestGiver/Interactable -- found by a
## direct-children scan (find_in), so it sits at the body root.
##
## It is to MarketSystem what ShopKeeper is to PlayerInventory: THE COUNTER OWNS THE
## TRANSACTION. Spread, position limits, suspension checks and the actual gold
## movement all live here and return a blank string on success or the refusal reason
## as text, which the market screen shows verbatim. MarketSystem just holds prices
## and positions. A trade fired from a quest script would take the identical path.
##
## Two things bend in the player's favour as they get in with the guild, and they
## are the reason bribery and faction standing pay off here:
##  * SPREAD narrows with the NPC's own disposition (the ShopKeeper price_factor()
##    shape -- one number moves the ask down and the bid up together).
##  * POSITION LIMITS widen with faction REPUTATION. This is the deliberate brake on
##    the whole feature: a stranger can only move a few units, so manipulating the
##    board for real money means being somebody at the guild first.
##
## There is no purse here, unlike ShopKeeper -- a clearing house always clears. The
## position limit is what bounds a trade instead.

## A trade went through, or the board moved under us. The screen rebuilds on this.
signal ledger_changed

## Panel title. Blank falls back to the NPC's profile display name, then its name.
@export var exchange_name: String = ""
## Faction whose standing sets this broker's position limits. Keep it equal to
## MarketSystem.guild_faction, or the guild will fine you for standing you never
## earned here.
@export var faction: StringName = &"Merchant's Guild"

@export_group("Pricing")
## The house's cut, applied to BOTH sides: you buy above the market and sell below
## it. 0.06 = a 12% round trip, so a flat market is a slow loss.
@export_range(0.0, 0.5, 0.01) var commission: float = 0.06
## Price swing per point of the NPC's disposition, same shape and default as
## ShopKeeper.disposition_price_shift.
@export var disposition_price_shift: float = 0.002
@export var min_price_factor: float = 0.85
@export var max_price_factor: float = 1.2

@export_group("Limits")
## Units of any one commodity a nobody may hold.
@export var base_position_limit: int = 8
## Extra units per point of standing with `faction`. At the +100 clamp and the
## default 0.32 that's 32 more units -- five times a stranger's line.
@export var reputation_units_per_point: float = 0.32
## Smallest position the guild will ever clear, whatever your standing.
@export var min_position_limit: int = 4

@export_group("Dialogue")
## Appends the rumours the broker has heard, plus a "look at the board" choice, to
## whatever this NPC already says. Turn off to hand-author a DialogueChoice with
## `opens_market` set instead.
@export var manage_dialogue: bool = true
## Label on the generated choice that opens the board.
@export var browse_text: String = "Show me the board."
## Said before the board opens.
@export_multiline var browse_response: String = "As you like. The ledger's open."

var _interactable: Interactable = null


func _ready() -> void:
	add_to_group("trade_exchange")
	var market := _market()
	if market:
		market.board_changed.connect(_on_board_changed)
		market.rumours_changed.connect(_refresh_dialogue)
	var clock := _clock()
	if clock:
		clock.day_changed.connect(_on_day_changed)
	# Deferred: on an NPC the profile hasn't seeded the Interactable's lines yet.
	_refresh_dialogue.call_deferred()


func _on_board_changed() -> void:
	ledger_changed.emit()


func _on_day_changed(_day: int, _elapsed: int) -> void:
	_refresh_dialogue()


## The sign over the counter -- the market screen's title.
func display_name() -> String:
	if exchange_name != "":
		return exchange_name
	return trader_name()


## The person behind it, for refusal prose where the firm's name reads wrong.
func trader_name() -> String:
	var body := get_parent()
	if body is Npc and body.profile and body.profile.display_name != "":
		return body.profile.display_name
	return body.name if body else "The broker"


# --- Pricing -------------------------------------------------------------------

## The NPC's live disposition, or 0 if this broker isn't on one. Duck typed, exactly
## like ShopKeeper -- a notice board could host an exchange.
func _disposition() -> int:
	var body := get_parent()
	if body and "disposition" in body:
		return int(body.disposition)
	return 0


## Below 1.0 when he likes you: multiplies the ask and divides the bid, so one
## number moves both halves of the trade the same direction.
func price_factor() -> float:
	return clampf(1.0 - _disposition() * disposition_price_shift, min_price_factor, max_price_factor)


## What the player pays per unit.
func ask_price(id: StringName) -> int:
	var market := _market()
	if market == null:
		return 0
	return maxi(roundi(market.price(id) * (1.0 + commission) * price_factor()), 1)


## What the player is paid per unit.
func bid_price(id: StringName) -> int:
	var market := _market()
	if market == null:
		return 0
	var factor := price_factor()
	if is_zero_approx(factor):
		return 1
	return maxi(roundi(market.price(id) * (1.0 - commission) / factor), 1)


## Units of one commodity this broker will let the player hold, widened by standing
## with `faction`.
func position_limit() -> int:
	var standing := 0
	var reputation := _reputation()
	if reputation:
		standing = reputation.modifier(faction)
	return maxi(base_position_limit + roundi(standing * reputation_units_per_point), min_position_limit)


## Units of `id` the player could still buy right now, given the limit and purse.
func room_to_buy(id: StringName) -> int:
	var market := _market()
	var state := _player_state()
	if market == null or state == null:
		return 0
	var by_limit := position_limit() - market.holdings(id)
	var unit_price := ask_price(id)
	var by_purse := (state.gold / unit_price) if unit_price > 0 else 0
	return maxi(mini(by_limit, by_purse), 0)


# --- Transactions --------------------------------------------------------------
# Both check every precondition BEFORE moving anything, so a refused trade leaves
# gold and positions exactly as they were -- the ShopKeeper contract.

## Player opens/adds to a position. Blank string on success, else the refusal.
func player_buy(id: StringName, units: int = 1) -> String:
	var market := _market()
	var state := _player_state()
	if market == null or state == null:
		return "The exchange is closed."
	if units <= 0:
		return "Nothing selected."
	if market.commodity(id) == null:
		return "%s doesn't deal in that." % trader_name()
	var barred := _barred_message()
	if barred != "":
		return barred

	var limit := position_limit()
	if market.holdings(id) + units > limit:
		return "The guild won't clear more than %d %s to your name." % [
			limit, _unit_plural(id, limit)]

	var cost := ask_price(id) * units
	if state.gold < cost:
		return "You can't cover %d gold." % cost
	if not state.spend_gold(cost):
		return "You can't cover %d gold." % cost

	market.add_position(id, units, cost)
	ledger_changed.emit()
	return ""


## Player closes part of a position. Blank string on success, else the refusal.
func player_sell(id: StringName, units: int = 1) -> String:
	var market := _market()
	var state := _player_state()
	if market == null or state == null:
		return "The exchange is closed."
	if units <= 0:
		return "Nothing selected."
	var held := market.holdings(id)
	if held < units:
		return "You don't hold that many."
	var barred := _barred_message()
	if barred != "":
		return barred

	var proceeds := bid_price(id) * units
	market.remove_position(id, units)
	state.add_gold(proceeds)
	ledger_changed.emit()
	return ""


func _barred_message() -> String:
	var market := _market()
	if market and market.is_barred():
		return "%s won't deal with you until day %d." % [trader_name(), market.barred_until_day]
	return ""


func _unit_plural(id: StringName, count: int) -> String:
	var c: Commodity = _market().commodity(id) if _market() else null
	if c == null:
		return "units"
	return c.unit_name if count == 1 else c.unit_name + "s"


# --- Dialogue ------------------------------------------------------------------
# The broker passes on what he's heard. This is the whole point of scheduling
# ambient events days ahead: the rumour is the edge, and it arrives through the
# dialogue system you already have rather than through a bespoke news UI.

func _refresh_dialogue() -> void:
	if not manage_dialogue:
		return
	if _interactable == null or not is_instance_valid(_interactable):
		_interactable = Interactable.find_in(get_parent())
	if _interactable == null:
		return

	# Start from what the NPC already says -- the authored/profile lines are left
	# untouched underneath the override, so turning manage_dialogue off restores them.
	var lines: Array[String] = _interactable.dialogue_lines.duplicate()
	var market := _market()
	if market:
		lines.append_array(market.rumours())

	var choices: Array[DialogueChoice] = _interactable.dialogue_choices.duplicate()
	var browse := DialogueChoice.new()
	browse.text = browse_text
	browse.response = browse_response
	browse.opens_market = true
	choices.append(browse)

	_interactable.set_dialogue_override(lines, choices)


func _market() -> MarketSystem:
	return get_node_or_null("/root/Market") as MarketSystem


func _player_state() -> PlayerStateSystem:
	return get_node_or_null("/root/PlayerState") as PlayerStateSystem


func _reputation() -> ReputationSystem:
	return get_node_or_null("/root/Reputation") as ReputationSystem


func _clock() -> WorldClockSystem:
	return get_node_or_null("/root/WorldClock") as WorldClockSystem


## Mirrors ShopKeeper.find_in / Interactable.find_in -- a direct-children scan.
static func find_in(body: Node) -> TradeExchange:
	if body == null:
		return null
	for child in body.get_children():
		if child is TradeExchange:
			return child
	return null
