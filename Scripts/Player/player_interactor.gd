extends Node
class_name PlayerInteractor
## Raycasts from the camera crosshair each physics frame for the nearest
## Interactable within reach of the player, shows its prompt on the HUD, and
## triggers it on the `interact` action. Add as a child of the player's Camera3D
## (sibling of SpellCaster) so the Brackeys controller stays untouched.

## Reach measured from the PLAYER body (not the third-person camera), so it feels
## like "close enough to the thing" regardless of camera distance.
@export var interact_range: float = 3.0
## How far the aim ray is cast; must exceed camera-to-player + interact_range.
@export var ray_length: float = 40.0
@export var interact_action: String = "interact"

@onready var _camera: Camera3D = get_parent()
var _player: Node3D
var _current: Interactable


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")


func _physics_process(_delta: float) -> void:
	# Only while actually playing (not in a menu / dialogue, which release the mouse).
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		if _current != null:
			_set_current(null)
		return

	_set_current(_find_interactable())
	if _current and Input.is_action_just_pressed(interact_action):
		_current.interact(_player)


func _find_interactable() -> Interactable:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return null

	var from := _camera.global_position
	var to := from - _camera.global_transform.basis.z * ray_length
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [_player.get_rid()])
	var hit := _camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null

	var interactable := Interactable.find_in(hit.collider)
	if interactable == null or not interactable.enabled:
		return null
	# Gate on distance from the player, not the camera.
	if _player.global_position.distance_to(hit.position) > interact_range:
		return null
	return interactable


func _set_current(interactable: Interactable) -> void:
	if interactable == _current:
		return
	_current = interactable
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_interact_prompt"):
		hud.set_interact_prompt(_current.prompt_text(interact_action) if _current else "")
