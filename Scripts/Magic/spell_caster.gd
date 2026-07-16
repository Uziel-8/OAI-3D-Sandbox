extends Node
class_name SpellCaster

## Routes input to whichever Spell child nodes are attached beneath it.
## Add new magic disciplines by adding more Spell-derived children here -
## no changes to this file needed.

@onready var camera: Camera3D = get_parent()
var player: CharacterBody3D


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")


func _physics_process(delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")

	# Only cast while the mouse is captured (i.e. actually playing, not menus)
	# and once a player body has actually been found.
	if player == null or Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	for child in get_children():
		if not (child is Spell):
			continue
		var spell: Spell = child

		if spell.instant:
			if Input.is_action_just_pressed(spell.trigger_action) and spell.can_cast():
				spell.start_cast()
			continue

		if not spell.is_active and Input.is_action_just_pressed(spell.trigger_action) and spell.can_cast():
			spell.is_active = true
			spell.start_cast()
		elif spell.is_active and Input.is_action_just_released(spell.trigger_action):
			spell.is_active = false
			spell.end_cast()
		elif spell.is_active:
			spell.hold_cast(delta)
