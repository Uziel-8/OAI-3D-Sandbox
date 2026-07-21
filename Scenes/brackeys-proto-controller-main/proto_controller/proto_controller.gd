# Originally ProtoController v1.0 by Brackeys (CC0). Heavily adapted: the
# per-frame locomotion has been pulled out into a StateMachine (Scripts/Player/
# States) so states own movement + animation. This script is now the "context":
# it keeps what's true in EVERY state -- mouse look + capture, exported config,
# node refs, the sprint-stamina hook -- and exposes movement primitives the
# states call. Look/config live here so the states stay small; the actual
# per-state decisions (speed, jump, air control, which animation) live in states.

extends CharacterBody3D
class_name PlayerController

## Can we move around?
@export var can_move : bool = true
## Are we affected by gravity?
@export var has_gravity : bool = true
## Can we press to jump?
@export var can_jump : bool = true
## Can we hold to run?
@export var can_sprint : bool = true
## Can we press to enter freefly mode (noclip)?
@export var can_freefly : bool = true

@export_group("Speeds")
## Look around rotation speed.
@export var look_speed : float = 0.002
## Normal speed.
@export var base_speed : float = 7.0
## Speed of jump.
@export var jump_velocity : float = 4.5
## How fast do we run?
@export var sprint_speed : float = 10.0
## Stamina drained per second while sprint-moving (spent via the PlayerState
## autoload; sprinting stops when the pool can't cover the frame's cost).
@export var sprint_stamina_drain : float = 20.0
## How fast do we freefly?
@export var freefly_speed : float = 25.0

@export_group("Input Actions")
@export var input_left : String = "move_left"
@export var input_right : String = "move_right"
@export var input_forward : String = "move_forward"
@export var input_back : String = "move_back"
@export var input_jump : String = "jump"
@export var input_sprint : String = "sprint"
@export var input_freefly : String = "fly"

var mouse_captured : bool = false
var look_rotation : Vector2

@onready var head: Node3D = $Head
@onready var collider: CollisionShape3D = $Collider
@onready var state_machine: StateMachine = $StateMachine
@onready var animator: PlayerAnimator = $PlayerAnimator


func _ready() -> void:
	check_input_mappings()
	look_rotation.y = rotation.y
	look_rotation.x = head.rotation.x
	# Hurt flinch is an animation overlay (doesn't change gameplay state), so wire
	# it straight to the animator. (Death is still handled by the DamageReceiver's
	# RELOAD_SCENE for now -- see note in the header of the FSM states.)
	var receiver := DamageReceiver.find_in(self)
	if receiver:
		receiver.damaged.connect(_on_damaged)


func _unhandled_input(event: InputEvent) -> void:
	# Mouse capturing (unchanged from the original; happens in every state).
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		capture_mouse()
	if Input.is_key_pressed(KEY_ESCAPE):
		release_mouse()
	if mouse_captured and event is InputEventMouseMotion:
		rotate_look(event.relative)


func _on_damaged(_amount: float, _remaining: float, _source: Node) -> void:
	if animator:
		animator.play_hurt()


# --- Movement primitives used by the states ---------------------------------

## Applies gravity to velocity when airborne (no-op on the floor / gravity off).
func apply_gravity(delta: float) -> void:
	if has_gravity and not is_on_floor():
		velocity += get_gravity() * delta


## Raw WASD vector.
func move_input() -> Vector2:
	if not can_move:
		return Vector2.ZERO
	return Input.get_vector(input_left, input_right, input_forward, input_back)


## World-space desired move direction from input, oriented by the body's facing.
func wish_direction() -> Vector3:
	var input := move_input()
	return (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()


## Drives horizontal velocity toward `speed` in the wish direction, or decelerates
## to a stop when there's no input. Vertical velocity is left untouched.
func apply_horizontal_velocity(speed: float) -> void:
	var dir := wish_direction()
	if dir != Vector3.ZERO:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)


## The move speed for this frame: sprint (charging stamina) when held + moving +
## affordable, else walk. Call once per frame from the moving state.
func resolve_move_speed(delta: float) -> float:
	if can_sprint and Input.is_action_pressed(input_sprint) and _try_pay_sprint(delta):
		return sprint_speed
	return base_speed


## Current horizontal speed magnitude (for driving the locomotion blend).
func planar_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Freefly (noclip) motion, driven by the FreeflyState.
func freefly_move(delta: float) -> void:
	var input := Input.get_vector(input_left, input_right, input_forward, input_back)
	var motion := (head.global_basis * Vector3(input.x, 0, input.y)).normalized()
	motion *= freefly_speed * delta
	move_and_collide(motion)


# --- Look / mouse / freefly toggle helpers ----------------------------------

func rotate_look(rot_input : Vector2) -> void:
	look_rotation.x -= rot_input.y * look_speed
	look_rotation.x = clamp(look_rotation.x, deg_to_rad(-85), deg_to_rad(85))
	look_rotation.y -= rot_input.x * look_speed
	transform.basis = Basis()
	rotate_y(look_rotation.y)
	head.transform.basis = Basis()
	head.rotate_x(look_rotation.x)


func enable_freefly() -> void:
	collider.disabled = true
	velocity = Vector3.ZERO


func disable_freefly() -> void:
	collider.disabled = false


func capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true


func release_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false


## Drains sprint stamina for this frame via the PlayerState autoload. Free when
## standing still, when there's no PlayerState (test scenes), or if the pool
## covers the cost; returns false (blocking sprint speed) once stamina is dry.
func _try_pay_sprint(delta: float) -> bool:
	if move_input() == Vector2.ZERO:
		return false
	var state := get_node_or_null("/root/PlayerState")
	if state == null:
		return true
	return state.spend_stamina(sprint_stamina_drain * delta)


## Disables features whose Input Actions are missing, so a stripped project still runs.
func check_input_mappings() -> void:
	if can_move and not (InputMap.has_action(input_left) and InputMap.has_action(input_right) \
			and InputMap.has_action(input_forward) and InputMap.has_action(input_back)):
		push_error("Movement disabled. Missing a movement InputAction.")
		can_move = false
	if can_jump and not InputMap.has_action(input_jump):
		push_error("Jumping disabled. No InputAction found for input_jump: " + input_jump)
		can_jump = false
	if can_sprint and not InputMap.has_action(input_sprint):
		push_error("Sprinting disabled. No InputAction found for input_sprint: " + input_sprint)
		can_sprint = false
	if can_freefly and not InputMap.has_action(input_freefly):
		push_error("Freefly disabled. No InputAction found for input_freefly: " + input_freefly)
		can_freefly = false
