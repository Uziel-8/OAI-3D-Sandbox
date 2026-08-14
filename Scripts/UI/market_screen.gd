class_name MarketScreen
extends Control
## The guild's commodity board: every good with its price and your position on the
## left, the news that moved them on the right. Opened by a TradeExchange (normally
## through a dialogue choice with `opens_market` set) and registered as the
## `MarketUI` autoload.
##
## Follows every menu-screen convention -- backdrop, shared theme, pause + mouse
## release, process_mode ALWAYS, HUD hide, mutual exclusion via group "menu_screen".
## Like DialogueScreen/ShopScreen the script sits on the autoload's `Screen` child,
## so it's found by GROUP ("market_screen"), NOT by /root/MarketUI.
##
## It's a VIEW and nothing more: every price, limit and refusal comes from the
## TradeExchange, exactly as ShopScreen defers to its ShopKeeper. This file only
## decides what's on screen and which row is selected.

@onready var _title: Label = %ExchangeTitle
@onready var _day_label: Label = %DayLabel
@onready var _close_button: Button = %CloseButton
@onready var _player_gold: Label = %PlayerGold
@onready var _limit_label: Label = %LimitLabel
@onready var _heat_bar: ProgressBar = %HeatBar
@onready var _heat_label: Label = %HeatLabel
@onready var _board_list: VBoxContainer = %BoardList
@onready var _news_list: VBoxContainer = %NewsList
@onready var _detail_label: RichTextLabel = %DetailLabel
@onready var _buy_button: Button = %BuyButton
@onready var _buy_five_button: Button = %BuyFiveButton
@onready var _buy_max_button: Button = %BuyMaxButton
@onready var _sell_button: Button = %SellButton
@onready var _sell_five_button: Button = %SellFiveButton
@onready var _sell_all_button: Button = %SellAllButton
@onready var _status_label: Label = %StatusLabel

var is_open := false

var _exchange: TradeExchange = null
## Id of the selected commodity, or empty for no selection.
var _selected: StringName = &""
## Cleared on the next rebuild, so a refusal doesn't linger past the trade that
## caused it.
var _status := ""


func _ready() -> void:
	add_to_group("menu_screen")
	add_to_group("market_screen")
	visible = false
	_close_button.pressed.connect(close)
	_buy_button.pressed.connect(_on_buy.bind(1))
	_buy_five_button.pressed.connect(_on_buy.bind(5))
	_buy_max_button.pressed.connect(_on_buy.bind(-1))
	_sell_button.pressed.connect(_on_sell.bind(1))
	_sell_five_button.pressed.connect(_on_sell.bind(5))
	_sell_all_button.pressed.connect(_on_sell.bind(-1))

	var state := _player_state()
	if state:
		state.gold_changed.connect(_on_world_changed.unbind(1))
	var market := _market()
	if market:
		market.board_changed.connect(_on_world_changed)
		market.holdings_changed.connect(_on_world_changed.unbind(2))
		market.heat_changed.connect(_on_world_changed.unbind(2))


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	# Registered late among the UI autoloads, so this sees input before the
	# inventory/journal and can swallow their toggles while the board is up.
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("inventory") \
			or event.is_action_pressed("journal"):
		close()
		get_viewport().set_input_as_handled()


## Opens the board for `exchange`. The only entry point -- no toggle key, since a
## broker is something you walk up to.
func open(exchange: TradeExchange) -> void:
	if exchange == null:
		return
	_close_other_menus()
	if _exchange and is_instance_valid(_exchange) and _exchange != exchange \
			and _exchange.ledger_changed.is_connected(_on_world_changed):
		_exchange.ledger_changed.disconnect(_on_world_changed)
	_exchange = exchange
	if not exchange.ledger_changed.is_connected(_on_world_changed):
		exchange.ledger_changed.connect(_on_world_changed)

	_status = ""
	if String(_selected).is_empty():
		var market := _market()
		var board := market.commodities() if market else []
		if not board.is_empty():
			_selected = board[0].id
	is_open = true
	visible = true
	_title.text = exchange.display_name().to_upper()
	_rebuild()
	_set_hud_visible(false)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	is_open = false
	visible = false
	if _exchange and is_instance_valid(_exchange) and _exchange.ledger_changed.is_connected(_on_world_changed):
		_exchange.ledger_changed.disconnect(_on_world_changed)
	_exchange = null
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


