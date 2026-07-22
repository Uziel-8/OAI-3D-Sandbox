extends LevelObjective
class_name InteractObjective
## Completes when an Interactable is interacted with -- the non-violent path
## ("talk the foreman down" rather than killing him).
##
## Point `target` at the body carrying the Interactable, or drop this node as a
## CHILD of that body to use its parent automatically.
##
## Today this fires on ANY interaction with that body. Once dialogue grows branching
## choices + NPC disposition, the natural upgrade is to complete on a specific
## outcome instead -- swap the signal hooked below; nothing else changes.

## The body whose Interactable is watched. Unset = use this node's parent.
@export var target: Node


func _setup() -> void:
	var body: Node = target if target else get_parent()
	if body == null:
		push_warning("InteractObjective '%s': no target set and no parent to fall back on." % description)
		return
	var interactable := Interactable.find_in(body)
	if interactable == null:
		push_warning("InteractObjective '%s': %s has no Interactable child." % [description, body.name])
		return
	if not interactable.interacted.is_connected(_on_interacted):
		interactable.interacted.connect(_on_interacted)


func _on_interacted(_interactor: Node) -> void:
	complete()
