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

@export var text: String = "..."
## Gold spent when chosen (0 = free). Unaffordable choices are shown disabled.
@export var gold_cost: int = 0
## Added to the target NPC's disposition when chosen (can be negative).
@export var disposition_delta: int = 0
## The NPC's reply, shown after choosing. Blank = close immediately.
@export_multiline var response: String = ""
