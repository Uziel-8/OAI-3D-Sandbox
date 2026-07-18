class_name InventoryScreen
extends Control
## Top-level controller for the inventory/character screen: builds the backpack grid,
## wires the paper-doll equipment sockets, and drives the tooltip + carry-weight readout.
## Item data is mock/placeholder (see MockItemDatabase) until a real item/save system exists.

const GRID_COLUMNS := 8
const GRID_ROWS := 5
const CARRY_CAPACITY := 60.0

const SlotScene := preload("res://Scenes/UI/inventory_slot.tscn")
const SpellSlotScene := preload("res://Scenes/UI/spell_slot.tscn")

## NOTE: nodes that are themselves PackedScene instances (InventorySlot/SpellSlot/
## ItemTooltip) are looked up by explicit $path, not %unique_name, per the
## Godot 4.7.1 gotcha in CLAUDE.md. Plain built-in node types use %unique_name
## as normal. (A "vanished parent" cascade hit this file once before -- that
## turned out to be a stale parent= path left over from wrapping Header/Tabs
## in a new Layout container, not an engine bug. Verify paths against actual
## node nesting before assuming unique_name_in_owner is at fault again.)
const _CHAR_PATH := "Center/Frame/Layout/Tabs/Inventory/CharacterPanel/CharVBox/PaperDollCenter/PaperDoll/"
const _SPELL_PATH := "Center/Frame/Layout/Tabs/Spellbook/LoadoutPanel/LoadoutVBox/"

@onready var _item_grid: GridContainer = %ItemGrid
@onready var _weight_bar: ProgressBar = %WeightBar
@onready var _weight_label: Label = %WeightLabel
@onready var _armor_value_label: Label = %ArmorValueLabel
@onready var _close_button: Button = %CloseButton
@onready var _spell_grid: GridContainer = %SpellGrid

@onready var _level_label: Label = %LevelLabel
@onready var _xp_bar: ProgressBar = %XPBar
@onready var _xp_label: Label = %XPLabel
@onready var _points_label: Label = %PointsLabel
@onready var _attributes_grid: GridContainer = %Attributes
@onready var _cs_health_bar: ProgressBar = %HealthBar
@onready var _cs_mana_bar: ProgressBar = %ManaBar
@onready var _cs_stamina_bar: ProgressBar = %StaminaBar

@onready var _tooltip: ItemTooltip = $Tooltip

@onready var _head_slot: InventorySlot = get_node(_CHAR_PATH + "HeadSlot")
@onready var _chest_slot: InventorySlot = get_node(_CHAR_PATH + "ChestSlot")
@onready var _legs_slot: InventorySlot = get_node(_CHAR_PATH + "LegsSlot")
@onready var _boots_slot: InventorySlot = get_node(_CHAR_PATH + "BootsSlot")
@onready var _hands_slot: InventorySlot = get_node(_CHAR_PATH + "HandsSlot")
@onready var _main_hand_slot: InventorySlot = get_node(_CHAR_PATH + "MainHandSlot")
@onready var _off_hand_slot: InventorySlot = get_node(_CHAR_PATH + "OffHandSlot")
@onready var _amulet_slot: InventorySlot = get_node(_CHAR_PATH + "AmuletSlot")
@onready var _ring_slot: InventorySlot = get_node(_CHAR_PATH + "RingSlot")

@onready var _primary_slot: SpellSlot = get_node(_SPELL_PATH + "PrimaryRow/PrimarySlot")
@onready var _secondary_slot: SpellSlot = get_node(_SPELL_PATH + "SecondaryRow/SecondarySlot")
@onready var _slot3_slot: SpellSlot = get_node(_SPELL_PATH + "Slot3Row/Slot3Slot")
@onready var _slot4_slot: SpellSlot = get_node(_SPELL_PATH + "Slot4Row/Slot4Slot")

var is_open := false
var _grid_slots: Array[InventorySlot] = []

func _ready() -> void:
	add_to_group("inventory_screen")
	visible = false
	_close_button.pressed.connect(close)
	_build_grid()
	_connect_equipment_slots()
	_populate_mock_data()
	on_inventory_changed()
	_populate_spellbook()
	_connect_loadout_slots()
	_setup_progression()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

func open() -> void:
	is_open = true
	visible = true
	_refresh_character_stats()
	_refresh_progression()
	_set_hud_visible(false)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	is_open = false
	visible = false
	_tooltip.hide_tooltip()
	_set_hud_visible(true)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _set_hud_visible(shown: bool) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hud_visible"):
		hud.set_hud_visible(shown)

## Pulls the character-sheet vitals from the real sources (player DamageReceiver
## for health, PlayerState for mana/stamina). Called on open; values can't change
## while the sheet is up since opening pauses the tree.
func _refresh_character_stats() -> void:
	var receiver := get_tree().get_first_node_in_group("player_health") as DamageReceiver
	if receiver:
		_cs_health_bar.max_value = receiver.max_health
		_cs_health_bar.value = receiver.health
	var state := get_node_or_null("/root/PlayerState")
	if state:
		_cs_mana_bar.max_value = state.max_mana
		_cs_mana_bar.value = state.mana
		_cs_stamina_bar.max_value = state.max_stamina
		_cs_stamina_bar.value = state.stamina

