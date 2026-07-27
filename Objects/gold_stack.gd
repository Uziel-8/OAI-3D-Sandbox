extends RigidBody3D



var _interactable = Interactable

func _ready() -> void:
	_interactable = Interactable.find_in(self)



func _on_node_interacted(interactor: Node) -> void:
	PlayerState.add_gold(50)
	queue_free()
