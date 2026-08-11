extends RigidBody3D
class_name ItemPickup
## An item lying in the world that goes into the player's pack when interacted
## with. The sibling of gold_stack.tscn (which pays currency); this one is the
## generic "pick this up" object, and the first thing to put a real InventoryItem
## into the world rather than seeding it into the bag at startup.
##
## Drop `Objects/item_pickup.tscn` into a level and set ONE of:
##   * `item`    -- an InventoryItem authored inline on the instance (full control), or
##   * `item_id` -- an id looked up in MockItemDatabase (quick, and what a real
##                  item database's load-by-id would replace).
## `item` wins if both are set.
##
## It's a RigidBody3D like the gold stack, so it can be knocked around, and the
## placeholder mesh tints itself to the item's icon_color -- the same
## build-it-from-the-data approach as SpiderWalker's legs and HudSpellSlot, so a
## new pickup needs no art. Add a model as a child and clear `tint_mesh` once
## there is some.

## Emitted after the item lands in the player's pack, just before this frees
## itself. Lets a level hook something onto a specific pickup.
signal picked_up(item: InventoryItem, count: int)

## Authored inline on the instance. Takes priority over item_id.
@export var item: InventoryItem
## Looked up in MockItemDatabase when `item` is unset.
@export var item_id: String = ""
## How many units this pickup grants. 0 = the item's own stack_count.
@export var count: int = 0
## Tints the placeholder mesh to the item's icon_color.
@export var tint_mesh: bool = true
## Shows a HUD toast naming what was picked up.
@export var announce: bool = true

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _interactable: Interactable = $Interactable

## Resolved once in _ready -- an owned copy, so two pickups sharing one
## MockItemDatabase entry can't scribble on each other's stack count.
var _item: InventoryItem = null
var _count: int = 0


func _ready() -> void:
	_item = item.duplicate() if item else MockItemDatabase.find_by_id(item_id)
	if _item == null:
		push_warning("ItemPickup '%s': no item set and item_id '%s' isn't in MockItemDatabase." % [name, item_id])
		_interactable.enabled = false
		return

	_count = count if count > 0 else _item.stack_count
	_item.stack_count = _count
	_interactable.prompt = "Pick Up %s" % _item.item_name
	if _count > 1:
		_interactable.prompt += "  x%d" % _count
	if tint_mesh and _mesh:
		var material := StandardMaterial3D.new()
		material.albedo_color = _item.icon_color
		_mesh.material_override = material


## Wired from the Interactable's `interacted` signal in item_pickup.tscn.
func _on_interacted(_interactor: Node) -> void:
	var inventory := get_node_or_null("/root/PlayerInventory") as PlayerInventorySystem
	if inventory == null or _item == null:
		return
	# add_item is all-or-nothing, so a refusal leaves the pickup sitting there
	# intact to come back for -- never a partial grab that loses the remainder.
	if not inventory.add_item(_item, _count):
		_toast("Pack Full", "No room for %s." % _item.item_name)
		return
	if announce:
		_toast(_item.item_name, "x%d added to your pack" % _count if _count > 1 else "Added to your pack")
	picked_up.emit(_item, _count)
	queue_free()


func _toast(title: String, subtitle: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_toast"):
		hud.show_toast(title, subtitle)
