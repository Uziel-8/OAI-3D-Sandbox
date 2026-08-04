class_name ShadowTendril
extends Node3D
## The thing Shadow Tendril actually spawns: a claw of living shadow that bursts
## out of the ground under a target, holds it for a few seconds, then sinks back.
##
## The claws are BUILT AT RUNTIME rather than modelled, the same approach
## SpiderWalker takes with its legs -- there is no shadow art in the project, and
## it keeps the whole spell drop-in. Each claw is re-oriented every frame from a
## base point on a ring to a tip point that curls inward as it rises, so the
## motion is one lerp rather than an animation resource.
##
## Holding is the duck-typed apply_root(duration) convention (the sibling of
## apply_impulse): this script never learns what it caught, it just checks
## has_method. See SpiderWalker/Npc/PlayerController for the implementations.

## Emitted when the tendril lets go, whether the hold ran out or was broken.
signal released(tendril: ShadowTendril)

enum Phase { RISING, HOLDING, RETRACTING }

@export_group("Shape")
@export var tendril_count: int = 4
## Radius of the ring the claws erupt from, around the target's feet.
@export var ring_radius: float = 0.55
@export var claw_height: float = 1.7
@export var claw_radius: float = 0.14
## How far the tips lean in toward the target at full height, as a fraction of
## ring_radius. 1.0 closes them into a point over the target's head.
@export var curl: float = 0.75

@export_group("Timing")
@export var rise_time: float = 0.22
@export var retract_time: float = 0.35
## Amplitude and rate of the idle writhe while holding, so it doesn't look frozen.
@export var writhe_amount: float = 0.09
@export var writhe_speed: float = 3.4

@export_group("Look")
@export var claw_color: Color = Color("2d1f5e")

@onready var _burst_particles: GPUParticles3D = get_node_or_null("BurstParticles")

var _target: Node3D
var _receiver: DamageReceiver
var _phase: Phase = Phase.RISING
var _elapsed: float = 0.0
var _hold_duration: float = 3.0
var _retract_elapsed: float = 0.0
var _released: bool = false
## Ground height the claws erupt from; the ring follows the target horizontally
## but never rides up with them.
var _ground_y: float = 0.0
var _claws: Array[MeshInstance3D] = []


func _ready() -> void:
	_build_claws()
	_ground_y = global_position.y
	if _burst_particles:
		_burst_particles.restart()


## Grabs `target` for `duration` seconds. With `break_on_damage` the grip fails
## the moment the target takes a wound, so the hold is a setup tool rather than a
## free damage window. Safe to call on anything: a target that can't be rooted
## still gets the visual, it just isn't held.
func ensnare(target: Node3D, duration: float, break_on_damage: bool = true) -> void:
	_target = target
	_hold_duration = maxf(duration, 0.0)
	if target and target.has_method("apply_root"):
		target.apply_root(_hold_duration)

	_receiver = DamageReceiver.find_in(target)
	if _receiver:
		# A target that dies mid-hold leaves the tendril sinking back on its own
		# rather than being taken to the grave with it -- same reasoning as the
		# sticky bomb outliving what it stuck to.
		_receiver.died.connect(_on_target_died)
		if break_on_damage:
			_receiver.damaged.connect(_on_target_damaged)


func _process(delta: float) -> void:
	_elapsed += delta

	match _phase:
		Phase.RISING:
			if _elapsed >= rise_time:
				_phase = Phase.HOLDING
		Phase.HOLDING:
			if _elapsed >= _hold_duration:
				_begin_retract()
		Phase.RETRACTING:
			_retract_elapsed += delta
			if _retract_elapsed >= retract_time:
				queue_free()
				return

	_follow_target()
	_shape_claws()


## Tracks the target horizontally so a shove doesn't leave the claws behind, but
## keeps the ring at the ground height it erupted from.
func _follow_target() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var pos := _target.global_position
	global_position = Vector3(pos.x, _ground_y, pos.z)


