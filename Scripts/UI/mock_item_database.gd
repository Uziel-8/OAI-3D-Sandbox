class_name MockItemDatabase
extends RefCounted
## Placeholder item pool so the inventory/character screen has something to display.
## Replace with real loot/save data once a world pickup and persistence system exists.

static func _make(id: String, item_name: String, description: String, item_type: InventoryItem.ItemType,
		equip_slot: InventoryItem.EquipSlot, rarity: InventoryItem.Rarity, stack_count: int, max_stack: int,
		weight: float, value: int, icon_color: Color, stat_bonuses: Dictionary = {}) -> InventoryItem:
	var it := InventoryItem.new()
	it.id = id
	it.item_name = item_name
	it.description = description
	it.item_type = item_type
	it.equip_slot = equip_slot
	it.rarity = rarity
	it.stack_count = stack_count
	it.max_stack = max_stack
	it.weight = weight
	it.value = value
	it.icon_color = icon_color
	it.stat_bonuses = stat_bonuses
	return it

## Every item this placeholder database knows about, across all three pools.
## What a real item database's "load by id" would replace.
static func catalogue() -> Array[InventoryItem]:
	var all: Array[InventoryItem] = []
	all.append_array(make_starting_inventory())
	all.append_array(make_merchant_stock())
	var equipped := make_starting_equipment()
	for equip_slot in equipped:
		all.append(equipped[equip_slot])
	return all

## Fresh copy of the item with this id, or null. Lets a world pickup or a quest
## reward name an item by id instead of authoring the whole resource inline.
static func find_by_id(id: String) -> InventoryItem:
	for entry in catalogue():
		if entry.id == id:
			return entry
	return null

## Items sitting loose in the backpack grid.
static func make_starting_inventory() -> Array[InventoryItem]:
	var items: Array[InventoryItem] = []
	items.append(_make("torch", "Torch", "A pitch-soaked torch. Sheds light in dark places.",
		InventoryItem.ItemType.MISC, InventoryItem.EquipSlot.NONE, InventoryItem.Rarity.COMMON,
		3, 5, 1.0, 2, Color("d68a3c")))
	items.append(_make("healing_potion", "Healing Potion", "Restores a modest amount of health when consumed.",
		InventoryItem.ItemType.CONSUMABLE, InventoryItem.EquipSlot.NONE, InventoryItem.Rarity.COMMON,
		4, 10, 0.5, 15, Color("c94b3f")))
	items.append(_make("mana_draught", "Mana Draught", "A bitter tonic that restores magical reserves.",
		InventoryItem.ItemType.CONSUMABLE, InventoryItem.EquipSlot.NONE, InventoryItem.Rarity.UNCOMMON,
		2, 10, 0.5, 22, Color("3f6fc9")))
	items.append(_make("lockpick", "Lockpick", "Fragile, but good enough for most dungeon doors.",
		InventoryItem.ItemType.MISC, InventoryItem.EquipSlot.NONE, InventoryItem.Rarity.COMMON,
		6, 12, 0.1, 3, Color("9a9a9a")))
	items.append(_make("silver_ring", "Silver Ring", "A plain band, cool to the touch.",
		InventoryItem.ItemType.ARMOR, InventoryItem.EquipSlot.RING, InventoryItem.Rarity.UNCOMMON,
		1, 1, 0.1, 40, Color("c9c9d4"), {"INT": 1}))
	items.append(_make("hunting_knife", "Hunting Knife", "Light, quick, and easy to conceal.",
		InventoryItem.ItemType.WEAPON, InventoryItem.EquipSlot.MAIN_HAND, InventoryItem.Rarity.COMMON,
		1, 1, 1.2, 18, Color("9aa0a8"), {"Damage": 4}))
	items.append(_make("gold_pouch", "Gold Coins", "Currency accepted almost everywhere.",
		InventoryItem.ItemType.MISC, InventoryItem.EquipSlot.NONE, InventoryItem.Rarity.COMMON,
		132, 999, 0.01, 1, Color("d6b23c")))
	items.append(_make("iron_ore", "Iron Ore", "Raw ore, could be smelted or sold.",
		InventoryItem.ItemType.MISC, InventoryItem.EquipSlot.NONE, InventoryItem.Rarity.COMMON,
		5, 20, 2.0, 4, Color("6f6a63")))
	items.append(_make("cracked_amulet", "Cracked Amulet", "Once enchanted; whatever magic it held has faded.",
		InventoryItem.ItemType.ARMOR, InventoryItem.EquipSlot.AMULET, InventoryItem.Rarity.COMMON,
		1, 1, 0.3, 6, Color("8f8266")))
	items.append(_make("scroll_of_fire", "Scroll of Fire", "A single-use scroll inscribed with a fire glyph.",
		InventoryItem.ItemType.CONSUMABLE, InventoryItem.EquipSlot.NONE, InventoryItem.Rarity.RARE,
		1, 5, 0.1, 60, Color("d67a2c")))
	items.append(_make("wolf_pelt", "Wolf Pelt", "Coarse fur, worth something to the right buyer.",
		InventoryItem.ItemType.MISC, InventoryItem.EquipSlot.NONE, InventoryItem.Rarity.COMMON,
		2, 10, 1.5, 8, Color("8a7a63")))
	items.append(_make("emberforged_blade", "Emberforged Blade", "A rare longsword that runs warm to the touch.",
		InventoryItem.ItemType.WEAPON, InventoryItem.EquipSlot.MAIN_HAND, InventoryItem.Rarity.EPIC,
		1, 1, 3.2, 340, Color("d6602c"), {"Damage": 14, "Fire Damage": 3}))
	items.append(_make("waterskin", "Waterskin", "Half full. Better than nothing.",
		InventoryItem.ItemType.CONSUMABLE, InventoryItem.EquipSlot.NONE, InventoryItem.Rarity.COMMON,
		1, 3, 0.8, 2, Color("4a7a8a")))
	items.append(_make("iron_key", "Iron Key", "Worn smooth. No idea what it opens.",
		InventoryItem.ItemType.QUEST, InventoryItem.EquipSlot.NONE, InventoryItem.Rarity.RARE,
		1, 1, 0.05, 0, Color("b0a888")))
	return items

