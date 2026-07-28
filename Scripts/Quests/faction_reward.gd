class_name FactionReward
extends Resource
## A shift in standing with a whole FACTION, granted when a quest is turned in.
## Authored inline on a Quest's `faction_rewards` array (like DialogueChoice /
## JournalEntry sub-resources).
##
## Applied through the Reputation autoload, which both nudges every NPC currently
## in group "faction_<faction>" AND remembers the shift, so NPCs that spawn later
## (a reloaded scene, the next level) start at the adjusted disposition.

## Faction key, matching NpcProfile.faction (e.g. &"docks", &"hostile").
@export var faction: StringName = &"neutral"
## Added to that faction's standing (can be negative -- quests can make enemies).
@export var delta: int = 0
