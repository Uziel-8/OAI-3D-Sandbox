extends Node
class_name PlayerInventorySystem
## The player's actual item store: the backpack grid plus what's worn on the paper
## doll. Registered as the `PlayerInventory` autoload (the class name differs from
## the singleton name because Godot rejects a global class that shadows an
## autoload -- same reason as ProgressionSystem/PlayerProgression).
##
## Before this existed, items lived ONLY inside the InventoryScreen's UI slots, so
## nothing outside that screen could give the player an item or take one away.
## This is the gameplay-side owner: the screen is now a VIEW over it, and shops,
## loot drops and fetch quests all go through the API here.
##
## Items are stored as OWNED COPIES -- add_item() duplicates what it's handed, so
## a shop's stock resource (or a MockItemDatabase entry, which is shared) can never
## be mutated by the player's stack count changing. Nothing is written to disk;
## there is still no save system.

## Any change at all -- add, remove, equip, or a slot rearranged in the UI.
signal inventory_changed
signal item_added(item: InventoryItem, count: int)
signal item_removed(item: InventoryItem, count: int)

## Backpack size. Must match the InventoryScreen's grid (8 x 5); the screen reads
## this rather than the reverse, so widening the bag is a change here.
@export var capacity: int = 40
## Seeds the bag with MockItemDatabase's placeholder pool on startup. Turn off for
## an empty start once real loot exists.
@export var seed_mock_items: bool = true

## Fixed-length; a null entry is an empty slot, so slot indices stay stable.
var backpack: Array[InventoryItem] = []
## EquipSlot -> InventoryItem for whatever is worn.
var equipment: Dictionary = {}


func _ready() -> void:
	backpack.resize(capacity)
	if seed_mock_items:
		_seed_mock()


func _seed_mock() -> void:
	var pool := MockItemDatabase.make_starting_inventory()
	for i in range(mini(pool.size(), capacity)):
		backpack[i] = pool[i]
	equipment = MockItemDatabase.make_starting_equipment()
	inventory_changed.emit()


# --- Queries -------------------------------------------------------------------

func slot(index: int) -> InventoryItem:
	return backpack[index] if index >= 0 and index < backpack.size() else null


func first_empty_index() -> int:
	for i in backpack.size():
		if backpack[i] == null:
			return i
	return -1


## Total units of `id` carried in the backpack (worn gear is not counted).
func count_of(id: String) -> int:
	var total := 0
	for entry in backpack:
		if entry and entry.id == id:
			total += entry.stack_count
	return total


## How many units of `item` would actually fit, counting room left in matching
## stacks plus empty slots. Used to reject a purchase BEFORE any gold moves.
func room_for(item: InventoryItem) -> int:
	if item == null:
		return 0
	var room := 0
	if item.max_stack > 1:
		for entry in backpack:
			if entry and entry.id == item.id:
				room += maxi(entry.max_stack - entry.stack_count, 0)
	for entry in backpack:
		if entry == null:
			room += item.max_stack
	return room


func has_room_for(item: InventoryItem, count: int = -1) -> bool:
	if item == null:
		return false
	return room_for(item) >= (item.stack_count if count < 0 else count)


func total_weight() -> float:
	var total := 0.0
	for entry in backpack:
		if entry:
			total += entry.weight * entry.stack_count
	for equip_slot in equipment:
		var worn: InventoryItem = equipment[equip_slot]
		if worn:
			total += worn.weight
	return total


# --- Mutation ------------------------------------------------------------------

## Adds `count` units of `item` (default: the item's own stack_count), filling
## partial stacks before empty slots. All-or-nothing -- returns false and changes
## nothing if it doesn't all fit, so a caller never has to unwind a half-transfer.
## The stored entries are COPIES; the passed item is left untouched.
func add_item(item: InventoryItem, count: int = -1) -> bool:
	if item == null:
		return false
	var wanted := item.stack_count if count < 0 else count
	if wanted <= 0 or room_for(item) < wanted:
		return false

	var remaining := wanted
	if item.max_stack > 1:
		for entry in backpack:
			if remaining <= 0:
				break
			if entry and entry.id == item.id and entry.stack_count < entry.max_stack:
				var space: int = mini(entry.max_stack - entry.stack_count, remaining)
				entry.stack_count += space
				remaining -= space
	for i in backpack.size():
		if remaining <= 0:
			break
		if backpack[i] == null:
			var copy: InventoryItem = item.duplicate()
			copy.stack_count = mini(item.max_stack, remaining)
			backpack[i] = copy
			remaining -= copy.stack_count

	item_added.emit(item, wanted)
	inventory_changed.emit()
	return true


## Removes `count` units of `id`, emptying partial stacks first so full stacks are
## left intact. All-or-nothing, like add_item.
func remove_item(id: String, count: int = 1) -> bool:
	if count <= 0 or count_of(id) < count:
		return false
	var removed: InventoryItem = null
	var remaining := count
	for i in backpack.size():
		if remaining <= 0:
			break
		var entry := backpack[i]
		if entry == null or entry.id != id:
			continue
		if removed == null:
			removed = entry
		var taken: int = mini(entry.stack_count, remaining)
		entry.stack_count -= taken
		remaining -= taken
		if entry.stack_count <= 0:
			backpack[i] = null

	item_removed.emit(removed, count)
	inventory_changed.emit()
	return true


## Removes units from ONE specific slot -- what a shop's sell button needs, since
## the player picked a particular stack rather than an item id.
func remove_from_slot(index: int, count: int = 1) -> InventoryItem:
	var entry := slot(index)
	if entry == null or count <= 0:
		return null
	var taken: int = mini(entry.stack_count, count)
	var out: InventoryItem = entry.duplicate()
	out.stack_count = taken
	entry.stack_count -= taken
	if entry.stack_count <= 0:
		backpack[index] = null

	item_removed.emit(out, taken)
	inventory_changed.emit()
	return out


func set_slot(index: int, item: InventoryItem) -> void:
	if index < 0 or index >= backpack.size():
		return
	backpack[index] = item
	inventory_changed.emit()


func equipped(equip_slot: InventoryItem.EquipSlot) -> InventoryItem:
	return equipment.get(equip_slot, null)


func equip(equip_slot: InventoryItem.EquipSlot, item: InventoryItem) -> void:
	if item == null:
		equipment.erase(equip_slot)
	else:
		equipment[equip_slot] = item
	inventory_changed.emit()


## Bulk overwrite, used by InventoryScreen to write its slot layout back after a
## drag/drop rearrange. `emit` is false when the caller is itself reacting to an
## inventory_changed, so the two can't ping-pong.
func replace_all(items: Array[InventoryItem], worn: Dictionary, emit: bool = true) -> void:
	backpack = items.duplicate()
	backpack.resize(capacity)
	equipment = worn.duplicate()
	if emit:
		inventory_changed.emit()
