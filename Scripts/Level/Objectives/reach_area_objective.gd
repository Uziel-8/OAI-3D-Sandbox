extends LevelObjective
class_name ReachAreaObjective
## Completes when the player enters an Area3D -- e.g. "Reach the inner hall".
##
## Drop this node as a CHILD of the Area3D that marks the destination (it uses its
## parent automatically), or point `area` at one. The Area3D needs a CollisionShape3D
## and monitoring on, which is the default for a fresh Area3D.

## The trigger volume. Unset = use this node's parent (must be an Area3D).
@export var area: Area3D
## Group the entering body must be in for the objective to count.
@export var player_group: StringName = &"player"


func _setup() -> void:
	var volume: Area3D = area if area else get_parent() as Area3D
	if volume == null:
		push_warning("ReachAreaObjective '%s': set `area`, or parent this node to an Area3D." % description)
		return
	if not volume.body_entered.is_connected(_on_body_entered):
		volume.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group(player_group):
		complete()
