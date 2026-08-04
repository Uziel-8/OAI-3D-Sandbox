class_name MockSpellbook
extends RefCounted
## Placeholder "known spells" list so the spellbook tab has something to show
## and assign. Replace with real spell-unlock/save data once that exists --
## same role MockItemDatabase plays for the backpack.

const GRAB_SCENE := preload("res://Scripts/Magic/telekinesis_grab_spell.tscn")
const PUSH_SCENE := preload("res://Scripts/Magic/telekinesis_push_spell.tscn")
const FIREBALL_SCENE := preload("res://Scripts/Magic/fireball_spell.tscn")
const ICEBOLT_SCENE := preload("res://Scripts/Magic/icebolt_spell.tscn")
const STICKY_BOMB_SCENE := preload("res://Scripts/Magic/sticky_bomb_spell.tscn")
const SHADOW_TENDRIL_SCENE := preload("res://Scripts/Magic/shadow_tendril_spell.tscn")

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
		_make("sticky_bomb", "Sticky Bomb",
			"Lobs a charge that clings to whatever it touches — wall, crate or throat — and bursts in a fiery radius three seconds later. With a Remote Detonator you set the moment yourself.",
			Color("d6602c"), 20, 3.0, STICKY_BOMB_SCENE),
		_make("icebolt", "Ice Bolt",
			"A fast-moving shard of ice that chills and staggers on impact.",
			Color("4ab0d6"), 12, 1.5, ICEBOLT_SCENE),
		_make("shadow_tendril", "Shadow Tendril",
			"A claw of living shadow bursts from the ground beneath your quarry and holds them fast for three seconds. It draws no blood — and the grip fails the moment anything else does. With Grasping Dark it takes the ground itself, and everything standing on it.",
			Color("7a4fd0"), 18, 8.0, SHADOW_TENDRIL_SCENE),
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


## Reverse lookup: a live Spell node back to the definition it was instanced
## from, matched on scene path. Lets the HUD spell bar label what's equipped
## without a Spell node having to know anything about spellbook data.
static func find_by_scene_path(path: String) -> SpellDefinition:
	if path.is_empty():
		return null
	for s in known_spells():
		if s.scene and s.scene.resource_path == path:
			return s
	return null
