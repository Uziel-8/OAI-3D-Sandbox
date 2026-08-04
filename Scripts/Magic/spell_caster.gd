extends Node
class_name SpellCaster

## Routes input to whichever Spell child nodes are attached beneath it.
## Add new magic disciplines by adding more Spell-derived children here -
## no changes to this file needed.

## Emitted the moment a cast begins (instant fire OR a held spell's press). The
## PlayerAnimator listens to raise the upper-body cast overlay.
signal spell_cast(spell: Spell)
## Emitted whenever the equipped set changes (equip_spell / unequip_slot). The
## HUD's spell bar rebuilds off this rather than polling for new children.
signal loadout_changed

## The hotbar bindings, in display order -- the single source of truth for which
## slots exist, shared by the HUD spell bar and the spellbook tab's sockets.
const LOADOUT_ACTIONS: Array[String] = [
	"cast_primary", "cast_secondary", "spell_slot_3", "spell_slot_4",
]

@onready var camera: Camera3D = get_parent()
var player: CharacterBody3D


func _ready() -> void:
	add_to_group("spell_caster")
	player = get_tree().get_first_node_in_group("player")


func _physics_process(delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")

	# Cooldowns recover whether or not casting is currently possible, so opening
	# a menu or releasing the mouse doesn't freeze them mid-recovery. Only a
	# paused tree stops them, which is what pausing is meant to do.
	for child in get_children():
		if child is Spell:
			child.tick_cooldown(delta)

	# Only cast while the mouse is captured (i.e. actually playing, not menus)
	# and once a player body has actually been found.
	if player == null or Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	for child in get_children():
		if not (child is Spell):
			continue
		var spell: Spell = child

		if spell.instant:
			if Input.is_action_just_pressed(spell.trigger_action) and not spell.is_on_cooldown() \
					and spell.can_cast() and spell.try_pay_cost():
				spell.start_cast()
				# After start_cast: a spell may decide the press was something
				# other than a fresh cast (StickyBombSpell's remote detonation).
				spell.begin_cooldown()
				spell_cast.emit(spell)
			continue

		if not spell.is_active and Input.is_action_just_pressed(spell.trigger_action) \
				and not spell.is_on_cooldown() and spell.can_cast() and spell.try_pay_cost():
			spell.is_active = true
			spell.start_cast()
			spell_cast.emit(spell)
		elif spell.is_active and Input.is_action_just_released(spell.trigger_action):
			spell.is_active = false
			spell.end_cast()
			# Held spells start recovering on RELEASE, so a long hold isn't
			# quietly serving out its own cooldown while it's still running.
			spell.begin_cooldown()
		elif spell.is_active:
			spell.hold_cast(delta)


## True while a held spell (e.g. Telekinesis Grab) is mid-cast -- lets the
## animator keep the cast overlay raised for the duration of a hold.
func is_casting() -> bool:
	for child in get_children():
		if child is Spell and child.is_active:
			return true
	return false


## Equips spell_scene into the given trigger_action slot, replacing whatever
## was equipped there (if anything). Passing null just clears the slot.
## Used by the inventory's spellbook tab to swap spells at runtime.
func equip_spell(trigger_action: String, spell_scene: PackedScene) -> void:
	unequip_slot(trigger_action)
	if spell_scene == null:
		return
	var spell: Spell = spell_scene.instantiate()
	spell.trigger_action = trigger_action
	add_child(spell)
	loadout_changed.emit()


## Removes whatever spell currently occupies the given trigger_action slot, if any.
func unequip_slot(trigger_action: String) -> void:
	for child in get_children():
		if child is Spell and child.trigger_action == trigger_action:
			remove_child(child)
			child.queue_free()
			loadout_changed.emit()
			return


## The Spell currently bound to an action, or null. Lets the HUD read live
## cooldown/cost state straight off the node driving that key.
func equipped_spell(trigger_action: String) -> Spell:
	for child in get_children():
		if child is Spell and child.trigger_action == trigger_action:
			return child
	return null
