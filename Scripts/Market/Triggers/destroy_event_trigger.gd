class_name DestroyEventTrigger
extends MarketEventTrigger
## Moves the market when a body is destroyed. The workhorse: burn the warehouse,
## wreck the foundry, sink the barge.
##
## Point `target` at the body, or just parent this node to it. Note the target's
## DamageReceiver almost certainly uses FREE_PARENT, which frees this node too --
## that's fine, because fire() runs synchronously inside the `died` signal, but it
## does mean a repeatable (one_shot = false) trigger must be pointed at the target
## from elsewhere rather than parented to it.

## The destructible body. Blank uses this node's parent.
@export var target: Node


func _setup() -> void:
	var body := _resolve_target(target)
	var receiver := DamageReceiver.find_in(body)
	if receiver == null:
		push_warning("DestroyEventTrigger '%s': '%s' has no DamageReceiver." % [
			name, body.name if body else "<none>"])
		return
	receiver.died.connect(_on_died)


func _on_died(_source: Node) -> void:
	fire()
