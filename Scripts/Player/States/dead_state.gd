extends PlayerFsmState
class_name DeadState
## Terminal state: play the death animation, freeze the player, then reload the
## scene once the clip has had time to play. Entered when the player's
## DamageReceiver emits `died` (its death_behavior is NONE, so this state owns the
## death flow instead of the receiver reloading instantly). Progression lives in
## autoloads, so the reload doesn't wipe XP/level.

## Seconds to hold on the death animation before reloading the scene.
@export var reload_delay: float = 2.5

var _timer: float = 0.0
var _reloading: bool = false


func enter(msg: Dictionary = {}) -> void:
	super.enter(msg)
	_timer = reload_delay
	_reloading = false
	player.velocity = Vector3.ZERO
	animator.play_death()


func physics_update(delta: float) -> void:
	# Settle under gravity but accept no directed movement.
	player.apply_gravity(delta)
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	player.move_and_slide()

	if _reloading:
		return
	_timer -= delta
	if _timer <= 0.0:
		_reloading = true
		get_tree().reload_current_scene()


func handle_input(_event: InputEvent) -> void:
	pass  # ignore the base freefly toggle etc. while dead
