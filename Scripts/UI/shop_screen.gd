class_name ShopScreen
extends Control
## Trading screen: the merchant's stock on the left, your pack on the right, each
## line priced in the direction it would move. Opened by a ShopKeeper (normally
## through a dialogue choice with `opens_shop` set) and registered as the `ShopUI`
## autoload.
##
## Follows every menu-screen convention -- backdrop, shared theme, pause + mouse
## release, process_mode ALWAYS, HUD hide, mutual exclusion via group
## "menu_screen". Like DialogueScreen/LevelCompleteScreen the script sits on the
## autoload's `Screen` child, so it's found by GROUP ("shop_screen"), not by
## /root/ShopUI.
##
## It's a VIEW and nothing more: every rule about whether a trade is allowed, and
## every number, comes from the ShopKeeper. This file only decides what's on
## screen and which row is selected.

## Which half of the screen a selection lives in. NB the name is deliberately not
## `Side` -- that collides with Godot's built-in global Side enum (SIDE_LEFT etc.),
## and a parameter typed `side: Side` silently resolves to the ENGINE's enum, so
## passing this one is a parse error. Same family as the State/FsmState collision
## documented in CLAUDE.md: keep generic names distinct.
enum TradeSide { MERCHANT, PLAYER }

@onready var _shop_title: Label = %ShopTitle
@onready var _close_button: Button = %CloseButton
@onready var _merchant_gold: Label = %MerchantGold
@onready var _player_gold: Label = %PlayerGold
@onready var _stock_list: VBoxContainer = %StockList
@onready var _bag_list: VBoxContainer = %BagList
@onready var _buy_button: Button = %BuyButton
@onready var _buy_all_button: Button = %BuyAllButton
@onready var _sell_button: Button = %SellButton
@onready var _sell_all_button: Button = %SellAllButton
@onready var _status_label: Label = %StatusLabel
@onready var _tooltip: ItemTooltip = $Tooltip

var is_open := false

var _keeper: ShopKeeper = null
## Index into the keeper's wares() / the player's backpack, or -1 for no selection.
var _stock_index := -1
var _bag_index := -1
## Cleared on the next rebuild, so a refusal reason doesn't linger past the
## trade that caused it.
var _status := ""


func _ready() -> void:
	add_to_group("menu_screen")
	add_to_group("shop_screen")
	visible = false
	_close_button.pressed.connect(close)
	_buy_button.pressed.connect(_on_buy.bind(1))
	_buy_all_button.pressed.connect(_on_buy.bind(-1))
	_sell_button.pressed.connect(_on_sell.bind(1))
	_sell_all_button.pressed.connect(_on_sell.bind(-1))

	var inventory := _inventory()
	if inventory:
		inventory.inventory_changed.connect(_on_world_changed)
	var state := _player_state()
	if state:
		state.gold_changed.connect(_on_world_changed.unbind(1))


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	# Registered last among the UI autoloads, so this sees input before the
	# inventory/journal do and can swallow their toggles while trading.
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("inventory") \
			or event.is_action_pressed("journal"):
		close()
		get_viewport().set_input_as_handled()


## Opens the counter for `keeper`. The only entry point -- there's no toggle key,
## since a shop is always something you walk up to.
func open(keeper: ShopKeeper) -> void:
	if keeper == null:
		return
	_close_other_menus()
	if _keeper and is_instance_valid(_keeper) and _keeper != keeper \
			and _keeper.stock_changed.is_connected(_on_world_changed):
		_keeper.stock_changed.disconnect(_on_world_changed)
	_keeper = keeper
	if not keeper.stock_changed.is_connected(_on_world_changed):
		keeper.stock_changed.connect(_on_world_changed)

	_stock_index = -1
	_bag_index = -1
	_status = ""
	is_open = true
	visible = true
	_shop_title.text = keeper.display_name().to_upper()
	_rebuild()
	_set_hud_visible(false)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	is_open = false
	visible = false
	_tooltip.hide_tooltip()
	if _keeper and is_instance_valid(_keeper) and _keeper.stock_changed.is_connected(_on_world_changed):
		_keeper.stock_changed.disconnect(_on_world_changed)
	_keeper = null
	_set_hud_visible(true)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _close_other_menus() -> void:
	for menu in get_tree().get_nodes_in_group("menu_screen"):
		if menu != self and menu.is_open:
			menu.close()


func _set_hud_visible(shown: bool) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hud_visible"):
		hud.set_hud_visible(shown)


## Gold spent/earned elsewhere, or the keeper restocking, while the counter is up.
func _on_world_changed() -> void:
	if is_open:
		_rebuild()


# --- Rendering -----------------------------------------------------------------

func _rebuild() -> void:
	if _keeper == null or not is_instance_valid(_keeper):
		return
	var state := _player_state()
	_merchant_gold.text = "%d g" % _keeper.gold
	_player_gold.text = "%d g" % (state.gold if state else 0)

	_build_stock_rows()
	_build_bag_rows()
	_refresh_buttons()
	_status_label.text = _status
	_status = ""


func _build_stock_rows() -> void:
	_clear(_stock_list)
	var state := _player_state()
	var gold := state.gold if state else 0
	var wares := _keeper.wares()
	if wares.is_empty():
		_stock_list.add_child(_make_empty_notice("Sold out."))
	_stock_index = mini(_stock_index, wares.size() - 1)
	for i in wares.size():
		var entry := wares[i]
		var price := _keeper.buy_price(entry)
		_add_row(_stock_list, entry, i, price, gold >= price, TradeSide.MERCHANT, i == _stock_index)


