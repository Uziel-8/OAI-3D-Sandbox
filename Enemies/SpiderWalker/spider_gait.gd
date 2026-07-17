extends Node
## Procedural gait controller: no animation clips. Each leg has a "home"
## position fixed relative to the body. When a planted foot drifts too far
## from its home (body moved/turned), it steps along an arc to a point
## slightly ahead of home, overshooting in the direction of travel. Legs are
## split into 2 diagonal groups; a group may only step while the other
## group is fully planted, producing a classic alternating tetrapod gait.
## Body height/tilt are derived from the current foot contact points so the
## body visually rides the terrain the feet are standing on.

## ---- Tuning parameters --------------------------------------------------
@export var step_threshold: float = 0.55
@export var step_duration: float = 0.2
@export var step_height: float = 0.25
@export var overshoot_factor: float = 0.35
@export var ride_height: float = 0.55
@export var tilt_smoothing: float = 8.0

const RAY_LENGTH := 3.0
## Perimeter walk order (fl, fr, br, bl) used for the plane-fit only, so the
## quad isn't self-intersecting. Index order otherwise matches setup().
const PLANE_ORDER := [0, 1, 3, 2]

enum FootState { PLANTED, STEPPING }


class LegRuntime:
	var foot_target: Marker3D
	var raycast: RayCast3D
	var home_local: Vector3
	var group: int
	var state: int = FootState.PLANTED
	var planted_pos: Vector3
	var step_from: Vector3
	var step_to: Vector3
	var step_t: float = 0.0


var _body: CharacterBody3D
var _visual: Node3D
var _legs: Array[LegRuntime] = []
var _stepping_count_by_group: Array[int] = [0, 0]


## Dependency injection: called once by the owning SpiderWalker after it has
## built the skeleton/foot targets/raycasts, instead of wiring via @export
## (these are runtime-built nodes, not scene references the inspector could
## fill in ahead of time).
func setup(body: CharacterBody3D, visual: Node3D, leg_configs: Array) -> void:
	_body = body
	_visual = visual
	_legs.clear()
	_stepping_count_by_group = [0, 0]

	for cfg in leg_configs:
		var leg := LegRuntime.new()
		leg.foot_target = cfg["foot_target"]
		leg.raycast = cfg["raycast"]
		leg.home_local = cfg["home_local"]
		leg.group = cfg["group"]
		var home_world := _body.global_transform * leg.home_local
		leg.planted_pos = _sample_ground(leg, home_world)
		if is_instance_valid(leg.foot_target):
			leg.foot_target.global_position = leg.planted_pos
		_legs.append(leg)


func update_gait(delta: float) -> void:
	if not is_instance_valid(_body) or _legs.is_empty():
		return
	var body_velocity := _body.velocity
	for leg in _legs:
		_update_leg(leg, delta, body_velocity)
	_update_body_visual(delta)


func _update_leg(leg: LegRuntime, delta: float, body_velocity: Vector3) -> void:
	if leg.state == FootState.STEPPING:
		leg.step_t = minf(leg.step_t + delta / step_duration, 1.0)
		var flat := leg.step_from.lerp(leg.step_to, leg.step_t)
		var arc := sin(leg.step_t * PI) * step_height
		if is_instance_valid(leg.foot_target):
			leg.foot_target.global_position = flat + Vector3.UP * arc
		if leg.step_t >= 1.0:
			leg.planted_pos = leg.step_to
			leg.state = FootState.PLANTED
			_stepping_count_by_group[leg.group] -= 1
		return

	# Planted: foot stays world-locked, independent of body motion, until it
	# is kicked off by the distance check below.
	if is_instance_valid(leg.foot_target):
		leg.foot_target.global_position = leg.planted_pos

	var home_world := _body.global_transform * leg.home_local
	var planar_dist := Vector2(leg.planted_pos.x - home_world.x, leg.planted_pos.z - home_world.z).length()
	if planar_dist <= step_threshold:
		return

	# Diagonal gait gate: this leg's group may only start a new step while
	# the other group has no legs currently in the air.
	var other_group := 1 - leg.group
	if _stepping_count_by_group[other_group] > 0:
		return

	var overshoot_home := home_world + body_velocity * overshoot_factor
	leg.step_from = leg.planted_pos
	leg.step_to = _sample_ground(leg, overshoot_home)
	leg.step_t = 0.0
	leg.state = FootState.STEPPING
	_stepping_count_by_group[leg.group] += 1


func _sample_ground(leg: LegRuntime, above_point: Vector3) -> Vector3:
	if not is_instance_valid(leg.raycast):
		return above_point
	leg.raycast.global_position = Vector3(above_point.x, above_point.y + RAY_LENGTH * 0.5, above_point.z)
	leg.raycast.force_raycast_update()
	if leg.raycast.is_colliding():
		return Vector3(above_point.x, leg.raycast.get_collision_point().y, above_point.z)
	return above_point


func _update_body_visual(delta: float) -> void:
	if not is_instance_valid(_visual) or not is_instance_valid(_body) or _legs.size() != 4:
		return

	var ground_points: Array[Vector3] = []
	var planted_sum_y := 0.0
	var planted_count := 0
	for leg in _legs:
		var ground_p: Vector3
		if leg.state == FootState.PLANTED:
			ground_p = leg.planted_pos
			planted_sum_y += ground_p.y
			planted_count += 1
		else:
			# Use the flat (non-arced) point so a leg mid-step doesn't yank
			# the body upward with it.
			ground_p = leg.step_from.lerp(leg.step_to, leg.step_t)
		ground_points.append(ground_p)

	var avg_foot_y: float
	if planted_count > 0:
		avg_foot_y = planted_sum_y / planted_count
	else:
		avg_foot_y = (ground_points[0].y + ground_points[1].y + ground_points[2].y + ground_points[3].y) * 0.25

	var perimeter: Array[Vector3] = []
	for idx in PLANE_ORDER:
		perimeter.append(ground_points[idx])
	var target_up := _fit_plane_normal(perimeter)

	var t := 1.0 - exp(-tilt_smoothing * delta)

	var target_local_y := (avg_foot_y + ride_height) - _body.global_position.y
	_visual.position.y = lerpf(_visual.position.y, target_local_y, t)

	var current_forward := -_visual.transform.basis.z
	var flat_forward := current_forward - target_up * current_forward.dot(target_up)
	if flat_forward.length() < 0.001:
		flat_forward = current_forward
	flat_forward = flat_forward.normalized()
	var right := flat_forward.cross(target_up).normalized()
	var forward := target_up.cross(right).normalized()
	var target_basis := Basis(right, target_up, -forward).orthonormalized()
	_visual.transform.basis = _visual.transform.basis.slerp(target_basis, t)


func _fit_plane_normal(points: Array[Vector3]) -> Vector3:
	# Newell's method; points must be given in perimeter (non-crossing) order.
	var normal := Vector3.ZERO
	var count := points.size()
	for i in count:
		var current := points[i]
		var next := points[(i + 1) % count]
		normal.x += (current.y - next.y) * (current.z + next.z)
		normal.y += (current.z - next.z) * (current.x + next.x)
		normal.z += (current.x - next.x) * (current.y + next.y)
	if normal.length() < 0.0001:
		return Vector3.UP
	if normal.y < 0.0:
		normal = -normal
	return normal.normalized()