func _on_world_changed() -> void:
	if is_open:
		_rebuild()


# --- Rendering -----------------------------------------------------------------

func _rebuild() -> void:
	if _exchange == null or not is_instance_valid(_exchange):
		return
	var market := _market()
	var state := _player_state()
	var clock := _clock()
	_player_gold.text = "%d g" % (state.gold if state else 0)
	_day_label.text = clock.date_text() if clock else ""
	_limit_label.text = "Position limit: %d per commodity" % _exchange.position_limit()

	_build_board_rows()
	_build_news_rows()
	_refresh_heat()
	_refresh_detail()
	_refresh_buttons()
	_status_label.text = _status
	_status = ""
	if market and market.is_barred():
		_status_label.text = "Your trading privileges are suspended until day %d." % market.barred_until_day


func _build_board_rows() -> void:
	_clear(_board_list)
	var market := _market()
	if market == null:
		return
	for entry in market.commodities():
		var row := MarketRow.new()
		_board_list.add_child(row)
		row.set_entry(entry, _exchange.ask_price(entry.id), market.price_delta_percent(entry.id),
			market.holdings(entry.id), market.unrealised_profit(entry.id))
		row.set_selected(entry.id == _selected)
		row.selected.connect(_on_row_selected)
		row.activated.connect(_on_row_activated)


func _build_news_rows() -> void:
	_clear(_news_list)
	var market := _market()
	if market == null:
		return

	var rumours := market.rumours()
	if not rumours.is_empty():
		_news_list.add_child(_make_heading("WHAT'S BEING SAID"))
		for rumour in rumours:
			var hint := _make_body(rumour, Color(0.72, 0.68, 0.88))
			_news_list.add_child(hint)

	var entries := market.news()
	_news_list.add_child(_make_heading("THE BOARD" if rumours.is_empty() else "\nTHE BOARD"))
	if entries.is_empty():
		_news_list.add_child(_make_body("Nothing has moved. A quiet season.", Color(0.5, 0.48, 0.45)))
		return
	for entry in entries:
		var headline := Label.new()
		var day: int = int(entry.get("day", 0))
		headline.text = "Day %d  —  %s" % [day, entry.get("headline", "")]
		headline.add_theme_font_size_override("font_size", 13)
		var magnitude: float = float(entry.get("magnitude", 0.0))
		headline.add_theme_color_override("font_color",
			Color(0.55, 0.80, 0.55) if magnitude > 0.0 else Color(0.88, 0.45, 0.40))
		headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_news_list.add_child(headline)

		var detail: String = str(entry.get("detail", ""))
		if entry.get("player_caused", false):
			# Named plainly, because it's what the guild is looking at too.
			detail += "  [Your doing.]" if detail.is_empty() else "\n[Your doing.]"
		if not detail.is_empty():
			_news_list.add_child(_make_body(detail, Color(0.62, 0.60, 0.57)))


