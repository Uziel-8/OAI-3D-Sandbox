class_name ReputationSystem
extends Node
## Persistent per-faction standing. Registered as the `Reputation` autoload, so it
## survives the player-death scene reload AND level changes -- reputation earned in
## the docks still applies in the keep.
##
## This is what finally gives the "faction_<x>" groups (created in Npc._ready) a
## consumer. adjust() does two things:
##   1. remembers the shift, keyed by faction;
##   2. nudges every NPC of that faction who is alive RIGHT NOW.
## NPCs that spawn LATER pick the modifier up in Npc._apply_profile, which seeds
## disposition as `profile.starting_disposition + Reputation.modifier(faction)`.
## Between them every NPC ends up correct, and nobody is adjusted twice.
##
## Quests are the first source (Quest.faction_rewards -> QuestSystem.turn_in), but
## adjust() is a general entry point -- crimes, faction kills, and dialogue can all
## call it later.

## Emitted after a faction's standing changes.
signal reputation_changed(faction: StringName, value: int, delta: int)

## Standing is clamped to the same range as an individual's disposition, so a
## faction modifier can't push an NPC past what change_disposition allows anyway.
const MIN_STANDING := Npc.DISPOSITION_MIN
const MAX_STANDING := Npc.DISPOSITION_MAX

## faction (StringName) -> accumulated modifier (int).
var _modifiers: Dictionary = {}


## Current standing with a faction (0 if never adjusted).
func modifier(faction: StringName) -> int:
	return _modifiers.get(faction, 0)


## Shifts standing with a faction and applies it to every live member. Returns the
## amount actually applied after clamping (0 = already at the cap, nothing done).
func adjust(faction: StringName, delta: int) -> int:
	if delta == 0 or String(faction).is_empty():
		return 0
	var old: int = modifier(faction)
	var value: int = clampi(old + delta, MIN_STANDING, MAX_STANDING)
	var applied: int = value - old
	if applied == 0:
		return 0
	_modifiers[faction] = value

	# Everyone currently in the world. Npc.change_disposition clamps and emits, so
	# DispositionReactions (gates, etc.) fire off this for free.
	for npc in get_tree().get_nodes_in_group("faction_%s" % String(faction)):
		if npc.has_method("change_disposition"):
			npc.change_disposition(applied)

	reputation_changed.emit(faction, value, applied)
	return applied


## Every faction with a non-zero standing, for UI/debug.
func all_standings() -> Dictionary:
	return _modifiers.duplicate()


## Wipes all standing. No UI yet -- here so a future new-game/respec has one call.
func reset() -> void:
	for faction in _modifiers.keys():
		var old: int = _modifiers[faction]
		if old != 0:
			for npc in get_tree().get_nodes_in_group("faction_%s" % String(faction)):
				if npc.has_method("change_disposition"):
					npc.change_disposition(-old)
	_modifiers.clear()
