extends Node
class_name Interactable
## Drop-in interaction component. Add as a child of any body the player should be
## able to interact with, and put that body in group "interactable" so the
## PlayerInteractor's raycast can find it (it scans the hit body's children via
## find_in, mirroring DamageReceiver). Emits `interacted(interactor)` and, when
## dialogue_lines are set, opens the DialogueUI -- so it handles "talk to an NPC"
## out of the box while the signal lets quests/doors/pickups hook in their own
## behaviour without subclassing.

signal interacted(interactor: Node)

## Verb shown in the HUD prompt, e.g. "Speak", "Open", "Search".
@export var prompt: String = "Interact"
## When false the component is ignored: no prompt, can't be triggered.
@export var enabled: bool = true

@export_group("Dialogue")
## Name shown in the dialogue panel header. Blank = no speaker line.
@export var speaker_name: String = ""
## Lines shown one after another when interacted. Empty = no dialogue (the
## `interacted` signal still fires for other systems to respond to).
@export var dialogue_lines: Array[String] = []
## Options offered after the lines. Each can cost gold and shift the target NPC's
## disposition (see DialogueChoice). Empty = no choices, dialogue just closes.
@export var dialogue_choices: Array[DialogueChoice] = []

# Temporary replacement for the authored lines/choices, pushed by a sibling
# component that wants this NPC to say something state-dependent (QuestGiver does
# this for its offer / in-progress / ready / completed line sets). Push-based
# rather than pulled at interact time: everything that can change what should be
# said already emits a signal, so the pusher can just keep it current.
var _override_active: bool = false
var _override_lines: Array[String] = []
var _override_choices: Array[DialogueChoice] = []


## Triggered by PlayerInteractor on the interact action.
func interact(interactor: Node) -> void:
	if not enabled:
		return
	interacted.emit(interactor)
	var lines := _override_lines if _override_active else dialogue_lines
	var choices := _override_choices if _override_active else dialogue_choices
	if lines.is_empty() and choices.is_empty():
		return
	# The DialogueScreen script sits on the autoload's Screen child, not the
	# CanvasLayer root, so find it by group (as the journal/inventory do). The
	# target -- this component's owning body (the NPC) -- receives choice effects
	# like disposition changes.
	var dialogue := get_tree().get_first_node_in_group("dialogue_screen")
	if dialogue and dialogue.has_method("start"):
		dialogue.start(speaker_name, lines, choices, get_parent())


## Replaces what this Interactable says until cleared. The authored lines/choices
## are left untouched underneath, so clear_dialogue_override() restores them.
func set_dialogue_override(lines: Array[String], choices: Array[DialogueChoice]) -> void:
	_override_active = true
	_override_lines = lines
	_override_choices = choices


## Falls back to the lines/choices authored on this component (or seeded from an
## NpcProfile).
func clear_dialogue_override() -> void:
	_override_active = false
	_override_lines = []
	_override_choices = []


## HUD prompt text including the key currently bound to the interact action.
func prompt_text(action: String = "interact") -> String:
	return "[%s]  %s" % [_key_label(action), prompt]


func _key_label(action: String) -> String:
	if InputMap.has_action(action):
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				var kc: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
				return OS.get_keycode_string(kc)
	return "?"


## Returns the Interactable child of the given body, or null. Mirrors
## DamageReceiver.find_in -- a direct-children scan, so the component sits at the
## body root.
static func find_in(body: Node) -> Interactable:
	if body == null:
		return null
	for child in body.get_children():
		if child is Interactable:
			return child
	return null
