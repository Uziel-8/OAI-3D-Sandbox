class_name SpellSlot
extends PanelContainer
## One socket in the spellbook tab. Loadout slots (is_loadout_slot = true) are
## one of the four live hotbar bindings (cast_primary/cast_secondary/spell_slot_3/
## spell_slot_4) and can be dragged into, out of, and between. Palette slots
## ("known spells" you drag FROM) are read-only and never lose their spell --
## equipping is a copy, not a move, since knowing a spell isn't consumed by
## assigning it to a key.

signal spell_changed(slot: SpellSlot)
signal slot_hovered(slot: SpellSlot)
signal slot_unhovered

@export var is_loadout_slot: bool = false
## Which input action this socket drives, e.g. "cast_primary". Only meaningful
## when is_loadout_slot is true.
@export var trigger_action: String = ""
@export var empty_glyph: String = ""

var spell: SpellDefinition = null

@onready var _icon_bg: Panel = %IconBg
@onready var _icon_label: Label = %IconLabel
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

	_empty_label.text = empty_glyph if is_loadout_slot else ""
	_update_visual()

func set_spell(new_spell: SpellDefinition) -> void:
	spell = new_spell
	_update_visual()
	spell_changed.emit(self)

func clear_spell() -> SpellDefinition:
	var old := spell
	spell = null
	_update_visual()
	spell_changed.emit(self)
	return old

func _update_visual() -> void:
	if spell:
		_icon_label.text = spell.icon_text()
		_icon_bg.self_modulate = spell.icon_color
		_icon_bg.visible = true
		_empty_label.visible = false
		_style.border_color = spell.icon_color
	else:
		_icon_label.text = ""
		_icon_bg.visible = false
		_empty_label.visible = is_loadout_slot
		_style.border_color = Color(0.78, 0.62, 0.32, 0.5) if is_loadout_slot else Color(1, 1, 1, 0.1)
	_apply_hover()

func _apply_hover() -> void:
	var w := 3 if _hovering else 2
	_style.border_width_top = w
	_style.border_width_bottom = w
	_style.border_width_left = w
	_style.border_width_right = w
	_style.bg_color = Color(0.17, 0.16, 0.18, 1.0) if _hovering else Color(0.12, 0.11, 0.13, 1.0)

func _on_mouse_entered() -> void:
	_hovering = true
	_apply_hover()
	slot_hovered.emit(self)

func _on_mouse_exited() -> void:
	_hovering = false
	_apply_hover()
	slot_unhovered.emit()

## Double-click a loadout slot to clear it -- unlike unequipping an item, this
## needs no coordination with the screen: the palette isn't consumed by
## equipping, so there's nothing to hand the spell back to.
func _on_gui_input(event: InputEvent) -> void:
	if is_loadout_slot and event is InputEventMouseButton and event.pressed and event.double_click \
			and event.button_index == MOUSE_BUTTON_LEFT and spell != null:
		clear_spell()

func _get_drag_data(_at_position: Vector2) -> Variant:
	if spell == null:
		return null
	set_drag_preview(_make_drag_preview())
	return {"spell": spell, "source": self}

func _make_drag_preview() -> Control:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = spell.icon_color
	style.set_corner_radius_all(6)
	box.add_theme_stylebox_override("panel", style)
	box.custom_minimum_size = Vector2(56, 56)
	box.modulate.a = 0.85
	var label := Label.new()
	label.text = spell.icon_text()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	box.add_child(label)
	return box

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not is_loadout_slot:
		return false  # the known-spells palette is read-only
	if typeof(data) != TYPE_DICTIONARY or not data.has("spell"):
		return false
	return data["source"] != self

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var source: SpellSlot = data["source"]
	var incoming: SpellDefinition = data["spell"]
	if source.is_loadout_slot:
		var outgoing := spell
		set_spell(incoming)
		source.set_spell(outgoing)
	else:
		set_spell(incoming)  # palette source keeps its own copy, nothing to swap back
