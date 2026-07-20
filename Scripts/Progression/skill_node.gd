class_name SkillNode
extends Resource
## Data-only definition of one node in a magic-school skill tree. Authored in
## MockSkillTrees for now (same mock-data pattern as SpellDefinition/InventoryItem).
##
## Nodes form a DAG, not a strict tree: `prerequisites` lists OTHER node ids that
## must be unlocked before this one, so branches can converge. `grid_position`
## (column, row) places the node on the SkillTreeView canvas and is also what the
## connector lines are drawn from/to.
##
## A node does exactly one thing, chosen by `effect`. Only UNLOCK_SPELL is fully
## consumed today; PASSIVE and UPGRADE store their payload and expose query hooks
## on SkillSystem (passive_total / has_upgrade) but nothing reads them yet -- they
## are deliberately just the bones for a later pass.

enum Effect { UNLOCK_SPELL, PASSIVE, UPGRADE }

@export var id: String = ""
@export var display_name: String = "Unknown Skill"
@export_multiline var description: String = ""
@export var icon_color: Color = Color(0.5, 0.5, 0.55)
@export var cost: int = 1
@export var prerequisites: Array[String] = []
@export var grid_position: Vector2i = Vector2i.ZERO

@export var effect: Effect = Effect.PASSIVE
## UNLOCK_SPELL: the SpellDefinition id this node makes equippable. Fully wired --
## SkillSystem.unlocked_spell_ids() collects these and the spellbook filters by them.
@export var unlock_spell_id: String = ""
## PASSIVE: additive bonuses keyed by an arbitrary stat string (e.g. {"fire_damage_pct": 0.1}),
## summed across unlocked nodes by SkillSystem.passive_total(). Bones only for now.
@export var passive_bonuses: Dictionary = {}
## UPGRADE: a tag a Spell script can later check via SkillSystem.has_upgrade().
## Bones only for now -- no Spell reads it yet.
@export var upgrade_id: String = ""

## Short label for the effect, used on the tooltip's subtitle line.
func effect_label() -> String:
	match effect:
		Effect.UNLOCK_SPELL:
			return "Unlocks Spell"
		Effect.UPGRADE:
			return "Spell Upgrade"
		_:
			return "Passive"

## Two-letter glyph fallback while there's no icon art (matches SpellDefinition/InventoryItem).
func icon_text() -> String:
	var clean := display_name.strip_edges()
	if clean.is_empty():
		return "?"
	var parts := clean.split(" ", false)
	if parts.size() >= 2:
		return (parts[0][0] + parts[1][0]).to_upper()
	return clean.substr(0, mini(2, clean.length())).to_upper()
