extends NpcState
class_name NpcStaticState
## Holds position. If the NPC is hostile it breaks off to Chase once the player
## comes within chase_range -- so "static" is the default posture, not a promise
## never to move.

func physics_update(delta: float) -> void:
	if npc.tick_stagger(delta):
		return
	npc.apply_gravity(delta)
	npc.halt(delta)
	npc.move_and_slide()
	if npc.should_start_chase():
		transition_to("Chase")
