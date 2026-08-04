extends CharacterBody3D
class_name SpiderWalker
## Procedural spider enemy. Fully self-contained: instance this scene as a
## child anywhere in a level (no code required) and it wanders on its own
## around wherever it was placed, or optionally chases the player. Owns
## locomotion and wires the skeleton builder + gait controller together at
## runtime. No animation clips anywhere -- all leg motion is IK driven by
## SpiderGait (spider_gait.gd / spider_skeleton_builder.gd).

## Optional gameplay tags (FLAMMABLE / LIVING / CONDUCTIVE). Authored ahead of the
## systems that will consume them -- nothing reads it yet, and leaving it unset is
## fine. Null-check it at the point of use when something finally does.
@export var tag_data : TagData
@export var move_speed: float = 2.5
@export var turn_speed: float = 6.0
@export var arrive_distance: float = 0.3

@export_group("Wander")
@export var wander_radius: float = 6.0
@export var wander_pause: float = 1.5

@export_group("Player Chase")
## If true, chases the first node in the "player" group whenever one exists
## in the scene, falling back to wandering if none is found.
@export var chase_player: bool = true

@export_group("Knockback")
## How long, after apply_impulse() lands, AI locomotion is suspended so the
## knockback is actually visible instead of being overwritten next frame.
@export var stagger_duration: float = 0.4
## How quickly the knockback velocity bleeds off while staggered.
@export var knockback_friction: float = 6.0

@export_group("Root")
## Planar distance at which a HELD spider can still land touch damage. A rooted
## spider can't move into the player, so move_and_slide() stops reporting them
## as a slide collision -- it's pinned, not defanged, so reach is checked
## directly while the root is up. Roughly body radius + player radius.
@export var held_reach: float = 1.4

# Radial leg layout (local X, local Z), order: front-left, front-right,
# back-left, back-right.
const LEG_DIRS: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
# Diagonal gait groups: group 0 = (front-left, back-right), group 1 = (front-right, back-left).
const LEG_GROUP: Array[int] = [0, 1, 1, 0]
const HIP_RADIUS := 0.35
const FOOT_RADIUS := 0.75
const RIDE_HEIGHT := 0.55
const KNEE_LIFT := 0.18

@onready var _visual: Node3D = $Visual
@onready var _skeleton: Node = $Visual/Skeleton3D
@onready var _gait: Node = $GaitController
@onready var _foot_targets: Node3D = $FootTargets
@onready var _leg_rays: Node3D = $Legs
## Optional touch-damage component; a spider without one is harmless to bump.
@onready var _damage_dealer: DamageDealer = get_node_or_null("DamageDealer")

var _player: Node3D
var _wander_origin: Vector3
var _wander_point: Vector3
var _wander_timer: float = 0.0
var _stagger_timer: float = 0.0
var _root_timer: float = 0.0


func _ready() -> void:
	# The generic enemy group: what "kill N of them" objectives count (see
	# KillCountObjective). New enemy types should join it too.
	add_to_group("enemy")
	# Wander is centered on wherever this instance was placed in the editor
	# (or spawned at runtime) -- no external configuration needed.
	_wander_origin = global_position
	_wander_point = _wander_origin
	_build_rig()


func _build_rig() -> void:
	var leg_dirs_3d: Array[Vector3] = []
	var foot_targets: Array[Marker3D] = []
	var leg_configs: Array = []

	for i in LEG_DIRS.size():
		var dir2 := LEG_DIRS[i].normalized()
		var dir3 := Vector3(dir2.x, 0.0, dir2.y)
		leg_dirs_3d.append(dir3)

		var foot_marker: Marker3D = _foot_targets.get_child(i)
		var raycast: RayCast3D = _leg_rays.get_child(i)
		var home_local := Vector3(dir3.x * FOOT_RADIUS, -RIDE_HEIGHT, dir3.z * FOOT_RADIUS)

		foot_marker.global_position = global_transform * home_local
		raycast.position = home_local + Vector3.UP * 1.5
		raycast.target_position = Vector3.DOWN * 3.0
		raycast.enabled = true

		foot_targets.append(foot_marker)
		leg_configs.append({
			"foot_target": foot_marker,
			"raycast": raycast,
			"home_local": home_local,
			"group": LEG_GROUP[i],
		})

	if is_instance_valid(_skeleton) and _skeleton.has_method("build"):
		_skeleton.build(leg_dirs_3d, HIP_RADIUS, FOOT_RADIUS, RIDE_HEIGHT, KNEE_LIFT, foot_targets)

	if is_instance_valid(_gait) and _gait.has_method("setup"):
		_gait.setup(self, _visual, leg_configs)


