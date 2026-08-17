extends LevelObjective
class_name PressurePlateObjective
## Completes when a PressurePlate is pressed -- "stand on the seal", "weigh down
## the dock scale", "get a barrel onto the loading plate".
##
## Point `plate` at one, or drop this node as a CHILD of the plate and it uses its
## parent. Like every LevelObjective it doubles as a sidequest step: set `quest`
## and it registers with QuestSystem instead of the level tracker.
##
## Completion LATCHES (complete() is one-way), so stepping off afterwards doesn't
## un-tick the row -- the same call CollectObjective makes, and for the same
## reason: a step that silently undoes itself reads as a bug.

## The plate to watch. Unset = this node's parent (drop it under the plate).
@export var plate: PressurePlate


func _setup() -> void:
	var watched: PressurePlate = plate if plate else get_parent() as PressurePlate
	if watched == null:
		push_warning("PressurePlateObjective '%s': set `plate`, or parent this node to a PressurePlate." % description)
		return
	# Already down when we register -- a barrel authored resting on it, or a quest
	# accepted after the fact. Count it rather than waiting for an edge that has
	# already passed.
	if watched.is_pressed:
		complete()
		return
	if not watched.pressed.is_connected(_on_pressed):
		watched.pressed.connect(_on_pressed)


func _on_pressed(_plate: PressurePlate) -> void:
	complete()
