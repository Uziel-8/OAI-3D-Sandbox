extends Node
class_name LevelObjective
## Base for a drop-in objective component -- the "when is this done?" half of a
## goal, where LevelObjectives / Quest hold the "what is the goal?" half.
##
## Add one or more anywhere in a level scene. Where it REGISTERS depends on one
## export:
##   * `quest` blank  -> the level's LevelObjectives tracker (group
##     "level_objectives"). It gates the mission-complete screen, as before.
##   * `quest` set    -> the QuestSystem autoload instead. It tracks that
##     SIDEQUEST and can never gate the level. It also stays DORMANT until the
##     player accepts the quest, so a quest objective can sit in the level from
##     the start doing nothing.
## Everything else -- the subclasses, the signals, the checklist rendering -- is
## identical either way, so every objective type works for both.
##
## Subclasses hook their completion signals in _setup() and then call complete()
## (or set_progress() for counted goals). Adding a NEW condition type is a new
## subclass -- nothing here, in the tracker, or in QuestSystem changes.

## Emitted once, when this objective is satisfied.
signal completed(objective: LevelObjective)
## Emitted on any state/progress change, so the HUD checklist can refresh.
signal changed(objective: LevelObjective)

## The line shown in the HUD checklist and on the mission-complete screen.
@export var description: String = "Objective"
## Optional objectives are tracked and displayed but do NOT gate completion.
@export var optional: bool = false
## XP granted when this objective completes (0 = none). Awarded via
## PlayerProgression.add_experience, the documented entry point for quest rewards.
@export var xp_reward: float = 0.0

@export_group("Quest")
## Set this to make the objective a SIDEQUEST step instead of a level objective:
## it registers with QuestSystem, stays dormant until the quest is accepted, and
## never gates the level's win condition. Leave blank for a level objective.
@export var quest: Quest
## Stable identity for this step in QuestSystem's progress store -- what lets
## "2 of 3 killed" survive the death-reload, since the node is recreated but the
## autoload isn't. Blank = the node's name, which is fine as long as you don't
## rename it mid-playthrough.
@export var key: StringName = &""

var is_complete: bool = false

var _current: int = 0
var _total: int = 0  ## 0 = not a counted objective


func _ready() -> void:
	add_to_group("level_objective")
	# Deferred so the tracker and the rest of the level exist before we register
	# and before _setup() goes looking for the things it watches.
	_register.call_deferred()


func _register() -> void:
	if quest != null:
		_register_with_quest()
		return
	var tracker := get_tree().get_first_node_in_group("level_objectives")
	if tracker and tracker.has_method("register_objective"):
		tracker.register_objective(self)
	_setup()


## Quest-backed registration: restore any stored progress, then only start
## watching the world once the quest is actually active.
func _register_with_quest() -> void:
	var quests := get_node_or_null("/root/QuestSystem")
	if quests == null:
		push_warning("LevelObjective '%s' has a quest but QuestSystem is missing." % name)
		return
	var row: Dictionary = quests.register_objective(self)
	if not row.is_empty():
		restore_state(row["current"], row["total"], row["complete"])
	if is_complete:
		return  # already done in an earlier scene/life -- nothing to watch
	if quests.is_active(quest.id) or quests.is_ready(quest.id):
		_setup()
	elif not quests.quest_accepted.is_connected(_on_quest_accepted):
		quests.quest_accepted.connect(_on_quest_accepted)


func _on_quest_accepted(accepted: Quest) -> void:
	if accepted == null or quest == null or accepted.id != quest.id:
		return
	var quests := get_node_or_null("/root/QuestSystem")
	if quests and quests.quest_accepted.is_connected(_on_quest_accepted):
		quests.quest_accepted.disconnect(_on_quest_accepted)
	_setup()


## Subclasses override: connect whatever signals decide completion. Runs after
## registration, so completing immediately here is safe.
func _setup() -> void:
	pass


## Marks this objective satisfied. Idempotent -- safe to call more than once.
func complete() -> void:
	if is_complete:
		return
	is_complete = true
	if _total > 0:
		_current = _total
	completed.emit(self)
	changed.emit(self)


## Counted progress (e.g. 2 of 3 nests destroyed). Auto-completes at current >= total.
func set_progress(current: int, total: int) -> void:
	_current = current
	_total = total
	changed.emit(self)
	if total > 0 and current >= total:
		complete()


## Seeds state from QuestSystem's store WITHOUT emitting -- used on scene reload so
## a rebuilt node picks up where the freed one left off. Subclasses that keep their
## own counter read it back via current_count().
func restore_state(current: int, total: int, complete_flag: bool) -> void:
	_current = current
	if total > 0:
		_total = total
	is_complete = complete_flag


func current_count() -> int:
	return _current


func total_count() -> int:
	return _total


## The id this objective's row is stored under in QuestSystem. Defaults to the
## node name so most objectives need no explicit key.
func progress_key() -> StringName:
	return key if not String(key).is_empty() else StringName(name)


## " (2/3)" for counted objectives that aren't finished yet, "" otherwise.
func progress_text() -> String:
	if _total > 0 and not is_complete:
		return " (%d/%d)" % [_current, _total]
	return ""


## The full checklist line, e.g. "Destroy the nests (2/3)".
func checklist_text() -> String:
	return description + progress_text()
