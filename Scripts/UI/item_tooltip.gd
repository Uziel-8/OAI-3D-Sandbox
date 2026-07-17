class_name ItemTooltip
extends PanelContainer
## Floating tooltip that follows the mouse while an inventory/equipment slot is hovered.

@onready var _name_label: Label = %NameLabel
@onready var _type_label: Label = %TypeLabel
@onready var _desc_label: Label = %DescLabel
@onready var _stats_label: Label = %StatsLabel
@onready var _footer_label: Label = %FooterLabel

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	hide()

func _process(_delta: float) -> void:
	if visible:
		_follow_mouse()

func show_item(item: InventoryItem) -> void:
	var type_str := InventoryItem.rarity_name(item.rarity)
	if item.equip_slot != InventoryItem.EquipSlot.NONE:
		type_str += "  •  " + InventoryItem.equip_slot_name(item.equip_slot)

	var lines: Array[String] = []
	for stat_key in item.stat_bonuses.keys():
		var stat_val = item.stat_bonuses[stat_key]
		var sign_str := "+" if stat_val >= 0 else ""
		lines.append("%s %s%s" % [stat_key, sign_str, str(stat_val)])

	var footer := "Weight %.1f" % item.weight
	if item.value > 0:
		footer += "   Value %d" % item.value
	if item.max_stack > 1:
		footer += "   x%d" % item.stack_count

	show_info(item.item_name, InventoryItem.rarity_color(item.rarity), type_str, item.description, lines, footer)

func show_spell(spell: SpellDefinition) -> void:
	var type_str := "%d Mana" % spell.mana_cost if spell.mana_cost > 0 else "No Mana Cost"
	var footer := "Cooldown %.1fs" % spell.cooldown if spell.cooldown > 0.0 else ""
	show_info(spell.spell_name, spell.icon_color, type_str, spell.description, [], footer)

## Shared renderer behind show_item()/show_spell() -- keeps the tooltip decoupled
## from any one data shape (duck typing over a shared base class, same convention
## the Magic spells use for apply_impulse()).
func show_info(title: String, title_color: Color, subtitle: String, description: String,
		extra_lines: Array[String], footer: String) -> void:
	_name_label.text = title
	_name_label.add_theme_color_override("font_color", title_color)
	_type_label.text = subtitle
	_desc_label.text = description
	_desc_label.visible = not description.is_empty()
	if extra_lines.size() > 0:
		_stats_label.text = "\n".join(extra_lines)
		_stats_label.visible = true
	else:
		_stats_label.visible = false
	_footer_label.text = footer
	_footer_label.visible = not footer.is_empty()

	reset_size()
	show()
	_follow_mouse()

func hide_tooltip() -> void:
	hide()

func _follow_mouse() -> void:
	var vp_size := get_viewport_rect().size
	var mouse_pos := get_viewport().get_mouse_position()
	var pos := mouse_pos + Vector2(20, 20)
	if pos.x + size.x > vp_size.x:
		pos.x = mouse_pos.x - size.x - 20
	if pos.y + size.y > vp_size.y:
		pos.y = mouse_pos.y - size.y - 20
	global_position = pos
