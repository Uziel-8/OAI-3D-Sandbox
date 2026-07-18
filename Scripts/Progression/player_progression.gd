extends Node
class_name ProgressionSystem
## Global player progression: experience, level, and unspent attribute/skill
## points. Registered as the `PlayerProgression` autoload, so any system can
## award XP with `PlayerProgression.add_experience(x)` and the character screen
## can bind to its signals. Being an autoload, it PERSISTS across scene reloads
## (e.g. the player-death reload), so progress isn't wiped on death.
##
## COSMETIC-FOR-NOW: attributes (STR/DEX/INT/VIT/LUK) can be raised by spending
## points, but they have NO gameplay effect yet, and level-ups grant points
## without changing max HP / spell power / etc. When stats should start
## mattering, fill in `_apply_level_up()` and `_apply_attributes()` below and
## have the consuming systems read from here. Skill points are tracked purely so
## a future ability-unlock system has a currency to spend -- nothing spends them
## yet. Grep "COSMETIC" for the spots to wire up.

signal experience_gained(current_xp: float, xp_to_next: float, level: int)
signal leveled_up(new_level: int, attribute_points: int, skill_points: int)
signal points_changed(attribute_points: int, skill_points: int)
signal attribute_changed(attribute: String, value: int)

## The allocatable attributes, in display order. (Armor is gear-derived and
## lives in the inventory system, not here.)
const ATTRIBUTES: Array[String] = ["STR", "DEX", "INT", "VIT", "LUK"]

@export var base_xp: float = 100.0
## XP needed for the next level = round(base_xp * level ^ curve_exponent).
@export var curve_exponent: float = 1.5
@export var attribute_points_per_level: int = 3
@export var skill_points_per_level: int = 1

var level: int = 1
var current_xp: float = 0.0
var attribute_points: int = 0
var skill_points: int = 0
var attributes: Dictionary = {"STR": 12, "DEX": 10, "INT": 8, "VIT": 14, "LUK": 9}


## XP required to advance from the current level to the next.
func xp_to_next() -> float:
	return round(base_xp * pow(float(level), curve_exponent))


## Reusable award entry point -- call this from anywhere (enemy deaths now;
## quests, persuasion, exploration, the remove-the-foreman objective later).
func add_experience(amount: float) -> void:
	if amount <= 0.0:
		return
	current_xp += amount
	while current_xp >= xp_to_next():
		current_xp -= xp_to_next()
		_level_up()
	experience_gained.emit(current_xp, xp_to_next(), level)


func _level_up() -> void:
	level += 1
	attribute_points += attribute_points_per_level
	skill_points += skill_points_per_level
	_apply_level_up()
	leveled_up.emit(level, attribute_points, skill_points)
	points_changed.emit(attribute_points, skill_points)


## Spends one attribute point into the given attribute. Returns true on success.
func spend_attribute_point(attribute: String) -> bool:
	if attribute_points <= 0 or not attributes.has(attribute):
		return false
	attribute_points -= 1
	attributes[attribute] += 1
	_apply_attributes()
	attribute_changed.emit(attribute, attributes[attribute])
	points_changed.emit(attribute_points, skill_points)
	return true


## COSMETIC hook: per-level gameplay effects (heal to full, raise max HP, ...)
## go here once stats matter. Intentionally a no-op for now.
func _apply_level_up() -> void:
	pass


## COSMETIC hook: recompute anything derived from attributes (max HP from VIT,
## spell damage from INT, carry weight from STR, ...) here once they matter.
## Intentionally a no-op for now.
func _apply_attributes() -> void:
	pass
