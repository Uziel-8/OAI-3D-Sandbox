extends CharacterBody3D
class_name Npc
## The "context" for a data-driven NPC, exactly like PlayerController is for the
## player: it holds the config (seeded from an NpcProfile), the node refs, and the
## movement PRIMITIVES the FSM states call -- it does not decide behaviour itself.
## Behaviour lives in the StateMachine child (Scripts/NPCs/States/), data lives in
## the `profile` resource, and per-NPC tweaks are exports/overrides on the instance.
##
## Composition (all drop-in components already used elsewhere): a DamageReceiver
## (killable), an Interactable (talkable), a HealthBar3D, and a StateMachine with
## Static/Patrol/Chase states. Add a new movement behaviour = a new state; add a
## new archetype = a new profile + inherited scene. See NPCs/npc.tscn.
##
## Spells can push NPCs: apply_impulse() folds knockback into velocity (duck-typed
## like SpiderWalker/RigidBody3D), and staggers the AI briefly so the shove shows.

const ARRIVE_DISTANCE := 0.6

@export var profile: NpcProfile
## World-space waypoints (Marker3D/Node3D placed in the LEVEL, not the NPC scene --
## a shared profile can't hold per-instance positions). Used by PATROL movement.
@export var patrol_points: Array[Node3D] = []

@export_group("Knockback")
@export var stagger_duration: float = 0.35
@export var knockback_friction: float = 6.0

# --- Live state (seeded from the profile; the profile itself is never mutated) ---
var faction: StringName = &"neutral"
var disposition: int = 0
var default_movement: NpcProfile.Movement = NpcProfile.Movement.STATIC
var move_speed: float = 3.0
var turn_speed: float = 8.0
var chase_range: float = 8.0
var give_up_range: float = 14.0
var stop_distance: float = 1.6
var patrol_wait: float = 1.5

@onready var state_machine: StateMachine = $StateMachine

var _receiver: DamageReceiver
var _interactable: Interactable
var _player: Node3D
var _stagger_timer: float = 0.0


func _ready() -> void:
	add_to_group("npc")
	_receiver = DamageReceiver.find_in(self)
	_interactable = Interactable.find_in(self)
	if profile:
		_apply_profile()
	add_to_group("faction_%s" % String(faction))
	# Set the SM's starting state BEFORE its deferred first enter() runs (the SM
	# defers it), so the NPC begins in the movement its profile asks for.
	if state_machine:
		state_machine.initial_state = _state_node_for(default_movement)


## Copies the profile's data into live state + the components. Runs after the
## components' own _ready (they're children), so we push health through directly.
func _apply_profile() -> void:
	faction = profile.faction
	disposition = profile.starting_disposition
	default_movement = profile.movement
	move_speed = profile.move_speed
	turn_speed = profile.turn_speed
	chase_range = profile.chase_range
	give_up_range = profile.give_up_range
	stop_distance = profile.stop_distance
	patrol_wait = profile.patrol_wait

	if _receiver:
		_receiver.max_health = profile.max_health
		_receiver.health = profile.max_health
		_receiver.health_regen = profile.health_regen
		_receiver.xp_reward = profile.xp_reward
		_receiver.health_changed.emit(profile.max_health, profile.max_health)

	if _interactable:
		if profile.interact_prompt != "":
			_interactable.prompt = profile.interact_prompt
		if profile.speaker_name != "":
			_interactable.speaker_name = profile.speaker_name
		# Profile lines are a default; a scene that authored its own lines wins.
		if not profile.dialogue_lines.is_empty() and _interactable.dialogue_lines.is_empty():
			_interactable.dialogue_lines = profile.dialogue_lines


# --- Queries the states use --------------------------------------------------

func is_hostile() -> bool:
	return disposition < 0

func get_player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player

func has_player() -> bool:
	return get_player() != null

func player_position() -> Vector3:
	var p := get_player()
	return p.global_position if p else global_position

func distance_to_player() -> float:
	var p := get_player()
	return global_position.distance_to(p.global_position) if p else INF

## A hostile STATIC/PATROL NPC breaks off to Chase once the player is within reach.
func should_start_chase() -> bool:
	return is_hostile() and has_player() and distance_to_player() <= chase_range

func default_movement_state_name() -> StringName:
	match default_movement:
		NpcProfile.Movement.PATROL:
			return &"Patrol"
		NpcProfile.Movement.CHASE:
			return &"Chase"
		_:
			return &"Static"


# --- Movement primitives the states call (they call move_and_slide themselves) --

func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0

## Drives horizontal velocity toward `point` at move_speed and turns to face it.
## Within `arrive`, decelerates instead. Returns the planar distance to `point`.
func steer_towards(point: Vector3, delta: float, arrive: float = 0.0) -> float:
	var to := point - global_position
	to.y = 0.0
	var dist := to.length()
	if dist <= arrive or dist < 0.001:
		halt(delta)
		return dist
	var dir := to / dist
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
	_face_dir(dir, delta)
	return dist

func face_towards(point: Vector3, delta: float) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length() > 0.001:
		_face_dir(to.normalized(), delta)

## Decelerates horizontal velocity to a stop (leaves vertical alone).
func halt(delta: float) -> void:
	var decel := move_speed * 4.0 * delta
	velocity.x = move_toward(velocity.x, 0.0, decel)
	velocity.z = move_toward(velocity.z, 0.0, decel)

## While staggered from a knockback, bleeds velocity and suspends AI steering so
## the shove is visible. Returns true while active -- states early-out on it.
func tick_stagger(delta: float) -> bool:
	if _stagger_timer <= 0.0:
		return false
	_stagger_timer -= delta
	apply_gravity(delta)
	var h := Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, knockback_friction * delta)
	velocity.x = h.x
	velocity.z = h.y
	move_and_slide()
	return true

## Duck-typed counterpart to RigidBody3D.apply_impulse so spells (TelekinesisPush,
## projectile impacts) can shove an NPC without knowing its type. Mass treated as 1.
func apply_impulse(impulse: Vector3, _position := Vector3.ZERO) -> void:
	velocity += impulse
	_stagger_timer = stagger_duration


# --- Internals ---------------------------------------------------------------

func _face_dir(dir: Vector3, delta: float) -> void:
	# Faces the model's +Z toward `dir` (KayKit rigs face +Z), matching SpiderWalker.
	# If a specific model faces backwards, flip it in that NPC's inherited scene.
	var target_yaw := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))

func _state_node_for(m: NpcProfile.Movement) -> FsmState:
	match m:
		NpcProfile.Movement.PATROL:
			return $StateMachine/Patrol
		NpcProfile.Movement.CHASE:
			return $StateMachine/Chase
		_:
			return $StateMachine/Static
