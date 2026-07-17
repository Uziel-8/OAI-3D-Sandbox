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
## ItemTooltip) are looked up by explicit $path, not %unique_name -- Godot 4.7.1
## corrupts sibling parent-resolution when unique_name_in_owner is set as a
## property override on an *instanced* node (reproduced in isolation; every
## node after the first such instance silently gets flattened onto the scene
## root during PackedScene::instantiate()). Plain built-in node types are
## unaffected and keep using %unique_name as normal.
const _CHAR_PATH := "Center/Frame/Tabs/Inventory/CharacterPanel/CharVBox/PaperDollCenter/PaperDoll/"
const _SPELL_PATH := "Center/Frame/Tabs/Spellbook/LoadoutPanel/LoadoutVBox/"

@onready var _item_grid: GridContainer = %ItemGrid
@onready var _weight_bar: ProgressBar = %WeightBar
@onready var _weight_label: Label = %WeightLabel
@onready var _armor_value_label: Label = %ArmorValueLabel
@onready var _close_button: Button = %CloseButton
@onready var _spell_grid: GridContainer = %SpellGrid

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
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	is_open = false
	visible = false
	_tooltip.hide_tooltip()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
