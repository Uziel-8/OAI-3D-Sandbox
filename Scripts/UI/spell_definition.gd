class_name SpellDefinition
extends Resource
## Data-only description of a spell the player knows, shown in the spellbook tab.
## `scene` is the actual Spell-derived scene SpellCaster.equip_spell() instantiates
## when this spell is dragged onto a loadout slot.

@export var id: String = ""
@export var spell_name: String = "Unknown Spell"
@export_multiline var description: String = ""
@export var icon_color: Color = Color(0.5, 0.5, 0.55)
@export var mana_cost: int = 0
@export var cooldown: float = 0.0
@export var scene: PackedScene = null

## Two-letter fallback glyph used while no icon texture/art exists.
func icon_text() -> String:
	var clean := spell_name.strip_edges()
	if clean.is_empty():
		return "?"
	var parts := clean.split(" ", false)
	if parts.size() >= 2:
		return (parts[0][0] + parts[1][0]).to_upper()
	return clean.substr(0, mini(2, clean.length())).to_upper()
