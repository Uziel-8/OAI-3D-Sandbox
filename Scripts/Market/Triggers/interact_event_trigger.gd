class_name InteractEventTrigger
extends MarketEventTrigger
## Moves the market when an Interactable is used -- opening a sluice to flood a
## market square, forging a manifest, cutting a mooring line. The non-violent half
## of manipulation, and the one a persuasion run wants.
##
## Point `interactable` at the component, or parent this node to the body carrying
## it. Pair with `delay_days` for the quiet options: a forged manifest shouldn't
## move the board until somebody reads it.

## The component to watch. Blank scans this node's parent for one.
@export var interactable: Interactable


func _setup() -> void:
	var component := interactable
	if component == null or not is_instance_valid(component):
		component = Interactable.find_in(_resolve_target(null))
	if component == null:
		push_warning("InteractEventTrigger '%s': no Interactable to watch." % name)
		return
	component.interacted.connect(_on_interacted)


func _on_interacted(_interactor: Node) -> void:
	fire()
