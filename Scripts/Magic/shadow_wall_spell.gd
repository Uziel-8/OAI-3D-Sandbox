extends Spell
class_name ShadowWallSpell
## Wall of Night: raises a temporary, solid slab of shadow out of the ground
## wherever you are looking. Cover, a barricade, or a step to jump onto -- it
## deals no damage and holds nothing, it is just terrain you can make.
##
## Like ShadowTendrilSpell this acts on the WORLD directly rather than launching
## something at it, so it follows that template: aim with the shared
## Spell.aim_ray(), resolve the spot, and hand off to a self-contained scene that
## owns everything after the press. The spell keeps hold of what it raised only
## so it can enforce max_live_walls -- the same bookkeeping StickyBombSpell does
## for planted bombs.
##
## A press that can't find floor to raise a wall from costs nothing: can_cast()
## is checked before SpellCaster charges mana or starts the cooldown, exactly how
## TelekinesisGrabSpell treats a grab with nothing in reach.

## Scene raised at the aim point. Set on the .tscn.
@export var wall_scene: PackedScene
## How far the crosshair ray reaches before the wall is placed at its end.
@export var cast_range: float = 18.0
## Nearest the base of a wall may be raised, measured on the ground plane. Keeps
## a slab from erupting inside the caster; small enough to still wall yourself in
## or raise a step at your feet to jump onto.
@export var min_cast_distance: float = 1.2
## How far below the aim point to look for the floor the wall stands on.
@export var ground_probe: float = 6.0
## Nudge off the surface the aim ray struck before probing downward, so a wall
## aimed at a vertical face probes through open air instead of grazing that face.
@export var surface_clearance: float = 0.2
## How many walls one caster may have standing. Raising past the cap dissolves
## the oldest, so the level can't be quietly filled with permanent geometry.
@export var max_live_walls: int = 3

var _live: Array[ShadowWall] = []


func _init() -> void:
	instant = true


func can_cast() -> bool:
	return not _resolve_spot().is_empty()


func start_cast() -> void:
	if wall_scene == null:
		return
	var spot := _resolve_spot()
	if spot.is_empty():
		return

	var wall := wall_scene.instantiate() as ShadowWall
	if wall == null:
		return
	# Placed BEFORE add_child: a physics body moved after entering the tree
	# doesn't sync to the physics server until the frame ends, so it would spend
	# its first frame as a collider sitting at the world origin.
	wall.place(spot["position"], spot["yaw"])
	get_tree().current_scene.add_child(wall)
	wall.dissolved.connect(_on_wall_dissolved)
	_live.append(wall)

	_prune()
	while _live.size() > max_live_walls:
		var oldest: ShadowWall = _live[0]
		_live.remove_at(0)
		if is_instance_valid(oldest):
			oldest.dissolve()


## Where this press would raise a wall: {"position": base on the floor, "yaw":
## facing}, or an empty dictionary if there is nowhere valid. Doing the whole
## resolve in can_cast() as well means the raycasts run twice per press, which is
## what ShadowTendrilSpell does with _acquire_targets() and is cheaper than
## letting an impossible cast take the mana.
func _resolve_spot() -> Dictionary:
	var player := _get_player()
	var cam := _get_camera()
	if player == null or cam == null:
		return {}

	var hit := aim_ray(cast_range)
	var aim_point: Vector3
	if hit.is_empty():
		aim_point = cam.global_position - cam.global_transform.basis.z * cast_range
	else:
		# Step off the surface along its own normal, so the downward probe below
		# starts in open air whether that was a floor or a sheer wall face.
		var normal: Vector3 = hit.get("normal", Vector3.UP)
		aim_point = hit["position"] + normal * surface_clearance

	var floor_hit := _floor_under(aim_point, player)
	if floor_hit.is_empty():
		return {}

	var ground: Vector3 = floor_hit["position"]
	# Planar distance: the player's origin is at their feet, but the aim point
	# can be well above or below them, and only the footprint matters here.
	var to_player := player.global_position - ground
	to_player.y = 0.0
	if to_player.length() < min_cast_distance:
		return {}

	# Broad face toward the caster, so the slab reads as a barrier between you
	# and whatever is beyond it. +Z is the wall's thickness axis, hence the
	# atan2(x, z) form used everywhere else in the project for facing.
	return {"position": ground, "yaw": atan2(to_player.x, to_player.z)}


## The floor beneath `point` as a raw intersect_ray dictionary, empty when there
## is nothing to stand a wall on within ground_probe (out over a gap, or off the
## edge of the level). Empty-on-miss rather than a null sentinel, matching
## Spell.aim_ray.
func _floor_under(point: Vector3, player: CharacterBody3D) -> Dictionary:
	var space := player.get_world_3d().direct_space_state
	var from := point + Vector3.UP * 0.5
	var to := from + Vector3.DOWN * (ground_probe + 0.5)
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [player.get_rid()])
	return space.intersect_ray(query)


## Drops walls freed without signalling (a level torn down under them).
func _prune() -> void:
	for i in range(_live.size() - 1, -1, -1):
		if not is_instance_valid(_live[i]):
			_live.remove_at(i)


func _on_wall_dissolved(wall: ShadowWall) -> void:
	_live.erase(wall)
