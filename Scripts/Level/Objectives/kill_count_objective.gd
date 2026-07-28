extends LevelObjective
class_name KillCountObjective
## Completes once `count` members of `group` have been KILLED -- e.g. "kill 3
## spiders". Shows live progress as (2/3).
##
## The sibling of DestroyGroupObjective, and deliberately not the same thing:
## DestroyGroup snapshots its members at level start and watches tree_exited, which
## is right for "destroy these 3 nests" but wrong here, because bodies that spawn
## LATER must count and a queue_free for any other reason must not. So this one
## watches each member's DamageReceiver.died and tallies deaths, picking up new
## members via the tree's node_added.
##
## Works as a level objective or a quest step (set `quest` -- see LevelObjective).

## The group whose deaths are counted. Enemies join "enemy" in their _ready.
@export var group: StringName = &"enemy"
## How many must die.
@export var count: int = 1

var _killed: int = 0


func _setup() -> void:
	if count <= 0:
		push_warning("KillCountObjective '%s': count is %d; completing immediately." % [description, count])
		complete()
		return
	# Restored from QuestSystem's store on a scene reload, 0 on a fresh start.
	_killed = current_count()
	get_tree().node_added.connect(_on_node_added)
	# Scanned IMMEDIATELY, not deferred: _setup() already runs late (either from
	# the deferred _register, or from quest_accepted mid-game), so everything in
	# the level is in its groups by now. Deferring it left a frame in which a kill
	# went uncounted.
	for member in get_tree().get_nodes_in_group(group):
		_watch(member)
	set_progress(_killed, count)


func _on_node_added(node: Node) -> void:
	# Same reason as above: the node isn't in its groups yet when this fires.
	_watch.call_deferred(node)


func _watch(body: Node) -> void:
	if is_complete or body == null or not is_instance_valid(body):
		return
	if not body.is_in_group(group):
		return
	var receiver := DamageReceiver.find_in(body)
	if receiver == null:
		return  # not damageable -- nothing to count
	if not receiver.died.is_connected(_on_member_died):
		receiver.died.connect(_on_member_died)


func _on_member_died(_source: Node) -> void:
	_killed += 1
	set_progress(_killed, count)
