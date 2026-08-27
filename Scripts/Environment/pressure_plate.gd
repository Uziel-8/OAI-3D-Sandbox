extends StaticBody3D
class_name PressurePlate
## A floor plate that presses down under weight and emits a signal -- the physical
## counterpart to DispositionReaction: a condition in the WORLD rather than in an
## NPC's head, wired to the same duck-typed target call.
##
## Drop `Objects/pressure_plate.tscn` into a level and it works with no
## configuration: stand on it, or roll a barrel onto it. Three ways to use it,
## cheapest first:
##   * `target` + `press_method`/`release_method` -- defaults to open/close, so
##     plate-opens-gate is two nodes and one NodePath, no code.
##   * `pressed` / `released` signals -- for anything else.
##   * a PressurePlateObjective under it -- makes it a level or sidequest step.
##
## It weighs what's on it rather than counting bodies: a RigidBody3D contributes
## its own `mass` (duck-typed, like apply_impulse -- anything exposing `mass`
## works), the player contributes `player_weight`, anything else
## `default_body_weight`. So `required_weight` can ask for two barrels, or for
## more than the player alone can provide -- the "weigh it down and walk away"
## puzzle, which is the whole reason weight beats presence here.
##
## STACKS COUNT. The detector is a tall column (`stack_height`) so a pile is
## sensed all the way up, and each sensed body is then checked for whether its
## weight actually BEARS on the plate -- resting on it, or on something that
## already does (see _resolve_supported). A body merely passing through the column
## -- a player mid-jump, a barrel in flight, anything on a walkway overhead --
## holds nothing up and is not weighed.
##
## The collider is deliberately SHALLOW and centred on the node origin, so a plate
## placed at floor level is ~4cm proud and not a curb the player has to climb.
## Only the mesh sinks when pressed; the collider never moves, so nothing standing
## on it can be jostled.

## Weight settled on the plate reached `required_weight`.
signal pressed(plate: PressurePlate)
## Weight came back off (never fires while `one_shot` is latched).
signal released(plate: PressurePlate)
## Any change in the load, for a scale readout or a debug label.
signal weight_changed(total: float, required: float)

## Give up resolving the support chain after this many passes -- one pass per
## layer of the stack, so this is the tallest pile that can be worked out.
const MAX_SUPPORT_PASSES := 8
## Bodies one downward probe will look at. A stack layer touches very few things.
const MAX_SUPPORT_HITS := 16

## Load needed to trip it. 1.0 = almost anything; the barrel's mass is 2.0 and the
## player counts as `player_weight`, so raise this to demand more than one thing.
@export var required_weight: float = 1.0
## What the player counts as. They're a CharacterBody3D, so they have no mass.
@export var player_weight: float = 5.0
## What anything else without a `mass` counts as -- NPCs, spiders, a shadow wall.
@export var default_body_weight: float = 3.0
## How tall a stack is sensed, measured up from just above the plate. A barrel is
## 1.2m, so the default is about three of them. Raise it for taller piles; there's
## little cost to a generous column, since unsupported bodies are filtered out.
@export var stack_height: float = 4.0
## Only bodies in one of these groups count. Empty = everything counts.
@export var accepted_groups: Array[StringName] = []
## Latch down once tripped: the weight can come off and it stays pressed. Right for
## "step here and the door stays open". Call unlatch() to reset the puzzle.
@export var one_shot: bool = false

@export_group("Reaction")
## Acted on directly when the plate trips, so a gate needs no script. Duck-typed:
## the method is only called if the target actually has it.
@export var target: Node
@export var press_method: StringName = &"open"
## Blank = do nothing when the weight comes off (a plate that only ever opens).
@export var release_method: StringName = &"close"

@export_group("Appearance")
## How far the mesh sinks. The collider stays put either way.
@export var press_depth: float = 0.04
@export var press_time: float = 0.12
## Tints the placeholder mesh idle/pressed. Clear it once there's real art.
@export var tint_mesh: bool = true
@export var idle_color: Color = Color(0.35, 0.33, 0.30)
@export var pressed_color: Color = Color(0.85, 0.55, 0.20)

@export_group("Tuning")
## How far below a body to look for whatever is holding it up. Needs to clear the
## small separation the physics engine keeps between resting bodies.
@export var support_probe: float = 0.06
## How often the load is re-checked while the column holds anything. Nothing is
## polled while it's empty.
@export var poll_interval: float = 0.1

