class_name MockSpellbook
extends RefCounted
## Placeholder "known spells" list so the spellbook tab has something to show
## and assign. Replace with real spell-unlock/save data once that exists --
## same role MockItemDatabase plays for the backpack.

const GRAB_SCENE := preload("res://Scripts/Magic/telekinesis_grab_spell.tscn")
const PUSH_SCENE := preload("res://Scripts/Magic/telekinesis_push_spell.tscn")
const FIREBALL_SCENE := preload("res://Scripts/Magic/fireball_spell.tscn")
const ICEBOLT_SCENE := preload("res://Scripts/Magic/icebolt_spell.tscn")

static func _make(id: String, spell_name: String, description: String, icon_color: Color,
		mana_cost: int, cooldown: float, scene: PackedScene) -> SpellDefinition:
	var s := SpellDefinition.new()
	s.id = id
	s.spell_name = spell_name
	s.description = description
	s.icon_color = icon_color
	s.mana_cost = mana_cost
	s.cooldown = cooldown
	s.scene = scene
	return s

static func known_spells() -> Array[SpellDefinition]:
	return [
		_make("telekinesis_grab", "Telekinesis Grab",
			"Reach out and hold a nearby object at range, then let go to throw it.",
			Color("a05fd6"), 0, 0.0, GRAB_SCENE),
		_make("telekinesis_push", "Telekinesis Push",
			"A short-range blast that knocks nearby objects and creatures away.",
			Color("a05fd6"), 5, 1.0, PUSH_SCENE),
		_make("fireball", "Fireball",
			"Hurls a bolt of flame that scorches and knocks back whatever it strikes.",
			Color("d6602c"), 15, 2.0, FIREBALL_SCENE),
		_make("icebolt", "Ice Bolt",
			"A fast-moving shard of ice that chills and staggers on impact.",
			Color("4ab0d6"), 12, 1.5, ICEBOLT_SCENE),
	]

## trigger_action -> spell id, mirrors the default loadout authored in proto_controller.tscn.
static func default_loadout() -> Dictionary:
	return {
		"cast_primary": "telekinesis_grab",
		"cast_secondary": "telekinesis_push",
		"spell_slot_3": "fireball",
		"spell_slot_4": "icebolt",
	}

static func find(id: String) -> SpellDefinition:
	for s in known_spells():
		if s.id == id:
			return s
	return null
