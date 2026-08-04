extends Node
class_name Spell

## Base class for one magical ability bound to a single input action.
## SpellCaster drives the lifecycle: start_cast() on press, hold_cast() every
## physics frame while held (skipped if instant), end_cast() on release.
##
## COOLDOWNS live here but are DRIVEN BY SpellCaster: it ticks every child's
## timer (tick_cooldown), refuses a press while is_on_cooldown(), and calls
## begin_cooldown() once the cast has actually happened -- on press for instant
## spells, on release for held ones, so holding a grab doesn't burn the timer.
## Deliberately NOT folded into can_cast(): subclasses override that for their
## own validity rules (TelekinesisGrabSpell needs something grabbable in front
## of it) and would silently drop the cooldown gate by not calling super().

@export var trigger_action: String = ""
## If true, start_cast() fires once on press and there is no hold/release phase.
@export var instant: bool = false
## Mana spent when the cast begins (0 = free). Checked/charged by SpellCaster
## via try_pay_cost() at press time; a cast that can't be afforded doesn't fire.
@export var mana_cost: float = 0.0
## Seconds before this spell can be cast again (0 = no cooldown). The value here
## is the BASE: begin_cooldown() scales it by the player's DEX-derived
## ProgressionSystem.cooldown_multiplier(). SpellDefinition.cooldown in
## MockSpellbook mirrors this number for display only -- keep the two in step.
@export var cooldown: float = 0.0

var is_active: bool = false

## Seconds left on the current cooldown, and the full duration it started at
## (which is the scaled duration, not `cooldown`, so the HUD sweep is accurate).
var _cooldown_left: float = 0.0
var _cooldown_total: float = 0.0

@onready var caster: SpellCaster = get_parent()


func can_cast() -> bool:
	return true


# --- Cooldown ----------------------------------------------------------------

## True while this spell is still recovering. Overridable for spells where some
## presses aren't a fresh cast at all (see StickyBombSpell's remote detonation).
func is_on_cooldown() -> bool:
	return _cooldown_left > 0.0


## Puts the spell on cooldown, scaled by the player's cooldown multiplier (DEX).
## Read live rather than cached so spending a point applies to the very next cast.
func begin_cooldown() -> void:
	if cooldown <= 0.0:
		return
	var duration := cooldown
	var prog := get_node_or_null("/root/PlayerProgression") as ProgressionSystem
	if prog:
		duration *= prog.cooldown_multiplier()
	_cooldown_total = duration
	_cooldown_left = duration


## Advances the timer. Called by SpellCaster every physics frame -- centralised
## there rather than in a _physics_process here, so a subclass that needs its own
## per-frame work can't accidentally stop its cooldown by forgetting super().
func tick_cooldown(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)


## Seconds still to wait, for HUD readouts.
func cooldown_remaining() -> float:
	return _cooldown_left


## 1.0 the instant the cooldown starts down to 0.0 when ready -- what the HUD
## slot's sweep is drawn from.
func cooldown_ratio() -> float:
	if _cooldown_total <= 0.0:
		return 0.0
	return clampf(_cooldown_left / _cooldown_total, 0.0, 1.0)


## Clears any active cooldown (respec/debug/level transitions).
func reset_cooldown() -> void:
	_cooldown_left = 0.0
	_cooldown_total = 0.0


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


## Raycasts from the camera through the crosshair, excluding the caster's own
## body, and hands back the raw intersect_ray dictionary (empty on a miss).
## Shared by every spell that acts on "whatever the player is looking at" --
## ProjectileSpell aims its spawn with it, ShadowTendril picks its target with it.
func aim_ray(distance: float) -> Dictionary:
	var cam := _get_camera()
	var player := _get_player()
	if cam == null or player == null:
		return {}
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * distance
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [player.get_rid()])
	return cam.get_world_3d().direct_space_state.intersect_ray(query)


func _get_camera() -> Camera3D:
	return caster.camera


func _get_player() -> CharacterBody3D:
	return caster.player
