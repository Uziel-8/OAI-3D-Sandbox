class_name InventorySlot
extends PanelContainer
## A single slot in the item grid or a socket on the equipment paper doll.
## Supports drag-and-drop between any two compatible slots and double-click quick equip/unequip.

signal item_changed
signal slot_hovered(slot: InventorySlot)
signal slot_unhovered

## If true, this slot only accepts items whose equip_slot matches accepted_equip_slot.
@export var is_equipment_slot: bool = false
@export var accepted_equip_slot: InventoryItem.EquipSlot = InventoryItem.EquipSlot.NONE
## Empty-socket glyph shown on equipment slots before anything is worn there.
@export var empty_glyph: String = ""

var item: InventoryItem = null

@onready var _icon_bg: Panel = %IconBg
@onready var _icon_label: Label = %IconLabel
@onready var _count_label: Label = %CountLabel
@onready var _empty_label: Label = %EmptyLabel

var _style: StyleBoxFlat
var _hovering := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.12, 0.11, 0.13, 1.0)
	_style.set_corner_radius_all(6)
	_style.set_border_width_all(2)
	_style.border_color = Color(1, 1, 1, 0.12)
	add_theme_stylebox_override("panel", _style)

	_empty_label.text = empty_glyph if is_equipment_slot else ""
	_update_visual()

func set_item(new_item: InventoryItem) -> void:
	item = new_item
	_update_visual()
	item_changed.emit()

func clear_item() -> InventoryItem:
	var old := item
	item = null
	_update_visual()
	item_changed.emit()
	return old

func accepts(candidate: InventoryItem) -> bool:
	if candidate == null:
		return true
	if is_equipment_slot:
		return candidate.equip_slot == accepted_equip_slot
	return true

func _update_visual() -> void:
	if item:
		_icon_label.text = item.icon_text()
		_icon_bg.self_modulate = item.icon_color
		_icon_bg.visible = true
		_empty_label.visible = false
		_count_label.visible = item.max_stack > 1 and item.stack_count > 1
		_count_label.text = str(item.stack_count)
		_style.border_color = InventoryItem.rarity_color(item.rarity)
	else:
		_icon_label.text = ""
		_icon_bg.visible = false
		_empty_label.visible = is_equipment_slot
		_count_label.visible = false
		_style.border_color = Color(0.78, 0.62, 0.32, 0.5) if is_equipment_slot else Color(1, 1, 1, 0.1)
	_apply_hover()

func _apply_hover() -> void:
	_style.border_width_top = 3 if _hovering else 2
	_style.border_width_bottom = 3 if _hovering else 2
	_style.border_width_left = 3 if _hovering else 2
	_style.border_width_right = 3 if _hovering else 2
	_style.bg_color = Color(0.17, 0.16, 0.18, 1.0) if _hovering else Color(0.12, 0.11, 0.13, 1.0)

func _on_mouse_entered() -> void:
	_hovering = true
	_apply_hover()
	slot_hovered.emit(self)

func _on_mouse_exited() -> void:
	_hovering = false
	_apply_hover()
	slot_unhovered.emit()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.double_click \
			and event.button_index == MOUSE_BUTTON_LEFT and item != null:
		_quick_transfer()

## Double-click: send equipment back to the grid, or send a wearable item to its socket.
func _quick_transfer() -> void:
	var screen := get_tree().get_first_node_in_group("inventory_screen")
	if screen and screen.has_method("quick_transfer"):
		screen.quick_transfer(self)

func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null:
		return null
	var preview := _make_drag_preview()
	set_drag_preview(preview)
	return {"item": item, "source": self}

func _make_drag_preview() -> Control:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = item.icon_color
	style.set_corner_radius_all(6)
	box.add_theme_stylebox_override("panel", style)
	box.custom_minimum_size = Vector2(56, 56)
	box.modulate.a = 0.85
	var label := Label.new()
	label.text = item.icon_text()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	box.add_child(label)
	return box

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("item"):
		return false
	var source: InventorySlot = data["source"]
	if source == self:
		return false
	return accepts(data["item"])

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var source: InventorySlot = data["source"]
	var incoming: InventoryItem = data["item"]
	var outgoing := item
	# Block the swap if what would land back in the source slot doesn't belong there.
	if not source.accepts(outgoing):
		return
	set_item(incoming)
	source.set_item(outgoing)
	_notify_screen()

func _notify_screen() -> void:
	var screen := get_tree().get_first_node_in_group("inventory_screen")
	if screen and screen.has_method("on_inventory_changed"):
		screen.on_inventory_changed()
