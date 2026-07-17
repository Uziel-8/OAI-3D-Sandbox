class_name InventoryItem
extends Resource
## Data-only definition of a single inventory/equipment item.
## No world/pickup/save system exists yet - this is the shape future systems should produce.

enum ItemType { WEAPON, ARMOR, CONSUMABLE, MISC, QUEST }
enum EquipSlot { NONE, HEAD, CHEST, LEGS, BOOTS, HANDS, MAIN_HAND, OFF_HAND, AMULET, RING }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

@export var id: String = ""
@export var item_name: String = "Unknown Item"
@export_multiline var description: String = ""
@export var icon: Texture2D = null
@export var icon_color: Color = Color(0.4, 0.4, 0.45)
@export var item_type: ItemType = ItemType.MISC
@export var equip_slot: EquipSlot = EquipSlot.NONE
@export var rarity: Rarity = Rarity.COMMON
@export var stack_count: int = 1
@export var max_stack: int = 1
@export var weight: float = 0.0
@export var value: int = 0
## Display-only bonuses shown on the tooltip, e.g. {"Armor": 5, "STR": 1}
@export var stat_bonuses: Dictionary = {}

static func rarity_color(r: Rarity) -> Color:
	match r:
		Rarity.UNCOMMON:
			return Color("4caf6b")
		Rarity.RARE:
			return Color("4a90d9")
		Rarity.EPIC:
			return Color("a05fd6")
		Rarity.LEGENDARY:
			return Color("e0a030")
		_:
			return Color("9a9a9a")

static func rarity_name(r: Rarity) -> String:
	match r:
		Rarity.UNCOMMON:
			return "Uncommon"
		Rarity.RARE:
			return "Rare"
		Rarity.EPIC:
			return "Epic"
		Rarity.LEGENDARY:
			return "Legendary"
		_:
			return "Common"

static func equip_slot_name(s: EquipSlot) -> String:
	match s:
		EquipSlot.HEAD:
			return "Head"
		EquipSlot.CHEST:
			return "Chest"
		EquipSlot.LEGS:
			return "Legs"
		EquipSlot.BOOTS:
			return "Boots"
		EquipSlot.HANDS:
			return "Hands"
		EquipSlot.MAIN_HAND:
			return "Main Hand"
		EquipSlot.OFF_HAND:
			return "Off Hand"
		EquipSlot.AMULET:
			return "Amulet"
		EquipSlot.RING:
			return "Ring"
		_:
			return ""

## Two-letter fallback glyph used while no icon texture/art exists.
func icon_text() -> String:
	var clean := item_name.strip_edges()
	if clean.is_empty():
		return "?"
	var parts := clean.split(" ", false)
	if parts.size() >= 2:
		return (parts[0][0] + parts[1][0]).to_upper()
	return clean.substr(0, mini(2, clean.length())).to_upper()
