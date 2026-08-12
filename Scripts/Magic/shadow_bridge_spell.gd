extends ShadowWallSpell
class_name ShadowBridgeSpell
## Shadow Bridge: lays a road of solid shadow out from your feet in the direction
## you are facing. Cross a gap, climb nothing, cost nothing but mana -- and it
## works in mid-air, so a bridge cast on the way down is a way out of a fall.
##
## Extends ShadowWallSpell rather than Spell because everything after "where does
## it go" is already there: spawning the scene, place()-before-add_child, holding
## the live list, dissolving the oldest past the cap, pruning what a level
## teardown freed. All that is inherited; this overrides _resolve_spot() and
## nothing else. (It therefore also inherits the wall's placement exports --
## cast_range, min_cast_distance, ground_probe, surface_clearance -- which a
## bridge doesn't consult. wall_scene and max_live_walls DO apply: they mean the
## bridge scene and how many decks may stand.)
##
## A bridge is deliberately NOT aimed at a surface the way a wall is. It starts
## where you stand and runs where you look, so it can be cast over a hole, off a
## ledge, or out of thin air -- there is nothing for an aim ray to hit in any of
## those cases, which is exactly when you want one.

@export_group("Bridge")
## How far ahead of the caster's feet the near end of the deck begins. Enough to
## clear the floor they're standing on so the two don't fight over the same
## surface, close enough to step straight onto.
@export var start_offset: float = 0.8


## Straight out from the caster's feet along their flattened facing. The only way
## to fail is looking dead-on up or down, where there is no direction to lay a
## road in -- and a refused press costs no mana and starts no cooldown, since
## SpellCaster checks can_cast() first.
func _resolve_spot() -> Dictionary:
	var player := _get_player()
	var cam := _get_camera()
	if player == null or cam == null:
		return {}

	# Flattened: the deck is always level, however far down the drop is that
	# you're looking at. Pitch aims a wall; it only chooses a bridge's heading.
	var forward := -cam.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return {}
	forward = forward.normalized()

	# The player's origin is at their feet, and _slab_offset() puts the deck's
	# walking surface at the origin it's given -- so the road comes out exactly
	# level with the ground they're standing on.
	var base := player.global_position + forward * start_offset
	return {"position": base, "yaw": atan2(forward.x, forward.z)}
