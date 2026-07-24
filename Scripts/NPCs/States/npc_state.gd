extends FsmState
class_name NpcState
## Base for the NPC movement states. Resolves its owning Npc via the tree structure
## (state -> StateMachine -> Npc), so it works for every NPC instance without any
## group lookup (there are many NPCs, unlike the single player). Concrete states
## override enter()/physics_update().

var npc: Npc


func _ready() -> void:
	# state's parent is the StateMachine; the StateMachine's parent is the Npc.
	npc = get_parent().get_parent() as Npc