func _build_grid() -> void:
	for i in range(GRID_COLUMNS * GRID_ROWS):
		var slot := SlotScene.instantiate() as InventorySlot
		_item_grid.add_child(slot)
		_grid_slots.append(slot)
		slot.slot_hovered.connect(_on_slot_hovered)
		slot.slot_unhovered.connect(_on_slot_unhovered)
		slot.item_changed.connect(on_inventory_changed)

func _connect_equipment_slots() -> void:
	for slot in _equipment_slots():
		slot.slot_hovered.connect(_on_slot_hovered)
		slot.slot_unhovered.connect(_on_slot_unhovered)
		slot.item_changed.connect(on_inventory_changed)

func _equipment_slots() -> Array[InventorySlot]:
	return [_head_slot, _chest_slot, _legs_slot, _boots_slot, _hands_slot,
		_main_hand_slot, _off_hand_slot, _amulet_slot, _ring_slot]

func _populate_mock_data() -> void:
	var equipped := MockItemDatabase.make_starting_equipment()
	for equip_slot_enum in equipped.keys():
		var node := _equipment_slot_for(equip_slot_enum)
		if node:
			node.set_item(equipped[equip_slot_enum])
	var pool := MockItemDatabase.make_starting_inventory()
	for i in range(mini(pool.size(), _grid_slots.size())):
		_grid_slots[i].set_item(pool[i])

func _equipment_slot_for(equip_slot_enum: InventoryItem.EquipSlot) -> InventorySlot:
	match equip_slot_enum:
		InventoryItem.EquipSlot.HEAD:
			return _head_slot
		InventoryItem.EquipSlot.CHEST:
			return _chest_slot
		InventoryItem.EquipSlot.LEGS:
			return _legs_slot
		InventoryItem.EquipSlot.BOOTS:
			return _boots_slot
		InventoryItem.EquipSlot.HANDS:
			return _hands_slot
		InventoryItem.EquipSlot.MAIN_HAND:
			return _main_hand_slot
		InventoryItem.EquipSlot.OFF_HAND:
			return _off_hand_slot
		InventoryItem.EquipSlot.AMULET:
			return _amulet_slot
		InventoryItem.EquipSlot.RING:
			return _ring_slot
		_:
			return null

func _on_slot_hovered(slot: InventorySlot) -> void:
	if slot.item:
		_tooltip.show_item(slot.item)
	else:
		_tooltip.hide_tooltip()

func _on_slot_unhovered() -> void:
	_tooltip.hide_tooltip()

## Double-click relayed from an InventorySlot: send gear to/from its paper-doll socket.
func quick_transfer(slot: InventorySlot) -> void:
	if slot.item == null:
		return
	if slot.is_equipment_slot:
		var target := _first_empty_grid_slot()
		if target:
			target.set_item(slot.clear_item())
	elif slot.item.equip_slot != InventoryItem.EquipSlot.NONE:
		var target := _equipment_slot_for(slot.item.equip_slot)
		if target:
			var previous := target.item
			target.set_item(slot.item)
			slot.set_item(previous)
	on_inventory_changed()

func _first_empty_grid_slot() -> InventorySlot:
	for slot in _grid_slots:
		if slot.item == null:
			return slot
	return null

func on_inventory_changed() -> void:
	var total_weight := 0.0
	var total_armor := 0
	for slot in _grid_slots:
		if slot.item:
			total_weight += slot.item.weight * slot.item.stack_count
	for slot in _equipment_slots():
		if slot.item:
			total_weight += slot.item.weight
			if slot.item.stat_bonuses.has("Armor"):
				total_armor += int(slot.item.stat_bonuses["Armor"])
	_weight_bar.max_value = CARRY_CAPACITY
	_weight_bar.value = total_weight
	_weight_label.text = "%.1f / %.1f kg" % [total_weight, CARRY_CAPACITY]
	_weight_bar.modulate = Color(1, 0.45, 0.4) if total_weight > CARRY_CAPACITY else Color(1, 1, 1)
	_armor_value_label.text = str(total_armor)

func _loadout_slots() -> Array[SpellSlot]:
	return [_primary_slot, _secondary_slot, _slot3_slot, _slot4_slot]

func _loadout_slot_for(trigger_action: String) -> SpellSlot:
	for slot in _loadout_slots():
		if slot.trigger_action == trigger_action:
			return slot
	return null

