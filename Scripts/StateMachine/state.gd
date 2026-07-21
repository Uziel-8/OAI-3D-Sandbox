extends Node
class_name FsmState
## Base class for one state in a StateMachine. (Named FsmState, not State, to
## avoid colliding with local `State` enums elsewhere in the project.) Authored as
## a child of a StateMachine node, so this node's `name` is the key others target.
## Subclasses override the lifecycle hooks; call transition_to("OtherState") to
## request a switch (the StateMachine performs it and hands `msg` to enter()).
## Generic on purpose -- the player, enemies, and NPCs can all reuse it.

## Asks the owning StateMachine to switch. `msg` passes data to the next state.
signal transition_requested(target: StringName, msg: Dictionary)


## Called when this state becomes active. `msg` carries any data from the caller.
func enter(_msg: Dictionary = {}) -> void:
	pass

## Called when leaving this state.
func exit() -> void:
	pass

## Per-frame (idle) update while active.
func update(_delta: float) -> void:
	pass

## Per-physics-frame update while active.
func physics_update(_delta: float) -> void:
	pass

## Unhandled input while active.
func handle_input(_event: InputEvent) -> void:
	pass


func transition_to(target: StringName, msg: Dictionary = {}) -> void:
	transition_requested.emit(target, msg)
