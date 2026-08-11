extends LevelObjective
class_name CollectObjective
## Completes once the player is CARRYING `count` units of `item_id` -- the fetch
## half of a fetch/deliver quest ("bring me 3 wolf pelts"). Shows live progress
## as (2/3).
##
## Counts what's in the pack RIGHT NOW rather than tallying pickups, which is what
## makes it behave sensibly in every direction: items already in the bag when the
## quest is accepted count immediately, items bought from a merchant count, and
## selling one drops the row back to (1/3). What it can't do is un-complete --
## LevelObjective.complete() latches -- so once you've held the full amount the
## step stays done even if you then sell the lot. That's deliberate: a quest step
## that silently un-ticks after the giver already acknowledged it is worse than a
## small exploit.
##
## The count is read from PlayerInventory, so it survives the death-reload for
## free (the autoload does), independently of QuestSystem's progress store.
##
## Works as a level objective or a quest step (set `quest` -- see LevelObjective).
##
## NOT handled here: taking the items off the player on turn-in. Handing over is a
## QUEST REWARD concern (it should happen when the giver is spoken to, not the
## moment the third pelt lands in the bag), and there's no item-cost field on
## Quest yet.

## InventoryItem.id to count, e.g. "wolf_pelt". Must match the id on the item the
## world/shop actually hands out -- nothing validates this, and a typo simply
## never ticks.
@export var item_id: String = ""
## How many must be carried.
@export var count: int = 1

## Cached so the signal can be disconnected once the objective is done; a fetch
## objective is otherwise the one type that keeps listening for the whole level.
var _inventory: PlayerInventorySystem = null


func _setup() -> void:
	if item_id.is_empty():
		push_warning("CollectObjective '%s': item_id is blank; it can never complete." % description)
		return
	if count <= 0:
		push_warning("CollectObjective '%s': count is %d; completing immediately." % [description, count])
		complete()
		return

	_inventory = get_node_or_null("/root/PlayerInventory") as PlayerInventorySystem
	if _inventory == null:
		push_warning("CollectObjective '%s': PlayerInventory is missing." % description)
		return
	_inventory.inventory_changed.connect(_on_inventory_changed)
	# Checked immediately: the player may already be holding the items when the
	# quest is accepted, and _setup() runs late enough that the autoload is seeded.
	_refresh()


func _on_inventory_changed() -> void:
	_refresh()


func _refresh() -> void:
	if is_complete:
		_stop_watching()
		return
	set_progress(mini(_inventory.count_of(item_id), count), count)
	if is_complete:
		_stop_watching()


func _stop_watching() -> void:
	if _inventory and _inventory.inventory_changed.is_connected(_on_inventory_changed):
		_inventory.inventory_changed.disconnect(_on_inventory_changed)