## Builds the read-only "known spells" palette and sets each loadout slot to
## the same default the live SpellCaster was authored with in proto_controller.tscn.
## Populated before signals are connected so this doesn't immediately re-equip
## the SpellCaster with what it already has.
func _populate_spellbook() -> void:
	for spell_def in MockSpellbook.known_spells():
		var slot := SpellSlotScene.instantiate() as SpellSlot
		slot.is_loadout_slot = false
		_spell_grid.add_child(slot)
		slot.slot_hovered.connect(_on_spell_slot_hovered)
		slot.slot_unhovered.connect(_on_slot_unhovered)
		slot.set_spell(spell_def)

	var defaults := MockSpellbook.default_loadout()
	for trigger_action in defaults.keys():
		var loadout_slot := _loadout_slot_for(trigger_action)
		var spell_def := MockSpellbook.find(defaults[trigger_action])
		if loadout_slot and spell_def:
			loadout_slot.set_spell(spell_def)

func _connect_loadout_slots() -> void:
	for slot in _loadout_slots():
		slot.slot_hovered.connect(_on_spell_slot_hovered)
		slot.slot_unhovered.connect(_on_slot_unhovered)
		slot.spell_changed.connect(_on_loadout_spell_changed)

func _on_spell_slot_hovered(slot: SpellSlot) -> void:
	if slot.spell:
		_tooltip.show_spell(slot.spell)
	else:
		_tooltip.hide_tooltip()

## Pushes a loadout change onto the live SpellCaster so dragging/clearing a
## spell in the UI actually changes what casting that key does in-game.
func _on_loadout_spell_changed(slot: SpellSlot) -> void:
	var caster := get_tree().get_first_node_in_group("spell_caster")
	if caster == null:
		return
	var scene: PackedScene = slot.spell.scene if slot.spell else null
	caster.equip_spell(slot.trigger_action, scene)

# --- Progression (XP / level / attribute allocation) ---------------------------
# Character-sheet display for the PlayerProgression autoload. Attribute rows are
# built here from progression.ATTRIBUTES rather than hand-placed in the scene, so
# the source of truth for which attributes exist lives in one place.

const _ATTR_DISPLAY_NAMES := {
	"STR": "Strength", "DEX": "Dexterity", "INT": "Intellect",
	"VIT": "Vitality", "LUK": "Luck",
}

var _attr_value_labels: Dictionary = {}
var _attr_plus_buttons: Dictionary = {}

func _progression() -> ProgressionSystem:
	return get_node_or_null("/root/PlayerProgression") as ProgressionSystem

func _setup_progression() -> void:
	var prog := _progression()
	if prog == null:
		return
	_build_attribute_rows(prog)
	prog.experience_gained.connect(_on_progression_changed.unbind(3))
	prog.leveled_up.connect(_on_progression_changed.unbind(3))
	prog.points_changed.connect(_on_progression_changed.unbind(2))
	prog.attribute_changed.connect(_on_attribute_value_changed)
	_refresh_progression()

func _build_attribute_rows(prog: ProgressionSystem) -> void:
	for child in _attributes_grid.get_children():
		child.queue_free()
	_attr_value_labels.clear()
	_attr_plus_buttons.clear()
	for attr in prog.ATTRIBUTES:
		var name_label := Label.new()
		name_label.text = _ATTR_DISPLAY_NAMES.get(attr, attr)
		name_label.add_theme_color_override("font_color", Color(0.65, 0.62, 0.58))
		name_label.add_theme_font_size_override("font_size", 13)

		var value_label := Label.new()
		value_label.text = str(prog.attributes[attr])
		value_label.custom_minimum_size = Vector2(32, 0)
		value_label.add_theme_font_size_override("font_size", 13)

		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(30, 0)
		plus.focus_mode = Control.FOCUS_NONE
		plus.pressed.connect(_on_attribute_plus_pressed.bind(attr))

		_attributes_grid.add_child(name_label)
		_attributes_grid.add_child(value_label)
		_attributes_grid.add_child(plus)
		_attr_value_labels[attr] = value_label
		_attr_plus_buttons[attr] = plus

func _on_attribute_plus_pressed(attribute: String) -> void:
	var prog := _progression()
	if prog:
		prog.spend_attribute_point(attribute)

func _on_progression_changed() -> void:
	_refresh_progression()

func _on_attribute_value_changed(attribute: String, value: int) -> void:
	if _attr_value_labels.has(attribute):
		_attr_value_labels[attribute].text = str(value)

func _refresh_progression() -> void:
	var prog := _progression()
	if prog == null:
		return
	var to_next := prog.xp_to_next()
	_level_label.text = "Level %d  •  Vagrant" % prog.level
	_xp_bar.max_value = to_next
	_xp_bar.value = prog.current_xp
	_xp_label.text = "%d / %d XP" % [int(prog.current_xp), int(to_next)]
	_points_label.text = "Attribute Points: %d      Skill Points: %d" % [prog.attribute_points, prog.skill_points]
	_points_label.visible = prog.attribute_points > 0 or prog.skill_points > 0
	for attr in _attr_value_labels:
		_attr_value_labels[attr].text = str(prog.attributes[attr])
	# Allocation buttons only appear when there are points to spend.
	for attr in _attr_plus_buttons:
		_attr_plus_buttons[attr].visible = prog.attribute_points > 0
