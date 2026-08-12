class_name ShadowBridge
extends ShadowWall
## The deck Shadow Bridge lays down: the same slab of solid shadow as a Wall of
## Night, turned on its side and pointed away from you -- a road you can walk out
## over a gap, and that withdraws again a few seconds later.
##
## SUBCLASS, DON'T FORK, the same call StickyBombProjectile makes against
## Projectile: emerging, holding, withdrawing, the collider built from wall_size
## and the AnimatableBody3D physics are all inherited untouched. A bridge differs
## from a wall in exactly two ways, and they are the two hooks the base exposes:
## where the slab sits relative to its origin, and where it comes from.
##
## `wall_size` is read as (width, thickness, SPAN) here -- the long axis is +Z,
## which is also the direction you walk.

## The origin sits at the near end of the deck, on its WALKING SURFACE, so
## ShadowBridgeSpell can hand place() the spot you step off from and the top
## comes out flush with the caster's feet -- no lip to trip over stepping on.
func _slab_offset() -> Vector3:
	return Vector3(0.0, -wall_size.y * 0.5, wall_size.z * 0.5)


## Unfurls FORWARD out of its own near end rather than rising out of the floor,
## because the whole point of a bridge is that there is no floor under it. The
## far end sweeps out across the gap; withdrawing runs the same motion backward,
## so it retracts the way it came.
func _emerge_offset() -> Vector3:
	return Vector3(0.0, 0.0, -wall_size.z)
