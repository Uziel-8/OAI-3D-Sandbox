extends AnimatableBody3D
class_name Gate
## A simple openable gate/door: open() slides it clear and disables its collision,
## close() reverses. Knows nothing about NPCs -- pair it with a DispositionReaction
## (target = this Gate, method "open") to open it when a guard is bribed/persuaded,
## or drive it from anything else. Reusable for any passage the world can open.

signal opened
signal closed

## Local offset the gate slides to when open (default: straight up, out of the way).
@export var open_offset: Vector3 = Vector3(0, 3.2, 0)
@export var slide_time: float = 0.9
## Author it already open (a reaction could close it later).
@export var start_open: bool = false

var is_open := false
var _closed_position: Vector3
var _collision: CollisionShape3D
var _tween: Tween


func _ready() -> void:
	_closed_position = position
	_collision = _find_collision()
	if start_open:
		position = _closed_position + open_offset
		is_open = true
		_set_collision_enabled(false)


func open() -> void:
	if is_open:
		return
	is_open = true
	_set_collision_enabled(false)
	_slide_to(_closed_position + open_offset)
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_set_collision_enabled(true)
	_slide_to(_closed_position)
	closed.emit()


func _slide_to(target_pos: Vector3) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "position", target_pos, slide_time)


func _set_collision_enabled(enabled: bool) -> void:
	if _collision:
		# Deferred: safe even if open()/close() is reached from a physics callback.
		_collision.set_deferred("disabled", not enabled)


func _find_collision() -> CollisionShape3D:
	for child in get_children():
		if child is CollisionShape3D:
			return child
	return null