var is_pressed: bool = false

@onready var _mesh: MeshInstance3D = get_node_or_null("Mesh")
@onready var _area: Area3D = get_node_or_null("DetectionArea")

## instance_id -> weight, for everything SENSED in the column (supported or not).
## Ids, not node references, so a body freed while standing on the plate can't
## leave a dangling reference here -- and a freed Object compares EQUAL to null in
## Godot 4, which makes references worse than useless as keys.
var _loads: Dictionary = {}
var _total_weight: float = 0.0
var _mesh_rest: Vector3 = Vector3.ZERO
var _material: StandardMaterial3D = null
var _tween: Tween = null
var _poll_accum: float = 0.0


func _ready() -> void:
	add_to_group("pressure_plate")
	if _mesh:
		_mesh_rest = _mesh.position
	_setup_material()
	if _area == null:
		push_warning("PressurePlate '%s': no DetectionArea child -- it can never trip." % name)
		return
	_setup_detector()
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	# Stacking a barrel DOES fire an Area3D event for it, but the moment it stops
	# falling and starts resting does not -- so a barrel dropped onto the pile
	# would land unnoticed and never be weighed. Re-check while the column holds
	# anything at all; costs nothing while it's empty.
	if _loads.is_empty():
		return
	_poll_accum += delta
	if _poll_accum < poll_interval:
		return
	_poll_accum = 0.0
	_recompute()


## The load currently bearing on the plate, for a readout or a scale puzzle.
func current_weight() -> float:
	return _total_weight


## Trips the plate regardless of what's on it -- a lever, a cutscene, a debug key.
func force_press() -> void:
	_set_pressed(true)


## Releases a latched `one_shot` plate so it can trip again. Re-evaluates
## immediately afterwards, since something may still be standing on it.
func unlatch() -> void:
	if not is_pressed:
		return
	is_pressed = false
	_animate(false)
	_call_target(release_method)
	released.emit(self)
	_set_pressed(_total_weight >= required_weight)


func _on_body_entered(body: Node3D) -> void:
	# The Area3D sees our own StaticBody3D as an overlap; without this the plate
	# would weigh itself and sit permanently pressed.
	if body == self or not _accepts(body):
		return
	_loads[body.get_instance_id()] = _weight_of(body)
	_recompute()


func _on_body_exited(body: Node3D) -> void:
	if _loads.erase(body.get_instance_id()):
		_recompute()


func _accepts(body: Node3D) -> bool:
	if accepted_groups.is_empty():
		return true
	for group in accepted_groups:
		if body.is_in_group(group):
			return true
	return false


func _weight_of(body: Node3D) -> float:
	if "mass" in body:
		return maxf(0.0, body.mass)
	if body.is_in_group(&"player"):
		return player_weight
	return default_body_weight


func _recompute() -> void:
	var candidates: Array[PhysicsBody3D] = []
	for id: int in _loads.keys():
		# Belt and braces: a body freed while on the plate normally emits
		# body_exited on leaving the tree, but a dead id would otherwise hold the
		# plate down forever. keys() is a fresh array, so erasing here is safe.
		var body := instance_from_id(id) as PhysicsBody3D
		if body == null:
			_loads.erase(id)
			continue
		candidates.append(body)

	var total := 0.0
	for id: int in _resolve_supported(candidates):
		total += _loads[id]

	if is_equal_approx(total, _total_weight):
		return
	_total_weight = total
	weight_changed.emit(total, required_weight)
	_set_pressed(total >= required_weight)


## Works out which of the sensed bodies actually bear on the plate, so a stack is
## weighed in full but a body merely passing through the column is not.
##
## One pass settles the layer resting directly on the plate, the next settles what
## rests on THAT, and so on -- a fixed point, reached in as many passes as the
## stack is tall. Bailing as soon as a whole pass adds nothing means the common
## case costs one extra sweep rather than MAX_SUPPORT_PASSES of them.
func _resolve_supported(candidates: Array[PhysicsBody3D]) -> Dictionary:
	var supported: Dictionary = {}
	if candidates.is_empty() or _area == null:
		return supported
	var space := get_world_3d().direct_space_state
	if space == null:
		return supported

	var pending: Array[PhysicsBody3D] = candidates.duplicate()
	for _pass: int in MAX_SUPPORT_PASSES:
		var still: Array[PhysicsBody3D] = []
		for body: PhysicsBody3D in pending:
			if _rests_on_stack(space, body, supported):
				supported[body.get_instance_id()] = true
			else:
				still.append(body)
		if still.size() == pending.size():
			break  # a whole pass resolved nothing -- the remainder is unsupported
		pending = still
		if pending.is_empty():
			break
	return supported


