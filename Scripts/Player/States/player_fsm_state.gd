extends FsmState
class_name PlayerFsmState
## Base for the player's movement states. Resolves the player body + animator
## (lazily, so node/group ready-order doesn't matter) and handles the freefly
## toggle generically, so every movement state can flip noclip on/off. Concrete
## states override enter()/physics_update() and should call super.enter(msg).

var player: PlayerController
var animator: PlayerAnimator


func enter(_msg: Dictionary = {}) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as PlayerController
	if animator == null:
		animator = get_tree().get_first_node_in_group("player_animator") as PlayerAnimator


func handle_input(event: InputEvent) -> void:
	# Freefly (noclip) toggle works from any movement state.
	if player and player.can_freefly and event.is_action_pressed(player.input_freefly):
		transition_to("Grounded" if name == "Freefly" else "Freefly")
