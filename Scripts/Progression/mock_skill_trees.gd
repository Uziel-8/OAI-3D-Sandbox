class_name MockSkillTrees
extends RefCounted
## Placeholder authoring home for the magic-school skill trees, same role
## MockSpellbook/MockItemDatabase play for their systems -- replace with real
## authored .tres resources once a save/content pipeline exists.
##
## Each school has a spell-unlock ROOT plus a couple of downstream nodes that
## demonstrate the other two effect types (PASSIVE, UPGRADE) and DAG branching.
## Spell-unlock ids must match SpellDefinition ids in MockSpellbook.
##
## To add a school: append another _school(...) block. To deepen a tree: append
## SkillNodes with prerequisites + grid_position. The UI derives everything from
## this data, so neither requires touching UI code.

static func _node(id: String, display_name: String, description: String, icon_color: Color,
		cost: int, prerequisites: Array[String], grid_position: Vector2i,
		effect: SkillNode.Effect, payload: Variant = null) -> SkillNode:
	var n := SkillNode.new()
	n.id = id
	n.display_name = display_name
	n.description = description
	n.icon_color = icon_color
	n.cost = cost
	n.prerequisites = prerequisites
	n.grid_position = grid_position
	n.effect = effect
	match effect:
		SkillNode.Effect.UNLOCK_SPELL:
			n.unlock_spell_id = payload
		SkillNode.Effect.PASSIVE:
			n.passive_bonuses = payload
		SkillNode.Effect.UPGRADE:
			n.upgrade_id = payload
	return n

static func _school(id: String, display_name: String, accent: Color, nodes: Array[SkillNode]) -> SkillSchool:
	var s := SkillSchool.new()
	s.id = id
	s.display_name = display_name
	s.accent_color = accent
	s.nodes = nodes
	return s

static func schools() -> Array[SkillSchool]:
	var result: Array[SkillSchool] = []

	var telekinesis_purple := Color("a05fd6")
	result.append(_school("telekinesis", "Telekinesis", telekinesis_purple, [
		_node("tk_grab", "Telekinesis Grab",
			"Unlock the ability to reach out and hold objects at range, then throw them.",
			telekinesis_purple, 1, [], Vector2i(0, 0),
			SkillNode.Effect.UNLOCK_SPELL, "telekinesis_grab"),
		_node("tk_push", "Telekinesis Push",
			"Unlock a short-range force blast that knocks objects and creatures away.",
			telekinesis_purple, 1, ["tk_grab"], Vector2i(0, 1),
			SkillNode.Effect.UNLOCK_SPELL, "telekinesis_push"),
	]))

	var fire_orange := Color("d6602c")
	result.append(_school("pyromancy", "Pyromancy", fire_orange, [
		_node("py_fireball", "Fireball",
			"Unlock a bolt of flame that scorches and knocks back what it strikes.",
			fire_orange, 1, [], Vector2i(1, 0),
			SkillNode.Effect.UNLOCK_SPELL, "fireball"),
		_node("py_kindling", "Kindling",
			"Your fire spells deal more damage. (Passive scaffolding -- not yet consumed.)",
			fire_orange, 1, ["py_fireball"], Vector2i(0, 1),
			SkillNode.Effect.PASSIVE, {"fire_damage_pct": 0.1}),
		_node("py_piercing", "Piercing Flames",
			"Fireball punches through its first target. (Upgrade scaffolding -- not yet consumed.)",
			fire_orange, 2, ["py_fireball"], Vector2i(2, 1),
			SkillNode.Effect.UPGRADE, "fireball_pierce"),
		_node("py_stickybomb", "Sticky Bomb",
			"Unlock a charge that clings to whatever it strikes -- wall, crate or enemy -- and bursts in a fiery radius once its fuse runs out.",
			fire_orange, 2, ["py_fireball"], Vector2i(1, 1),
			SkillNode.Effect.UNLOCK_SPELL, "sticky_bomb"),
		_node("py_detonator", "Remote Detonator",
			"Your Sticky Bombs no longer burn a fuse. Press the spell again to set off every charge you have planted, at the moment of your choosing.",
			fire_orange, 2, ["py_stickybomb"], Vector2i(1, 2),
			SkillNode.Effect.UPGRADE, "sticky_bomb_remote"),
		_node("py_bombimmunity", "Bomb Immunity",
			"You are now immune to the damage of your sticky bombs.",
			fire_orange, 1, ["py_stickybomb"], Vector2i(1, 3),
			SkillNode.Effect.UPGRADE, "bomb_immunity"),
	]))

	var frost_cyan := Color("4ab0d6")
	result.append(_school("cryomancy", "Cryomancy", frost_cyan, [
		_node("cr_icebolt", "Ice Bolt",
			"Unlock a fast shard of ice that chills and staggers on impact.",
			frost_cyan, 1, [], Vector2i(1, 0),
			SkillNode.Effect.UNLOCK_SPELL, "icebolt"),
		_node("cr_frugal", "Frugal Frost",
			"Your frost spells cost less mana. (Passive scaffolding -- not yet consumed.)",
			frost_cyan, 1, ["cr_icebolt"], Vector2i(0, 1),
			SkillNode.Effect.PASSIVE, {"frost_mana_cost_flat": -3}),
		_node("cr_deepfreeze", "Deep Freeze",
			"Ice Bolt slows its target far harder. (Upgrade scaffolding -- not yet consumed.)",
			frost_cyan, 2, ["cr_icebolt"], Vector2i(2, 1),
			SkillNode.Effect.UPGRADE, "icebolt_deepfreeze"),
	]))

	# Brightened from the authored #2d1f5e: the accent tints the node buttons,
	# connector lines, tooltip titles and the HUD spell-bar border, all of which
	# sit on near-black panels -- the deeper tone was legible only as a smudge.
	# It survives where it reads best, as ShadowTendril's claw_color.
	var shadow_violet := Color("7a4fd0")
	result.append(_school("shadow", "Shadow", shadow_violet, [
		_node("sh_tendril", "Shadow Tendril",
			"Unlock an ephemeral tendril of liquid shadow to ensnare your enemies.",
			shadow_violet, 1, [], Vector2i(1, 0),
			SkillNode.Effect.UNLOCK_SPELL, "shadow_tendril"),
		_node("sh_burst", "Grasping Dark",
			"Your Shadow Tendril no longer reaches for one throat. The dark erupts wherever you aim and takes hold of everything standing around it.",
			shadow_violet, 2, ["sh_tendril"], Vector2i(1, 1),
			SkillNode.Effect.UPGRADE, "shadow_tendril_burst"),
	]))

	return result
