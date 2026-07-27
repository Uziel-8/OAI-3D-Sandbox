extends Node
class_name DispositionReaction
## Drop-in bridge between "an NPC's disposition changed" and "something in the
## world reacts" -- e.g. bribe a guard past a threshold and a Gate opens. Mirrors
## the objective-component convention: reference a subject, watch a signal, fire.
##
## Place it under the NPC (leave `npc` empty to use the parent) or anywhere and
## point `npc` at one. When the NPC's disposition first satisfies the threshold it
## calls `method` on `target` (duck-typed, so any node exposing that method works)
## and emits `triggered`. `one_shot` latches it so a gate stays open.

signal triggered(reaction: DispositionReaction)

enum Compare { AT_LEAST, AT_MOST }

## NPC to watch. Unset = this node's parent (drop it under the NPC).
@export var npc: Npc
@export var threshold: int = 0
@export var compare: Compare = Compare.AT_LEAST
## Node acted on when the condition is met; `method` is called if it exists.
@export var target: Node
@export var method: StringName = &"open"
## Latch after firing once (right for a gate). False = fire each time it re-crosses.
@export var one_shot: bool = true

var _fired := false


func _ready() -> void:
	if npc == null:
		npc = get_parent() as Npc
	if npc == null:
		push_warning("DispositionReaction '%s': no `npc` set and parent isn't an Npc." % name)
		return
	npc.disposition_changed.connect(_on_disposition_changed)
	# Deferred, and re-reads disposition live: this reaction is usually a CHILD of
	# the NPC, so its _ready runs BEFORE the NPC's _ready seeds disposition from the
	# profile. Snapshotting npc.disposition here would catch the default (0); by the
	# time the deferred call runs, the profile has been applied.
	_check_initial.call_deferred()


func _check_initial() -> void:
	if is_instance_valid(npc):
		_evaluate(npc.disposition)


func _on_disposition_changed(new_value: int, _old_value: int) -> void:
	_evaluate(new_value)


func _evaluate(value: int) -> void:
	if _fired and one_shot:
		return
	var met := false
	if compare == Compare.AT_LEAST:
		met = value >= threshold
	else:
		met = value <= threshold
	if not met:
		return
	_fired = true
	if target and target.has_method(method):
		target.call(method)
	triggered.emit(self)
