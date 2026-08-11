extends Node
class_name ShopKeeper
## Drop-in vendor component. Add as a child of any NPC who should trade, exactly
## like QuestGiver/Interactable/DamageReceiver -- it's found by a direct-children
## scan (find_in), so it sits at the body root.
##
## It owns the whole transaction: stock, purse, pricing, and the actual
## buy/sell calls against PlayerInventory + PlayerState. The ShopScreen is a dumb
## view over this, so a trade triggered from anywhere else (a quest script, a
## vending machine) would go through the same two methods.
##
## Stock is FINITE and the purse is REAL: buying depletes a line, selling drains
## his gold, and he'll refuse a sale he can't pay for. `stock` is authored data
## and is never mutated -- _runtime_stock holds duplicated working copies, the
## same rule NpcProfile follows (a shared resource must survive being traded
## against).
##
## Prices bend with the NPC's DISPOSITION, which makes the existing
## bribery/reputation systems worth something at the counter: being liked makes
## his goods cheaper AND his offers for your junk better.

## Stock or purse changed -- the screen rebuilds on this.
signal stock_changed

## Panel title. Blank falls back to the NPC's profile display name, then its name.
@export var shop_name: String = ""
## Goods for sale. Each entry's stack_count is how many are in stock.
@export var stock: Array[InventoryItem] = []
## Fills empty stock with MockItemDatabase's placeholder wares, matching how the
## rest of the project stands in for a real content pipeline.
@export var use_default_stock: bool = true
## Coin on hand. Caps what he can buy from the player; drops as he pays out.
@export var gold: int = 400
## Stock lines never deplete when true (his purse still limits buying).
@export var infinite_stock: bool = false

@export_group("Pricing")
## Sale price = item.value * this. Above 1.0 = he takes a cut on what he sells.
@export var buy_markup: float = 1.6
## Offer price = item.value * this. Below 1.0 = he lowballs what he buys.
@export var sell_rate: float = 0.4
## Price swing per point of the NPC's disposition. At the +/-100 disposition clamp
## and the default 0.003, prices move by 30% in your favour or against you.
@export var disposition_price_shift: float = 0.003
## Bounds on that swing, so an extreme disposition can't invert the economy.
@export var min_price_factor: float = 0.7
@export var max_price_factor: float = 1.4
## Nothing is ever free -- a worthless item still costs this to buy.
@export var min_price: int = 1
## Won't take quest items off your hands. Selling the plot key is rarely intended.
@export var refuses_quest_items: bool = true

## Working copies of `stock`; the authored resources are left untouched.
var _runtime_stock: Array[InventoryItem] = []


func _ready() -> void:
	var source := stock
	if source.is_empty() and use_default_stock:
		source = MockItemDatabase.make_merchant_stock()
	for entry in source:
		if entry:
			_runtime_stock.append(entry.duplicate())


## What the screen lists on the merchant's side. Live objects -- treat as read-only.
func wares() -> Array[InventoryItem]:
	return _runtime_stock


## The sign over the counter -- the shop screen's title.
func display_name() -> String:
	if shop_name != "":
		return shop_name
	return trader_name()


## The person behind it. Used in refusal messages, where the shop's sign reads
## wrong in a sentence ("Tom's Sundries won't take that").
func trader_name() -> String:
	var owner_body := get_parent()
	if owner_body is Npc and owner_body.profile and owner_body.profile.display_name != "":
		return owner_body.profile.display_name
	return owner_body.name if owner_body else "The trader"


# --- Pricing -------------------------------------------------------------------

## The NPC's live disposition, or 0 if this keeper isn't parented to one (duck
## typed, so a crate or a vending machine can host a shop just as well).
func _disposition() -> int:
	var owner_body := get_parent()
	if owner_body and "disposition" in owner_body:
		return int(owner_body.disposition)
	return 0


## Below 1.0 when he likes you. Multiplies his asking price and divides his offer,
## so a single number moves both halves of the trade the same direction.
func price_factor() -> float:
	return clampf(1.0 - _disposition() * disposition_price_shift, min_price_factor, max_price_factor)


## What the player pays for one unit.
func buy_price(item: InventoryItem) -> int:
	if item == null:
		return 0
	return maxi(roundi(item.value * buy_markup * price_factor()), min_price)


## What the player is offered for one unit.
func sell_price(item: InventoryItem) -> int:
	if item == null:
		return 0
	var factor := price_factor()
	if is_zero_approx(factor):
		return min_price
	return maxi(roundi(item.value * sell_rate / factor), min_price)


func will_buy(item: InventoryItem) -> bool:
	if item == null:
		return false
	if refuses_quest_items and item.item_type == InventoryItem.ItemType.QUEST:
		return false
	return true


# --- Transactions --------------------------------------------------------------
# Both check every precondition BEFORE moving anything, so a refused trade leaves
# gold, stock and bag exactly as they were.

## Player buys `count` units of the stock entry at `index`. Returns a blank string
## on success, or the reason it was refused (shown on the shop screen).
func player_buy(index: int, count: int = 1) -> String:
	if index < 0 or index >= _runtime_stock.size() or count <= 0:
		return "Nothing selected."
	var line := _runtime_stock[index]
	if not infinite_stock and line.stack_count < count:
		return "%s doesn't have that many." % trader_name()

	var state := _player_state()
	var inventory := _inventory()
	if state == null or inventory == null:
		return "Can't trade right now."

	var price := buy_price(line) * count
	if state.gold < price:
		return "You can't afford that."
	if not inventory.has_room_for(line, count):
		return "Your pack is full."

	if not state.spend_gold(price):
		return "You can't afford that."
	inventory.add_item(line, count)
	gold += price
	if not infinite_stock:
		line.stack_count -= count
		if line.stack_count <= 0:
			_runtime_stock.remove_at(index)
	stock_changed.emit()
	return ""


## Player sells `count` units out of backpack slot `slot_index`.
func player_sell(slot_index: int, count: int = 1) -> String:
	var inventory := _inventory()
	var state := _player_state()
	if inventory == null or state == null:
		return "Can't trade right now."
	var entry := inventory.slot(slot_index)
	if entry == null or count <= 0:
		return "Nothing selected."
	if not will_buy(entry):
		return "%s won't take that." % trader_name()
	if entry.stack_count < count:
		return "You don't have that many."

	var price := sell_price(entry) * count
	if gold < price:
		return "%s doesn't have the coin for that." % trader_name()

	var sold := inventory.remove_from_slot(slot_index, count)
	if sold == null:
		return "Nothing selected."
	gold -= price
	state.add_gold(price)
	_take_into_stock(sold)
	stock_changed.emit()
	return ""


## Sold goods go onto his shelf, so you can buy back something sold by mistake.
func _take_into_stock(sold: InventoryItem) -> void:
	if infinite_stock:
		return
	for line in _runtime_stock:
		if line.id == sold.id and line.max_stack > 1:
			line.stack_count += sold.stack_count
			return
	_runtime_stock.append(sold)


func _inventory() -> PlayerInventorySystem:
	return get_node_or_null("/root/PlayerInventory") as PlayerInventorySystem


func _player_state() -> PlayerStateSystem:
	return get_node_or_null("/root/PlayerState") as PlayerStateSystem


## Returns the ShopKeeper child of a body, or null. Mirrors Interactable.find_in /
## DamageReceiver.find_in -- a direct-children scan.
static func find_in(body: Node) -> ShopKeeper:
	if body == null:
		return null
	for child in body.get_children():
		if child is ShopKeeper:
			return child
	return null
