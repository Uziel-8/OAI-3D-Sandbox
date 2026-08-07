extends RigidBody3D
## Pile of coins that pays out and disappears when picked up. The Interactable
## child's `interacted` signal is connected to _on_node_interacted in gold_stack.tscn.


func _on_node_interacted(_interactor: Node) -> void:
	PlayerState.add_gold(50)
	queue_free()
