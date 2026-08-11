extends PanelContainer
class_name ShopRow
## One line in either half of the shop screen: an item, how many, and what it
## trades for. A price-bearing list reads better than a grid here, so this is a
## row rather than a reused InventorySlot -- and reusing InventorySlot would also
## have dragged in its drag/drop and its double-click quick-equip, which routes to
## the inventory screen by group and would fire on a shop click.
##
## Built entirely in code with no .tscn, like HudSpellSlot, for the same reason:
## the contents are data-driven and it keeps the stale-`parent=` NodePath hazard
## documented in CLAUDE.md out of another scene file.

signal hovered(row: ShopRow)
signal unhovered
signal selected(row: ShopRow)
## Double-click -- transacts immediately, same as pressing the panel's action button.
signal activated(row: ShopRow)

const _BG := Color(0.10, 0.095, 0.11, 1.0)
const _BG_HOVER := Color(0.15, 0.14, 0.16, 1.0)
const _BG_SELECTED := Color(0.20, 0.17, 0.12, 1.0)

var item: InventoryItem = null
## Index into whichever list this row came from -- the merchant's stock or the
## player's backpack. What the transaction methods are keyed on.
var source_index: int = -1
## Unit price in this direction of trade.
var price: int = 0
## False greys the row out: unaffordable to buy, or something he won't take.
var tradeable: bool = true

var _style: StyleBoxFlat
var _icon_bg: Panel
var _icon_label: Label
var _name_label: Label
var _sub_label: Label
var _count_label: Label
var _price_label: Label
var _hovering := false
var _is_selected := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, 46)


func _ready() -> void:
	_style = StyleBoxFlat.new()
	_style.bg_color = _BG
	_style.set_corner_radius_all(5)
	_style.set_border_width_all(2)
	_style.border_color = Color(1, 1, 1, 0.08)
	_style.content_margin_left = 8.0
	_style.content_margin_right = 10.0
	_style.content_margin_top = 4.0
	_style.content_margin_bottom = 4.0
	add_theme_stylebox_override("panel", _style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	_icon_bg = Panel.new()
	_icon_bg.custom_minimum_size = Vector2(34, 34)
	_icon_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color(1, 1, 1)
	icon_style.set_corner_radius_all(5)
	_icon_bg.add_theme_stylebox_override("panel", icon_style)
	row.add_child(_icon_bg)

	_icon_label = _make_label(14, Color(0.06, 0.06, 0.07))
	_icon_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon_bg.add_child(_icon_label)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.add_theme_constant_override("separation", 0)
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_box)

	_name_label = _make_label(15, Color(0.9, 0.88, 0.84))
	text_box.add_child(_name_label)
	_sub_label = _make_label(11, Color(0.6, 0.57, 0.54))
	text_box.add_child(_sub_label)

	_count_label = _make_label(13, Color(0.68, 0.65, 0.62))
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_count_label.custom_minimum_size = Vector2(46, 0)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_count_label)

	_price_label = _make_label(15, Color(0.85, 0.72, 0.32))
	_price_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_price_label.custom_minimum_size = Vector2(78, 0)
	_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_price_label)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	_refresh()


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Fills the row in. Called once by the screen right after instancing, before the
## node is ready, so the visual pass is deferred to _refresh().
func set_entry(entry: InventoryItem, index: int, unit_price: int, can_trade: bool) -> void:
	item = entry
	source_index = index
	price = unit_price
	tradeable = can_trade
	if is_node_ready():
		_refresh()


func set_selected(value: bool) -> void:
	_is_selected = value
	if is_node_ready():
		_apply_background()


func _refresh() -> void:
	if item == null:
		return
	_icon_label.text = item.icon_text()
	_icon_bg.self_modulate = item.icon_color
	_name_label.text = item.item_name
	_name_label.add_theme_color_override("font_color", InventoryItem.rarity_color(item.rarity))

	var sub := InventoryItem.rarity_name(item.rarity)
	var equip_name := InventoryItem.equip_slot_name(item.equip_slot)
	if equip_name != "":
		sub += "  •  " + equip_name
	_sub_label.text = sub

	_count_label.text = "x%d" % item.stack_count if item.stack_count > 1 else ""
	_price_label.text = "%d g" % price if tradeable else "—"
	_price_label.add_theme_color_override("font_color",
		Color(0.85, 0.72, 0.32) if tradeable else Color(0.55, 0.4, 0.4))
	modulate.a = 1.0 if tradeable else 0.5
	_apply_background()


func _apply_background() -> void:
	if _is_selected:
		_style.bg_color = _BG_SELECTED
		_style.border_color = Color(0.78, 0.62, 0.32, 0.85)
	elif _hovering:
		_style.bg_color = _BG_HOVER
		_style.border_color = Color(1, 1, 1, 0.2)
	else:
		_style.bg_color = _BG
		_style.border_color = Color(1, 1, 1, 0.08)


func _on_mouse_entered() -> void:
	_hovering = true
	_apply_background()
	hovered.emit(self)


func _on_mouse_exited() -> void:
	_hovering = false
	_apply_background()
	unhovered.emit()


func _on_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	selected.emit(self)
	if event.double_click:
		activated.emit(self)
	accept_event()
