class_name DialogueChoice
extends Resource
## One selectable option at the end of a dialogue. Authored inline on an
## Interactable's `dialogue_choices` array (like JournalEntry sub-resources).
##
## Effects apply to the dialogue's TARGET (the NPC) when chosen: `gold_cost` is
## spent via PlayerState (the choice is shown disabled if you can't afford it, so a
## bribe is a real transaction), and `disposition_delta` shifts the NPC's live
## disposition -- which is what a DispositionReaction watches to change the world
## (e.g. open a gate). `response` is the NPC's reply, shown before the panel closes.
##
## Kept to a flat "intro lines -> choice list" model for now; a branching
## DialogueNode graph is the natural next step (point `response` at a follow-up).

## What choosing this does to `quest`, on top of the gold/disposition effects.
enum QuestAction {
	NONE,     ## no quest effect
	ACCEPT,   ## take the quest on
	TURN_IN,  ## hand it in and collect the rewards
}

@export var text: String = "..."
## Gold spent when chosen (0 = free). Unaffordable choices are shown disabled.
@export var gold_cost: int = 0
## Added to the target NPC's disposition when chosen (can be negative).
@export var disposition_delta: int = 0
## The NPC's reply, shown after choosing. Blank = close immediately.
@export_multiline var response: String = ""

@export_group("Quest")
## The quest this choice acts on. QuestGiver builds these choices automatically
## from a Quest's dialogue fields, but they're hand-authorable too -- so a bespoke
## NPC can offer or take in a quest without a QuestGiver component.
@export var quest: Quest
## Blank quest or NONE = a plain dialogue choice, exactly as before.
@export var quest_action: QuestAction = QuestAction.NONE
