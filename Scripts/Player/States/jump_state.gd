extends PlayerFsmState
class_name JumpState
## The upward part of a jump: kick velocity up on enter, allow air control, then
## hand off to Fall once we start descending.

func enter(msg: Dictionary = {}) -> void:
	super.enter(msg)
	player.velocity.y = player.jump_velocity
	animator.travel("Jump")


func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	player.apply_horizontal_velocity(player.base_speed)  # air control at walk speed
	player.move_and_slide()

	if player.velocity.y <= 0.0:
		transition_to("Fall")
