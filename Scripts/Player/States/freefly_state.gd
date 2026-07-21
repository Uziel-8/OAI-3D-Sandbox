extends PlayerFsmState
class_name FreeflyState
## Debug noclip: disables the collider and flies along the look direction. Entered
## / exited by the freefly toggle handled in PlayerFsmState. Gravity and
## move_and_slide are bypassed entirely (freefly_move uses move_and_collide).

func enter(msg: Dictionary = {}) -> void:
	super.enter(msg)
	player.enable_freefly()
	animator.travel("Fall")


func exit() -> void:
	if player:
		player.disable_freefly()


func physics_update(delta: float) -> void:
	player.freefly_move(delta)
