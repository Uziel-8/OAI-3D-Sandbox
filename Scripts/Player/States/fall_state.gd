extends PlayerFsmState
class_name FallState
## Airborne and descending (jumped over the top, or walked off a ledge). Air
## control continues; landing returns to Grounded.

func enter(msg: Dictionary = {}) -> void:
	super.enter(msg)
	animator.travel("Fall")


func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	player.apply_horizontal_velocity(player.base_speed)
	player.move_and_slide()

	if player.is_on_floor():
		transition_to("Grounded")