func _build_bag_rows() -> void:
	_clear(_bag_list)
	var inventory := _inventory()
	if inventory == null:
		return
	var any := false
	# Rows are keyed by BACKPACK INDEX, not by position in the list -- empty slots
	# are skipped for display but a sale still names the exact stack it came from.
	for i in inventory.backpack.size():
		var entry := inventory.slot(i)
		if entry == null:
			continue
		any = true
		var sellable := _keeper.will_buy(entry)
		var price := _keeper.sell_price(entry) if sellable else 0
		_add_row(_bag_list, entry, i, price, sellable, TradeSide.PLAYER, i == _bag_index)
	if not any:
		_bag_list.add_child(_make_empty_notice("Your pack is empty."))
		_bag_index = -1


func _add_row(list: VBoxContainer, entry: InventoryItem, index: int, price: int,
		tradeable: bool, side: TradeSide, is_selected: bool) -> void:
	var row := ShopRow.new()
	list.add_child(row)
	row.set_entry(entry, index, price, tradeable)
	row.set_selected(is_selected)
	row.hovered.connect(_on_row_hovered)
	row.unhovered.connect(_on_row_unhovered)
	row.selected.connect(_on_row_selected.bind(side))
	row.activated.connect(_on_row_activated.bind(side))


func _make_empty_notice(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.5, 0.48, 0.45))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _clear(list: VBoxContainer) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()


## Button labels quote the actual total, so the price is known before committing.
func _refresh_buttons() -> void:
	var stock_entry := _selected_ware()
	var buy_price := _keeper.buy_price(stock_entry) if stock_entry else 0
	_buy_button.disabled = stock_entry == null or not _can_afford(buy_price)
	_buy_button.text = "Buy  —  %d g" % buy_price if stock_entry else "Buy"
	var stock_count := stock_entry.stack_count if stock_entry else 0
	_buy_all_button.visible = stock_count > 1 and not _keeper.infinite_stock
	_buy_all_button.disabled = not _can_afford(buy_price * stock_count)
	_buy_all_button.text = "Buy x%d  —  %d g" % [stock_count, buy_price * stock_count]

	var bag_entry := _selected_bag_item()
	var sellable := bag_entry != null and _keeper.will_buy(bag_entry)
	var sell_price := _keeper.sell_price(bag_entry) if sellable else 0
	_sell_button.disabled = not sellable or _keeper.gold < sell_price
	_sell_button.text = "Sell  —  %d g" % sell_price if sellable else "Sell"
	var bag_count := bag_entry.stack_count if bag_entry else 0
	_sell_all_button.visible = sellable and bag_count > 1
	_sell_all_button.disabled = _keeper.gold < sell_price * bag_count
	_sell_all_button.text = "Sell x%d  —  %d g" % [bag_count, sell_price * bag_count]


func _can_afford(price: int) -> bool:
	var state := _player_state()
	return state != null and state.gold >= price


func _selected_ware() -> InventoryItem:
	if _keeper == null:
		return null
	var wares := _keeper.wares()
	return wares[_stock_index] if _stock_index >= 0 and _stock_index < wares.size() else null


func _selected_bag_item() -> InventoryItem:
	var inventory := _inventory()
	return inventory.slot(_bag_index) if inventory else null


# --- Interaction ---------------------------------------------------------------

func _on_row_hovered(row: ShopRow) -> void:
	if row.item:
		_tooltip.show_item(row.item)


func _on_row_unhovered() -> void:
	_tooltip.hide_tooltip()


## Selection is per side, so the two panels can hold a highlight each.
func _on_row_selected(row: ShopRow, side: TradeSide) -> void:
	if side == TradeSide.MERCHANT:
		_stock_index = row.source_index
	else:
		_bag_index = row.source_index
	for child in (_stock_list if side == TradeSide.MERCHANT else _bag_list).get_children():
		if child is ShopRow:
			child.set_selected(child == row)
	_refresh_buttons()


func _on_row_activated(row: ShopRow, side: TradeSide) -> void:
	_on_row_selected(row, side)
	if side == TradeSide.MERCHANT:
		_on_buy(1)
	else:
		_on_sell(1)


## `count` of -1 means the whole selected stack.
func _on_buy(count: int) -> void:
	var entry := _selected_ware()
	if _keeper == null or entry == null:
		return
	_status = _keeper.player_buy(_stock_index, entry.stack_count if count < 0 else count)
	# player_buy already emits stock_changed on success, which rebuilds; a refusal
	# changes nothing, so rebuild here to surface the reason.
	if _status != "":
		_rebuild()


func _on_sell(count: int) -> void:
	var entry := _selected_bag_item()
	if _keeper == null or entry == null:
		return
	_status = _keeper.player_sell(_bag_index, entry.stack_count if count < 0 else count)
	if _status != "":
		_rebuild()


func _inventory() -> PlayerInventorySystem:
	return get_node_or_null("/root/PlayerInventory") as PlayerInventorySystem


func _player_state() -> PlayerStateSystem:
	return get_node_or_null("/root/PlayerState") as PlayerStateSystem