func _begin_retract() -> void:
	if _phase == Phase.RETRACTING:
		return
	_phase = Phase.RETRACTING
	_retract_elapsed = 0.0
	_disconnect_receiver()
	released.emit(self)


## Breaks the hold early and lets go of the target. Natural expiry deliberately
## does NOT call release_root(): the body is running its own countdown and will
## free itself on the same frame, and calling it would also cut short a SECOND
## tendril that had grabbed the same target later.
func _release_early() -> void:
	if _released:
		return
	_released = true
	if _target and is_instance_valid(_target) and _target.has_method("release_root"):
		_target.release_root()
	_begin_retract()


func _on_target_damaged(_amount: float, _remaining: float, _source: Node) -> void:
	_release_early()


func _on_target_died(_source: Node) -> void:
	# No release_root needed -- whatever it was is on its way out.
	_begin_retract()


func _disconnect_receiver() -> void:
	if _receiver == null or not is_instance_valid(_receiver):
		return
	if _receiver.damaged.is_connected(_on_target_damaged):
		_receiver.damaged.disconnect(_on_target_damaged)
	if _receiver.died.is_connected(_on_target_died):
		_receiver.died.disconnect(_on_target_died)


# --- Procedural claws ---------------------------------------------------------

func _build_claws() -> void:
	var material := StandardMaterial3D.new()
	# Unshaded so it reads as a silhouette of absence rather than a lit object --
	# a shaded near-black mesh just disappears into a dark floor.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = claw_color

	# Height 1.0 so a claw's length is just its Y scale each frame.
	var mesh := CylinderMesh.new()
	mesh.height = 1.0
	mesh.bottom_radius = claw_radius
	mesh.top_radius = claw_radius * 0.12
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.material = material

	for i in tendril_count:
		var claw := MeshInstance3D.new()
		claw.mesh = mesh
		claw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(claw)
		_claws.append(claw)


## Re-derives every claw's transform from its base and tip. Doing it from two
## points rather than composing rotations keeps "curls inward as it rises" a
## single lerp with no chance of the lean going the wrong way.
func _shape_claws() -> void:
	var rise := _rise_amount()
	if rise <= 0.001:
		for claw in _claws:
			claw.visible = false
		return

	var time := float(Time.get_ticks_msec()) * 0.001
	for i in _claws.size():
		var claw := _claws[i]
		claw.visible = true

		var angle := TAU * (float(i) + 0.5) / float(_claws.size())
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var tangent := Vector3.UP.cross(outward)

		var base := outward * ring_radius
		# The tip climbs and draws in toward the centre together, so a half-risen
		# claw is a shallow hook and a full one is closed over the target.
		var lean := ring_radius * curl * rise
		var writhe := sin(time * writhe_speed + float(i) * 1.7) * writhe_amount * rise
		var tip := outward * (ring_radius - lean) + Vector3.UP * (claw_height * rise) + tangent * writhe

		_orient(claw, base, tip)


func _orient(claw: MeshInstance3D, base: Vector3, tip: Vector3) -> void:
	var along := tip - base
	var length := along.length()
	if length < 0.001:
		claw.visible = false
		return
	var up_axis := along / length
	# Any vector not parallel to the claw works as the seed for the other two axes.
	var seed_axis := Vector3.FORWARD if absf(up_axis.z) < 0.9 else Vector3.RIGHT
	var x_axis := seed_axis.cross(up_axis).normalized()
	var z_axis := x_axis.cross(up_axis)
	# Basis columns are the local axes; scaling the Y column stretches the claw
	# along its own length (Basis.scaled() would scale in PARENT space instead).
	claw.transform = Transform3D(Basis(x_axis, up_axis * length, z_axis), (base + tip) * 0.5)


## 0 -> 1 as the claws erupt, back to 0 as they sink.
func _rise_amount() -> float:
	match _phase:
		Phase.RISING:
			return clampf(_elapsed / maxf(rise_time, 0.001), 0.0, 1.0)
		Phase.RETRACTING:
			return clampf(1.0 - _retract_elapsed / maxf(retract_time, 0.001), 0.0, 1.0)
		_:
			return 1.0
