extends LevelObjective
class_name KillTargetObjective
## Completes when a specific body's DamageReceiver dies -- e.g. "Remove the Foreman".
##
## Point `target` at the body (recommended), or drop this node as a CHILD of that
## body and it will use its parent automatically. NOTE: if the target's
## death_behavior is FREE_PARENT, parenting this objective to it means the objective
## node is freed the instant it completes -- that's handled (the tracker caches the
## checklist line), but pointing `target` at the body from a safe parent is tidier.

## The body whose DamageReceiver is watched. Unset = use this node's parent.
@export var target: Node


func _setup() -> void:
	var body: Node = target if target else get_parent()
	if body == null:
		push_warning("KillTargetObjective '%s': no target set and no parent to fall back on." % description)
		return
	var receiver := DamageReceiver.find_in(body)
	if receiver == null:
		push_warning("KillTargetObjective '%s': %s has no DamageReceiver child." % [description, body.name])
		return
	if not receiver.died.is_connected(_on_target_died):
		receiver.died.connect(_on_target_died)


func _on_target_died(_source: Node) -> void:
	complete()