## Default wares for a ShopKeeper that was dropped in without authored stock.
## stack_count is the number in stock, so a line depletes as it's bought out.
static func make_merchant_stock() -> Array[InventoryItem]:
	var items: Array[InventoryItem] = []
	items.append(_make("healing_potion", "Healing Potion", "Restores a modest amount of health when consumed.",
		InventoryItem.ItemType.CONSUMABLE, InventoryItem.EquipSlot.NONE, InventoryItem.Rarity.COMMON,
		8, 10, 0.5, 15, Color("c94b3f")))
	items.append(_make("mana_draught", "Mana Draught", "A bitter tonic that restores magical reserves.",
		InventoryItem.ItemType.CONSUMABLE, InventoryItem.EquipSlot.NONE, InventoryItem.Rarity.UNCOMMON,
		5, 10, 0.5, 22, Color("3f6fc9")))
	items.append(_make("torch", "Torch", "A pitch-soaked torch. Sheds light in dark places.",
		InventoryItem.ItemType.MISC, InventoryItem.EquipSlot.NONE, InventoryItem.Rarity.COMMON,
		10, 12, 1.0, 2, Color("d68a3c")))
	items.append(_make("lockpick", "Lockpick", "Fragile, but good enough for most dungeon doors.",
		InventoryItem.ItemType.MISC, InventoryItem.EquipSlot.NONE, InventoryItem.Rarity.COMMON,
		12, 12, 0.1, 3, Color("9a9a9a")))
	items.append(_make("traveling_cloak", "Traveling Cloak", "Waxed wool. Keeps the harbour damp off your back.",
		InventoryItem.ItemType.ARMOR, InventoryItem.EquipSlot.CHEST, InventoryItem.Rarity.COMMON,
		1, 1, 2.2, 35, Color("4a5a6a"), {"Armor": 4}))
	items.append(_make("guild_signet", "Guild Signet", "A merchant's ring. Opens doors, if the right people see it.",
		InventoryItem.ItemType.ARMOR, InventoryItem.EquipSlot.RING, InventoryItem.Rarity.RARE,
		1, 1, 0.1, 120, Color("d6b23c"), {"WIL": 2}))
	items.append(_make("warding_amulet", "Warding Amulet", "The glass bead is warm. Tom swears it turns a blade.",
		InventoryItem.ItemType.ARMOR, InventoryItem.EquipSlot.AMULET, InventoryItem.Rarity.UNCOMMON,
		1, 1, 0.3, 85, Color("7a5fd6"), {"Armor": 2, "INT": 1}))
	items.append(_make("scroll_of_fire", "Scroll of Fire", "A single-use scroll inscribed with a fire glyph.",
		InventoryItem.ItemType.CONSUMABLE, InventoryItem.EquipSlot.NONE, InventoryItem.Rarity.RARE,
		2, 5, 0.1, 60, Color("d67a2c")))
	items.append(_make("dockhand_boots", "Dockhand's Boots", "Salt-stained, but the soles grip a wet deck.",
		InventoryItem.ItemType.ARMOR, InventoryItem.EquipSlot.BOOTS, InventoryItem.Rarity.COMMON,
		1, 1, 1.1, 18, Color("5c452e"), {"Armor": 2}))
	return items

