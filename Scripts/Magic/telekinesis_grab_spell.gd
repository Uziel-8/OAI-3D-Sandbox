extends Spell
class_name TelekinesisGrabSpell

## Holds a RigidBody3D at a distance in front of the camera and lets it swing,
## bump, and collide naturally. Releasing while moving the mouse throws it -
## there is no separate throw button, the velocity just carries over.

@export var max_grab_distance: float = 6.0
@export var min_hold_distance: float = 1.5
@export var max_hold_distance: float = 5.0
@export var pull_speed: float = 12.0
@export var max_follow_speed: float = 14.0
@export var angular_damping: float = 10.0
@export var scroll_step: float = 0.5

@onready var particles: GPUParticles3D = $GrabParticles

var held_body: RigidBody3D = null
var hold_distance: float = 3.0
var _original_gravity_scale: float = 1.0


func can_cast() -> bool:
	return held_body == null and not _find_grabbable().is_empty()


func start_cast() -> void:
	var hit := _find_grabbable()
	if hit.is_empty():
		is_active = false
		return
	held_body = hit.collider
	_original_gravity_scale = held_body.gravity_scale
	held_body.gravity_scale = 0.0
	held_body.angular_velocity = Vector3.ZERO
	hold_distance = clamp(_get_camera().global_position.distance_to(hit.position), min_hold_distance, max_hold_distance)
	particles.global_position = held_body.global_position
	particles.emitting = true


func hold_cast(delta: float) -> void:
	if held_body == null or not is_instance_valid(held_body):
		held_body = null
		is_active = false
		particles.emitting = false
		return

	if Input.is_action_just_pressed("magic_scroll_up"):
		hold_distance = clamp(hold_distance + scroll_step, min_hold_distance, max_hold_distance)
	if Input.is_action_just_pressed("magic_scroll_down"):
		hold_distance = clamp(hold_distance - scroll_step, min_hold_distance, max_hold_distance)

	var cam := _get_camera()
	var target_pos := cam.global_position - cam.global_transform.basis.z * hold_distance
	var to_target := target_pos - held_body.global_position

	var desired_velocity := to_target * pull_speed
	if desired_velocity.length() > max_follow_speed:
		desired_velocity = desired_velocity.normalized() * max_follow_speed

	held_body.linear_velocity = desired_velocity
	held_body.angular_velocity = held_body.angular_velocity.lerp(Vector3.ZERO, clamp(angular_damping * delta, 0.0, 1.0))
	particles.global_position = held_body.global_position


func end_cast() -> void:
	if held_body and is_instance_valid(held_body):
		held_body.gravity_scale = _original_gravity_scale
	held_body = null
	particles.emitting = false


func _find_grabbable() -> Dictionary:
	var cam := _get_camera()
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * max_grab_distance
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [_get_player().get_rid()])
	var result := cam.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return {}
	if not (result.collider is RigidBody3D) or not result.collider.is_in_group("grabbable"):
		return {}
	return result