## True if `body` is held up by the plate itself or by something already known to
## be. Probes with the body's OWN collision shapes dropped a few cm, rather than a
## ray from its origin, so a barrel resting off-centre or overhanging the one below
## is still seen to be resting on it.
func _rests_on_stack(space: PhysicsDirectSpaceState3D, body: PhysicsBody3D, supported: Dictionary) -> bool:
	var rid := body.get_rid()
	var query := PhysicsShapeQueryParameters3D.new()
	query.exclude = [rid]
	query.collision_mask = _area.collision_mask
	query.margin = 0.0
	var body_y := body.global_position.y

	for i: int in PhysicsServer3D.body_get_shape_count(rid):
		query.shape_rid = PhysicsServer3D.body_get_shape(rid, i)
		var xform := body.global_transform * PhysicsServer3D.body_get_shape_transform(rid, i)
		xform.origin.y -= support_probe
		query.transform = xform
		for hit: Dictionary in space.intersect_shape(query, MAX_SUPPORT_HITS):
			var other := hit.get("collider") as Node3D
			if other == null:
				continue
			if other == self:
				return true  # resting directly on the plate
			# Only something genuinely BELOW can be holding this up. Without the
			# height test a barrel sitting on the floor and merely touching the
			# side of the stack would inherit the stack's support and be weighed.
			# Known limit: this compares ORIGINS, so a body resting on its own
			# scenery ABOVE floor level, jutting into the column and leaning on
			# the pile, is still weighed (verified: reads 6.0 where the stack
			# alone is 4.0). It takes a pedestal beside the plate to arrange; at
			# floor level it cannot happen, because the plate collider is WIDER
			# than the sense column, so anything sensed down there is genuinely
			# on the plate. Erring toward counting is deliberate -- a puzzle
			# that will not trigger reads as broken, one that triggers a little
			# eagerly reads as generous.
			if other.global_position.y < body_y and supported.has(other.get_instance_id()):
				return true
	return false


func _set_pressed(value: bool) -> void:
	if value == is_pressed:
		return
	if not value and one_shot:
		return  # latched: the weight came off, but the plate stays down
	is_pressed = value
	_animate(value)
	if value:
		_call_target(press_method)
		pressed.emit(self)
	else:
		_call_target(release_method)
		released.emit(self)


func _call_target(method: StringName) -> void:
	if String(method).is_empty():
		return
	# is_instance_valid, never `== null`: a freed node compares equal to null.
	if target and is_instance_valid(target) and target.has_method(method):
		target.call(method)


func _animate(down: bool) -> void:
	if _mesh == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_mesh, "position", _mesh_rest - Vector3(0, press_depth, 0) if down else _mesh_rest, press_time)
	if _material:
		_tween.tween_property(_material, "albedo_color", pressed_color if down else idle_color, press_time)


## Raises the detector to `stack_height` so a whole pile is sensed. Keeps the
## authored footprint and floor and only moves the ceiling, so the column still
## starts just above the plate's own collider.
func _setup_detector() -> void:
	var shape_node: CollisionShape3D = null
	for child in _area.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			shape_node = child
			break
	if shape_node == null:
		push_warning("PressurePlate '%s': DetectionArea has no BoxShape3D to raise." % name)
		return
	# An owned copy: the authored box is a SHARED sub-resource, so resizing it in
	# place would give every plate in the level this one's column. Same trap as
	# the material below.
	var box: BoxShape3D = (shape_node.shape as BoxShape3D).duplicate()
	var base_y := shape_node.position.y - box.size.y * 0.5
	box.size = Vector3(box.size.x, stack_height, box.size.z)
	shape_node.shape = box
	shape_node.position.y = base_y + stack_height * 0.5


func _setup_material() -> void:
	if not tint_mesh or _mesh == null:
		return
	# An owned copy: a .tscn sub-resource is SHARED by every instance of that
	# scene, so tinting the authored material would tint every plate in the level.
	# Same immutability discipline as NpcProfile and ShopKeeper.stock.
	var base := _mesh.get_active_material(0)
	_material = base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
	_material.albedo_color = idle_color
	_mesh.set_surface_override_material(0, _material)
