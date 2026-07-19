extends Node
class_name Spell

## Base class for one magical ability bound to a single input action.
## SpellCaster drives the lifecycle: start_cast() on press, hold_cast() every
## physics frame while held (skipped if instant), end_cast() on release.

@export var trigger_action: String = ""
## If true, start_cast() fires once on press and there is no hold/release phase.
@export var instant: bool = false
## Mana spent when the cast begins (0 = free). Checked/charged by SpellCaster
## via try_pay_cost() at press time; a cast that can't be afforded doesn't fire.
@export var mana_cost: float = 0.0

var is_active: bool = false

@onready var caster: SpellCaster = get_parent()


func can_cast() -> bool:
	return true


## Charges this spell's mana cost against PlayerState. Free spells (or a missing
## PlayerState autoload) always succeed, so spells work in test scenes too.
func try_pay_cost() -> bool:
	if mana_cost <= 0.0:
		return true
	var state := get_node_or_null("/root/PlayerState")
	if state == null:
		return true
	return state.spend_mana(mana_cost)


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
