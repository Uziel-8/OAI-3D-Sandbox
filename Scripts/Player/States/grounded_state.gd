extends PlayerFsmState
class_name GroundedState
## On the floor: idle / walk / run / sprint. Drives the locomotion blend from
## actual horizontal speed, and hands off to Jump (jump pressed) or Fall (walked
## off a ledge).

func enter(msg: Dictionary = {}) -> void:
	super.enter(msg)
	animator.travel("Grounded")


func physics_update(delta: float) -> void:
	player.apply_gravity(delta)

	if not player.is_on_floor():
		transition_to("Fall")
		return
	if player.can_jump and Input.is_action_just_pressed(player.input_jump):
		transition_to("Jump")
		return

	player.apply_horizontal_velocity(player.resolve_move_speed(delta))
	player.move_and_slide()

	animator.set_locomotion(player.planar_speed() / player.sprint_speed)
