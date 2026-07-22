extends LevelObjective
class_name DestroyGroupObjective
## Completes when every member of `group` that existed at level start has been
## destroyed -- e.g. all the "enemy_spawner" nests. Shows live progress as (2/3).
##
## The member set is snapshotted once at level start, so enemies a spawner spits out
## afterwards don't count against it (spawners themselves are the targets, and the
## EnemySpawner scene already joins the "enemy_spawner" group). Members are watched
## via tree_exited, which covers a DamageReceiver's FREE_PARENT death and any other
## removal.

## The group whose members must all be destroyed.
@export var group: StringName = &"enemy_spawner"

var _total_members: int = 0
var _destroyed: int = 0


func _setup() -> void:
	var members := get_tree().get_nodes_in_group(group)
	_total_members = members.size()
	if _total_members == 0:
		# Vacuously true, but almost always means the designer hasn't placed them
		# yet -- warn loudly rather than silently gifting the objective.
		push_warning("DestroyGroupObjective '%s': nothing in group '%s' at level start; completing immediately." % [description, group])
		complete()
		return
	for member in members:
		member.tree_exited.connect(_on_member_destroyed)
	set_progress(0, _total_members)


func _on_member_destroyed() -> void:
	_destroyed += 1
	set_progress(_destroyed, _total_members)