## Gear worn on the paper doll at scene start, keyed by InventoryItem.EquipSlot.
static func make_starting_equipment() -> Dictionary:
	var equipped := {}
	equipped[InventoryItem.EquipSlot.HEAD] = _make("leather_cap", "Leather Cap", "Simple boiled-leather headgear.",
		InventoryItem.ItemType.ARMOR, InventoryItem.EquipSlot.HEAD, InventoryItem.Rarity.COMMON,
		1, 1, 0.8, 12, Color("7a5c3e"), {"Armor": 2})
	equipped[InventoryItem.EquipSlot.CHEST] = _make("leather_tunic", "Leather Tunic", "Worn but sturdy travel armor.",
		InventoryItem.ItemType.ARMOR, InventoryItem.EquipSlot.CHEST, InventoryItem.Rarity.COMMON,
		1, 1, 3.5, 30, Color("7a5c3e"), {"Armor": 6})
	equipped[InventoryItem.EquipSlot.LEGS] = _make("leather_trousers", "Leather Trousers", "Matches the tunic.",
		InventoryItem.ItemType.ARMOR, InventoryItem.EquipSlot.LEGS, InventoryItem.Rarity.COMMON,
		1, 1, 2.0, 20, Color("7a5c3e"), {"Armor": 4})
	equipped[InventoryItem.EquipSlot.BOOTS] = _make("traveling_boots", "Traveling Boots", "Comfortable for long roads.",
		InventoryItem.ItemType.ARMOR, InventoryItem.EquipSlot.BOOTS, InventoryItem.Rarity.COMMON,
		1, 1, 1.2, 15, Color("5c452e"), {"Armor": 2})
	equipped[InventoryItem.EquipSlot.HANDS] = _make("leather_gloves", "Leather Gloves", "Improves grip on cold steel.",
		InventoryItem.ItemType.ARMOR, InventoryItem.EquipSlot.HANDS, InventoryItem.Rarity.COMMON,
		1, 1, 0.6, 10, Color("5c452e"), {"Armor": 1})
	equipped[InventoryItem.EquipSlot.MAIN_HAND] = _make("iron_sword", "Iron Sword", "A well-balanced arming sword.",
		InventoryItem.ItemType.WEAPON, InventoryItem.EquipSlot.MAIN_HAND, InventoryItem.Rarity.UNCOMMON,
		1, 1, 2.8, 55, Color("aab0b8"), {"Damage": 9})
	equipped[InventoryItem.EquipSlot.OFF_HAND] = _make("wooden_buckler", "Wooden Buckler", "Small, light, iron-rimmed.",
		InventoryItem.ItemType.ARMOR, InventoryItem.EquipSlot.OFF_HAND, InventoryItem.Rarity.COMMON,
		1, 1, 1.8, 18, Color("7a5c3e"), {"Armor": 3})
	return equipped