func _make_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.72, 0.68, 0.62))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_body(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## The guild's suspicion, shown plainly. Hiding it would make the penalties feel
## arbitrary rather than earned.
func _refresh_heat() -> void:
	var market := _market()
	if market == null:
		return
	_heat_bar.max_value = MarketSystem.HEAT_MAX
	_heat_bar.value = market.heat
	var level := market.heat_level()
	var text := "Guild scrutiny: none"
	match level:
		1:
			text = "Guild scrutiny: they're watching your ledger"
		2:
			text = "Guild scrutiny: under investigation"
		3:
			text = "Guild scrutiny: suspended"
	_heat_label.text = text
	_heat_label.add_theme_color_override("font_color",
		Color(0.62, 0.60, 0.57) if level == 0 else Color(0.90, 0.62, 0.35))


func _refresh_detail() -> void:
	var market := _market()
	var c: Commodity = market.commodity(_selected) if market else null
	if c == null:
		_detail_label.text = ""
		return
	var lines: Array[String] = []
	lines.append("[b]%s[/b]   %s" % [c.display_name, c.description])
	lines.append("Buy at [color=#d9b852]%d g[/color]   •   Sell at [color=#d9b852]%d g[/color]"
		% [_exchange.ask_price(c.id), _exchange.bid_price(c.id)])
	var held := market.holdings(c.id)
	if held > 0:
		var profit := market.unrealised_profit(c.id)
		var colour := "#8ccc8c" if profit >= 0 else "#e07369"
		lines.append("Holding %d at %.1f g average   •   [color=%s]%+d g open[/color]"
			% [held, market.average_cost(c.id), colour, profit])
	var effects := market.effects_for(c.id)
	for effect in effects:
		lines.append("[i]%s — %d day%s left[/i]" % [effect["headline"], effect["days_left"],
			"" if int(effect["days_left"]) == 1 else "s"])
	_detail_label.text = "\n".join(lines)


func _refresh_buttons() -> void:
	var market := _market()
	if market == null or String(_selected).is_empty():
		for button in [_buy_button, _buy_five_button, _buy_max_button,
				_sell_button, _sell_five_button, _sell_all_button]:
			button.disabled = true
		return

	var ask := _exchange.ask_price(_selected)
	var bid := _exchange.bid_price(_selected)
	var room := _exchange.room_to_buy(_selected)
	var held := market.holdings(_selected)
	var barred := market.is_barred()

	_buy_button.text = "Buy 1  —  %d g" % ask
	_buy_button.disabled = barred or room < 1
	_buy_five_button.text = "Buy 5  —  %d g" % (ask * 5)
	_buy_five_button.disabled = barred or room < 5
	_buy_max_button.text = "Buy %d  —  %d g" % [room, ask * room]
	_buy_max_button.visible = room > 1
	_buy_max_button.disabled = barred or room < 1

	_sell_button.text = "Sell 1  —  %d g" % bid
	_sell_button.disabled = barred or held < 1
	_sell_five_button.text = "Sell 5  —  %d g" % (bid * 5)
	_sell_five_button.disabled = barred or held < 5
	_sell_all_button.text = "Sell %d  —  %d g" % [held, bid * held]
	_sell_all_button.visible = held > 1
	_sell_all_button.disabled = barred or held < 1


func _clear(list: VBoxContainer) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()


# --- Interaction ---------------------------------------------------------------

func _on_row_selected(row: MarketRow) -> void:
	if row.commodity == null:
		return
	_selected = row.commodity.id
	for child in _board_list.get_children():
		if child is MarketRow:
			child.set_selected(child == row)
	_refresh_detail()
	_refresh_buttons()


func _on_row_activated(row: MarketRow) -> void:
	_on_row_selected(row)
	_on_buy(1)


## `count` of -1 means as many as the limit and the purse allow.
func _on_buy(count: int) -> void:
	if _exchange == null or String(_selected).is_empty():
		return
	var units := _exchange.room_to_buy(_selected) if count < 0 else count
	_status = _exchange.player_buy(_selected, units)
	# A successful trade emits ledger_changed, which rebuilds; a refusal changes
	# nothing, so rebuild here to surface the reason.
	if _status != "":
		_rebuild()


## `count` of -1 means the whole position.
func _on_sell(count: int) -> void:
	var market := _market()
	if _exchange == null or market == null or String(_selected).is_empty():
		return
	var units := market.holdings(_selected) if count < 0 else count
	_status = _exchange.player_sell(_selected, units)
	if _status != "":
		_rebuild()


func _market() -> MarketSystem:
	return get_node_or_null("/root/Market") as MarketSystem


func _player_state() -> PlayerStateSystem:
	return get_node_or_null("/root/PlayerState") as PlayerStateSystem


func _clock() -> WorldClockSystem:
	return get_node_or_null("/root/WorldClock") as WorldClockSystem