## Duck-typed counterpart to RigidBody3D.apply_impulse(), so spells (e.g.
## TelekinesisPushSpell) can affect this kinematic actor without knowing its
## concrete type -- they just check has_method("apply_impulse"). Since this
## is a CharacterBody3D, not a RigidBody3D, there's no physics solver to
## hand the impulse to: it's folded directly into velocity (treating mass as
## 1), and AI locomotion is suspended for stagger_duration so the knockback
## is visible instead of being overwritten by _update_locomotion() next frame.
func apply_impulse(impulse: Vector3, _position := Vector3.ZERO) -> void:
	velocity += impulse
	_stagger_timer = stagger_duration


## Duck-typed crowd control, the same convention as apply_impulse(): anything
## that wants to hold a body still (ShadowTendril today, snares/webs/traps later)
## calls this on whatever it caught, checked with has_method("apply_root").
## Pins locomotion for `duration` seconds -- the spider can still TURN and can
## still hurt what stands in it; it just can't go anywhere. Stacking takes the
## longer of the two rather than adding, so overlapping holds can't compound.
func apply_root(duration: float) -> void:
	_root_timer = maxf(_root_timer, duration)


## Ends a hold early (the tendril calls this when its grip is broken).
func release_root() -> void:
	_root_timer = 0.0


func is_rooted() -> bool:
	return _root_timer > 0.0


func _physics_process(delta: float) -> void:
	_update_locomotion(delta)
	# velocity is NOT multiplied by delta here -- move_and_slide() expects
	# velocity in units/second and integrates it internally.
	move_and_slide()
	if _damage_dealer:
		# Touch damage on contact with the player; the dealer's own cooldown
		# keeps this from landing every physics frame while touching.
		for i in get_slide_collision_count():
			var collider := get_slide_collision(i).get_collider()
			if collider is Node and collider.is_in_group("player"):
				_damage_dealer.try_deal(collider)
		if _root_timer > 0.0:
			_try_deal_at_reach()
	if is_instance_valid(_gait) and _gait.has_method("update_gait"):
		_gait.update_gait(delta)


## Touch damage while held. Planar distance only: the spider's origin sits at
## body height and the player's at their feet, so a 3D distance would read as
## out of reach while they're plainly standing in it.
func _try_deal_at_reach() -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(_player):
		return
	var to := _player.global_position - global_position
	to.y = 0.0
	if to.length() <= held_reach:
		_damage_dealer.try_deal(_player)


func _update_locomotion(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0

	# Root outranks stagger: something holding this body in place shouldn't be
	# undone by a knockback landing on it mid-hold.
	if _root_timer > 0.0:
		_root_timer -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		# Held, not disabled -- it keeps tracking its target so it's still facing
		# you (and still biting) when the grip lets go.
		var held_target := _current_target_position(delta)
		var to_held := held_target - global_position
		to_held.y = 0.0
		if to_held.length() > 0.001:
			var held_dir := to_held.normalized()
			rotation.y = lerp_angle(rotation.y, atan2(held_dir.x, held_dir.z), 1.0 - exp(-turn_speed * delta))
		return

	if _stagger_timer > 0.0:
		_stagger_timer -= delta
		# Let the knockback velocity bleed off instead of driving normal AI
		# locomotion this frame, so an apply_impulse() hit is actually visible.
		var horizontal := Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, knockback_friction * delta)
		velocity.x = horizontal.x
		velocity.z = horizontal.y
		return

	var target_pos := _current_target_position(delta)
	var to_target := target_pos - global_position
	to_target.y = 0.0
	var dist := to_target.length()

	if dist > arrive_distance:
		var dir := to_target / dist
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
		var target_yaw := atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))
	else:
		# move_toward's step here is a per-frame deceleration rate limit, not
		# the final velocity fed to move_and_slide(), so scaling it by delta
		# is correct and doesn't run afoul of "don't multiply velocity by
		# delta before move_and_slide()".
		velocity.x = move_toward(velocity.x, 0.0, move_speed * delta)
		velocity.z = move_toward(velocity.z, 0.0, move_speed * delta)


func _current_target_position(delta: float) -> Vector3:
	if chase_player:
		if not is_instance_valid(_player):
			_player = get_tree().get_first_node_in_group("player")
		if is_instance_valid(_player):
			return _player.global_position

	var to_wander := _wander_point - global_position
	to_wander.y = 0.0
	if to_wander.length() <= arrive_distance:
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_wander_timer = wander_pause
			var angle := randf() * TAU
			var radius := randf() * wander_radius
			_wander_point = _wander_origin + Vector3(cos(angle), 0.0, sin(angle)) * radius
	return _wander_point
