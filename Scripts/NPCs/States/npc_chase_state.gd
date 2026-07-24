extends NpcState
class_name NpcChaseState
## Pursues the player, stopping just short (stop_distance) so it doesn't jitter
## into them. If the NPC's DEFAULT movement is STATIC/PATROL it gives up and
## returns there once the player escapes give_up_range; a pure CHASE archetype
## pursues relentlessly. Dealing damage on contact is a deliberate follow-up --
## give the NPC a DamageDealer and try_deal here (the "owner detects contact"
## convention), same as SpiderWalker.

func physics_update(delta: float) -> void:
	if npc.tick_stagger(delta):
		return
	npc.apply_gravity(delta)

	if not npc.has_player():
		transition_to(npc.default_movement_state_name())
		return

	var dist := npc.distance_to_player()
	if npc.default_movement != NpcProfile.Movement.CHASE and dist > npc.give_up_range:
		transition_to(npc.default_movement_state_name())
		return

	if dist > npc.stop_distance:
		npc.steer_towards(npc.player_position(), delta, npc.stop_distance)
	else:
		npc.face_towards(npc.player_position(), delta)
		npc.halt(delta)
	npc.move_and_slide()
