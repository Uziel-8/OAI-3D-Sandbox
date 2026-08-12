class_name ShadowWall
extends AnimatableBody3D
## The slab Wall of Night actually spawns: a temporary, SOLID barrier of shadow
## that erupts out of the ground, stands for a few seconds, then sinks away.
##
## It is an AnimatableBody3D rather than a StaticBody3D so it can move while
## being a real collider -- it starts fully sunk beneath its base point and
## rises into place, which is also what lets it shove/carry a CharacterBody3D
## standing where it comes up. (Not a RigidBody3D: a wall you can jump on
## shouldn't topple when a spider walks into it. Swap the root type if you ever
## want one that does.)
##
## Mesh and collision are BUILT AT RUNTIME from wall_size, the same approach
## ShadowTendril takes with its claws and the sticky bomb takes with its blast
## radius -- so the barrier's dimensions stay ONE exported number instead of
## also being baked into a CollisionShape that could silently drift out of sync.
##
## Because it is just a collider, everything else in the project reacts to it
## for free: projectiles burst on it, NPCs and spiders bump into it, and the
## player can stand, jump and cast from on top of it. Aiming a second wall at
## the first stacks them into a staircase.

## Emitted when the wall begins sinking, however that was triggered.
signal dissolved(wall: ShadowWall)

enum Phase { RISING, HOLDING, SINKING }

@export_group("Shape")
## Width, height and thickness. Drives the mesh, the collision box and how far
## the slab starts sunk, so there is only one number to change.
@export var wall_size: Vector3 = Vector3(4.0, 3.0, 0.45)

@export_group("Timing")
## Seconds the wall stands before it sinks on its own, measured from the cast.
@export var duration: float = 12.0
@export var rise_time: float = 0.45
@export var sink_time: float = 0.7

@export_group("Look")
@export var wall_color: Color = Color(0.13, 0.08, 0.28, 0.92)
## Emission/rim tint -- the violet edge that keeps a near-black slab readable
## against a dark floor. Matches the Shadow school accent.
@export var edge_color: Color = Color("7a4fd0")

@onready var _rise_particles: GPUParticles3D = get_node_or_null("RiseParticles")

var _phase: Phase = Phase.RISING
var _elapsed: float = 0.0
var _sink_elapsed: float = 0.0
## World positions of the slab's base, standing and fully buried.
var _risen_position: Vector3 = Vector3.ZERO
var _sunk_position: Vector3 = Vector3.ZERO
var _placed: bool = false
var _material: StandardMaterial3D


func _ready() -> void:
	_build_body()
	if _placed:
		# Re-assert in world space now there IS a parent: place() runs before
		# add_child (so the collider is never live at the origin for a frame,
		# per the physics-sync rule) and can only set a local position there.
		global_position = _sunk_position
	else:
		# Dropped into a level by hand: treat where it was authored as where it
		# stands, and emerge into it just the same.
		_risen_position = global_position
		_sunk_position = _risen_position + basis * _emerge_offset()
		global_position = _sunk_position
	if _rise_particles:
		_rise_particles.restart()


## Positions the slab to emerge at `base_position` -- the point _slab_offset()
## is measured from, which for a wall is where its BOTTOM face ends up -- turned
## to `yaw` radians. Called by ShadowWallSpell BEFORE add_child: a body moved
## after entering the tree doesn't reach the physics server until the frame ends,
## so it would spend one frame colliding at the world origin.
func place(base_position: Vector3, yaw: float) -> void:
	rotation = Vector3(0.0, yaw, 0.0)
	_risen_position = base_position
	_sunk_position = base_position + Basis.from_euler(Vector3(0.0, yaw, 0.0)) * _emerge_offset()
	position = _sunk_position
	_placed = true


## Sinks the wall early. Used when the caster exceeds their standing-wall cap,
## and safe to call from anything else that wants a barrier gone.
func dissolve() -> void:
	if _phase == Phase.SINKING:
		return
	_phase = Phase.SINKING
	_sink_elapsed = 0.0
	dissolved.emit(self)


## Moved in _physics_process, not _process or a Tween: with sync_to_physics on,
## an AnimatableBody3D only interacts properly with characters standing on it if
## its transform changes during the physics step.
func _physics_process(delta: float) -> void:
	_elapsed += delta

	match _phase:
		Phase.RISING:
			if _elapsed >= rise_time:
				_phase = Phase.HOLDING
		Phase.HOLDING:
			if _elapsed >= duration:
				dissolve()
		Phase.SINKING:
			_sink_elapsed += delta
			if _sink_elapsed >= sink_time:
				queue_free()
				return

	_apply_motion()


func _apply_motion() -> void:
	global_position = _sunk_position.lerp(_risen_position, _emergence())
	if _material:
		# Only fades on the way out, and only partly: it stays solid while it is
		# visible, so a fading slab never reads as one you can walk through.
		_material.albedo_color.a = wall_color.a * _opacity()


## 0 while buried, 1 while standing -- smoothed so the slab punches up and
## settles rather than sliding at a constant rate.
func _emergence() -> float:
	match _phase:
		Phase.RISING:
			return smoothstep(0.0, 1.0, clampf(_elapsed / maxf(rise_time, 0.001), 0.0, 1.0))
		Phase.SINKING:
			var t := clampf(_sink_elapsed / maxf(sink_time, 0.001), 0.0, 1.0)
			return 1.0 - smoothstep(0.0, 1.0, t)
		_:
			return 1.0


func _opacity() -> float:
	if _phase != Phase.SINKING:
		return 1.0
	return 1.0 - clampf(_sink_elapsed / maxf(sink_time, 0.001), 0.0, 1.0)


# --- Shape hooks --------------------------------------------------------------
# The two things a different KIND of shadow construct needs to change. Override
# this pair and the whole emerge/hold/withdraw lifecycle comes along unaltered
# -- see ShadowBridge, which is a deck rather than a barrier and arrives by
# unfurling forward instead of rising.

## Where the slab sits relative to the body's ORIGIN, in local space. A wall
## stands its full height above the origin, so place() takes a floor point and
## nothing outside this file has to know how tall the slab is.
func _slab_offset() -> Vector3:
	return Vector3.UP * (wall_size.y * 0.5)


## Local offset of the hidden position the slab emerges FROM, rotated by yaw in
## place(). A wall starts one full height underground and rises out of the floor.
func _emerge_offset() -> Vector3:
	return Vector3.DOWN * wall_size.y


# --- Runtime construction -----------------------------------------------------

## Builds the mesh and the collider from wall_size, both sitting at
## _slab_offset() so where the body's origin lands is the shape's decision.
func _build_body() -> void:
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = wall_color
	# Shaded, unlike ShadowTendril's claws: a barrier has to read as a surface
	# with form and a top face you can aim a jump at, not a flat silhouette. The
	# emission and rim are what keep near-black legible on a dark floor.
	_material.emission_enabled = true
	_material.emission = edge_color
	_material.emission_energy_multiplier = 0.4
	_material.rim_enabled = true
	_material.rim = 0.75
	_material.roughness = 0.35

	var mesh := BoxMesh.new()
	mesh.size = wall_size
	mesh.material = _material

	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = _slab_offset()
	add_child(visual)

	var shape := BoxShape3D.new()
	shape.size = wall_size

	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = _slab_offset()
	add_child(collider)
