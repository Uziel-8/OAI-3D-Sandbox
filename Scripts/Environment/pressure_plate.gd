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

## Load needed to trip it. 1.0 = almost anything; the barrel's mass is 2.0 and the
## player counts as `player_weight`, so raise this to demand more than one thing.
@export var required_weight: float = 1.0
## What the player counts as. They're a CharacterBody3D, so they have no mass.
@export var player_weight: float = 5.0
## What anything else without a `mass` counts as -- NPCs, spiders, a shadow wall.
@export var default_body_weight: float = 3.0
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

var is_pressed: bool = false

@onready var _mesh: MeshInstance3D = get_node_or_null("Mesh")
@onready var _area: Area3D = get_node_or_null("DetectionArea")

## instance_id -> weight. Ids, not node references, so a body freed while standing
## on the plate can't leave a dangling reference here (and a freed Object compares
## EQUAL to null in Godot 4, which makes references worse than useless as keys).
var _loads: Dictionary = {}
var _total_weight: float = 0.0
var _mesh_rest: Vector3 = Vector3.ZERO
var _material: StandardMaterial3D = null
var _tween: Tween = null


func _ready() -> void:
	add_to_group("pressure_plate")
	if _mesh:
		_mesh_rest = _mesh.position
	_setup_material()
	if _area == null:
		push_warning("PressurePlate '%s': no DetectionArea child -- it can never trip." % name)
		return
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)


## The load currently on the plate, for a readout or a scale puzzle.
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
	var total := 0.0
	for id: int in _loads.keys():
		# Belt and braces: a body freed while on the plate normally emits
		# body_exited on leaving the tree, but a dead id would otherwise hold the
		# plate down forever. keys() is a fresh array, so erasing here is safe.
		if instance_from_id(id) == null:
			_loads.erase(id)
			continue
		total += _loads[id]
	if is_equal_approx(total, _total_weight):
		return
	_total_weight = total
	weight_changed.emit(total, required_weight)
	_set_pressed(total >= required_weight)


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
