extends Node
class_name Spell

## Base class for one magical ability bound to a single input action.
## SpellCaster drives the lifecycle: start_cast() on press, hold_cast() every
## physics frame while held (skipped if instant), end_cast() on release.

@export var trigger_action: String = ""
## If true, start_cast() fires once on press and there is no hold/release phase.
@export var instant: bool = false

var is_active: bool = false

@onready var caster: SpellCaster = get_parent()


func can_cast() -> bool:
	return true


func start_cast() -> void:
	pass


func hold_cast(_delta: float) -> void:
	pass


func end_cast() -> void:
	pass


func _get_camera() -> Camera3D:
	return caster.camera


func _get_player() -> CharacterBody3D:
	return caster.player
