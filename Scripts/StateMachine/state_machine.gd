extends Node
class_name StateMachine
## Generic finite state machine: holds FsmState children, forwards
## update/physics/input to the active one, and switches when a state requests it.
## It knows nothing about what the states do, so it's reusable for the player,
## enemies, and NPCs alike. Transition targets are child node names.

signal state_changed(state_name: StringName)

## FsmState to start in. If unset, the first FsmState child is used.
@export var initial_state: FsmState

var current: FsmState


func _ready() -> void:
	for child in get_children():
		if child is FsmState:
			child.transition_requested.connect(_on_transition_requested)
	# Deferred so the first enter() runs after every node (animator, groups, the
	# player body) has finished _ready -- states resolve those refs in enter().
	_enter_initial.call_deferred()


func _enter_initial() -> void:
	current = initial_state if initial_state else _first_state()
	if current:
		current.enter()
		state_changed.emit(current.name)


func _process(delta: float) -> void:
	if current:
		current.update(delta)


func _physics_process(delta: float) -> void:
	if current:
		current.physics_update(delta)


func _unhandled_input(event: InputEvent) -> void:
	if current:
		current.handle_input(event)


## Switches to the state whose node name matches `target`. No-op if it doesn't
## exist or is already active.
func transition_to(target: StringName, msg: Dictionary = {}) -> void:
	var next := get_node_or_null(NodePath(String(target))) as FsmState
	if next == null or next == current:
		return
	if current:
		current.exit()
	current = next
	current.enter(msg)
	state_changed.emit(current.name)


func _on_transition_requested(target: StringName, msg: Dictionary) -> void:
	transition_to(target, msg)


func _first_state() -> FsmState:
	for child in get_children():
		if child is FsmState:
			return child
	return null
