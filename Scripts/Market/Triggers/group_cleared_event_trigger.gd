class_name GroupClearedEventTrigger
extends MarketEventTrigger
## Moves the market when every member of a group present at level start is gone --
## a whole caravan wiped, every crate in a granary smashed, all three warehouses
## burned.
##
## Snapshotted once (like DestroyGroupObjective, and unlike KillCountObjective), so
## bodies that spawn LATER don't count and can't un-complete it. An empty group at
## start warns and fires immediately rather than sitting there doing nothing.

## Everything in this group must be gone. Members are collected once, deferred.
@export var group: StringName = &"caravan"

var _remaining: int = 0


func _setup() -> void:
	var members := get_tree().get_nodes_in_group(group)
	_remaining = members.size()
	if _remaining == 0:
		push_warning("GroupClearedEventTrigger '%s': group '%s' is empty at level start."
			% [name, group])
		fire()
		return
	for member in members:
		member.tree_exited.connect(_on_member_gone)


func _on_member_gone() -> void:
	_remaining -= 1
	if _remaining <= 0:
		fire()
