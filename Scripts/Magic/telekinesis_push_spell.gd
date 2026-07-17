extends Spell
class_name TelekinesisPushSpell

## Instant force blast: raycasts to find a point of impact, then applies a
## radial impulse to everything in a small sphere around it that exposes an
## apply_impulse() method -- RigidBody3D has this built in; other actors
## (e.g. SpiderWalker) can opt in by implementing the same method/signature.

@export var push_range: float = 8.0
@export var push_radius: float = 1.75
@export var push_force: float = 10.0

@onready var particles: GPUParticles3D = $PushParticles


func _init() -> void:
	instant = true


func start_cast() -> void:
	var cam := _get_camera()
	var player_rid := _get_player().get_rid()

	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * push_range
	var ray_query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [player_rid])
	var ray_result := cam.get_world_3d().direct_space_state.intersect_ray(ray_query)
	var origin: Vector3 = ray_result.position if not ray_result.is_empty() else to

	particles.global_position = origin
	particles.restart()

	var shape := SphereShape3D.new()
	shape.radius = push_radius
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = shape
	shape_query.transform = Transform3D(Basis(), origin)
	shape_query.exclude = [player_rid]

	var hits := cam.get_world_3d().direct_space_state.intersect_shape(shape_query, 16)
	for hit in hits:
		var body: Node = hit.collider
		if not body.has_method("apply_impulse"):
			continue
		var offset = body.global_position - origin
		var dir = offset.normalized() if offset.length() > 0.01 else -cam.global_transform.basis.z
		var falloff = 1.0 - clamp(offset.length() / push_radius, 0.0, 1.0)
		body.apply_impulse(dir * push_force * max(falloff, 0.3))
