extends Node
class_name LevelObjectives
## Drop this node into a level scene to define that level's mission: its objective
## text, its journal, AND its win condition. On load it pushes the objective to the
## HUD panel and the entries to the Journal, replacing whatever the previous level
## set -- so each level shows its own goals.
##
## THIS is the place to edit a level's mission as the game grows: select the
## LevelObjectives node in the level scene and edit these fields in the inspector.
##
## WIN CONDITION: add LevelObjective components (KillTarget / DestroyGroup /
## ReachArea / Interact -- see Scripts/Level/Objectives/) anywhere in the level.
## They self-register here via the "level_objectives" group. Once every
## non-optional one is satisfied the level is complete: XP is awarded and the
## mission-complete screen opens, with Continue loading `next_level`.
## A level with NO objective components simply never auto-completes and shows the
## plain objective text, exactly as before.

## Emitted whenever an objective's state or progress changes.
signal objectives_changed
## Emitted once, when every required objective is satisfied.
signal level_completed

## Shown in the always-on HUD objective panel (top-left).
@export var objective_title: String = "Objective"
@export_multiline var objective_text: String = ""

## If true, the objective above is also added as the first journal entry, so you
## only write it once (categorised "Objective").
@export var objective_in_journal: bool = true

## Extra journal entries for this level (lore, clues, sub-goals), shown after the
## objective. Editable in the inspector: press Add Element and fill each entry's
## title / body / category.
@export var journal_entries: Array[JournalEntry] = []

@export_group("Completion")
## Scene the win screen's Continue button loads. Leave empty on the last level --
## Continue then just closes and returns you to the finished level.
@export var next_level: PackedScene
## Bonus XP for finishing the level, on top of each objective's own xp_reward.
@export var completion_xp: float = 0.0
## Heading shown on the mission-complete screen.
@export var complete_title: String = "Mission Complete"

## One cached row per registered objective: {"text", "optional", "complete"}.
## Cached rather than read live off the node because an objective attached to
## something that dies (a kill target) can be freed the instant it completes.
var _entries: Array[Dictionary] = []
var _objectives: Array[LevelObjective] = []
var _xp_earned: float = 0.0
var _finished := false


func _ready() -> void:
	add_to_group("level_objectives")
	# Deferred so it runs once the whole scene (and the UI autoloads) are ready,
	# and re-applies cleanly on scene reload / level change.
	_apply.call_deferred()


## Pushes this level's objective + journal to the UI. Public so a future quest
## system could re-apply after mutating the fields at runtime.
func apply() -> void:
	_apply()


# --- Objective registration / completion --------------------------------------

## Called by LevelObjective components as they register themselves.
func register_objective(objective: LevelObjective) -> void:
	if objective in _objectives:
		return
	_objectives.append(objective)
	_entries.append({
		"text": objective.checklist_text(),
		"optional": objective.optional,
		"complete": objective.is_complete,
	})
	objective.changed.connect(_on_objective_changed)
	objective.completed.connect(_on_objective_completed)
	_refresh.call_deferred()


func _on_objective_changed(objective: LevelObjective) -> void:
	_sync_entry(objective)
	_refresh()


func _on_objective_completed(objective: LevelObjective) -> void:
	_sync_entry(objective)
	if objective.xp_reward > 0.0:
		_award_xp(objective.xp_reward)
	_refresh()
	_check_complete()


func _sync_entry(objective: LevelObjective) -> void:
	var index := _objectives.find(objective)
	if index < 0:
		return
	_entries[index]["text"] = objective.checklist_text()
	_entries[index]["optional"] = objective.optional
	_entries[index]["complete"] = objective.is_complete


## The level is won once every non-optional objective is complete. Levels with no
## objective components never fire this.
func _check_complete() -> void:
	if _finished or _entries.is_empty():
		return
	for entry in _entries:
		if not entry["optional"] and not entry["complete"]:
			return
	_finished = true
	if completion_xp > 0.0:
		_award_xp(completion_xp)
	level_completed.emit()
	# Deferred: an Interactable emits `interacted` (which can finish the level)
	# BEFORE it opens its dialogue, so showing the screen immediately would let the
	# dialogue pop on top of it. Waiting a frame means we open last and close it.
	_show_complete_screen.call_deferred()


func _award_xp(amount: float) -> void:
	_xp_earned += amount
	var progression := get_node_or_null("/root/PlayerProgression")
	if progression and progression.has_method("add_experience"):
		progression.add_experience(amount)


func _show_complete_screen() -> void:
	var screen := get_tree().get_first_node_in_group("level_complete_screen")
	if screen and screen.has_method("show_result"):
		screen.show_result(complete_title, objective_title, _entries.duplicate(true), _xp_earned, next_level)


# --- UI push ------------------------------------------------------------------

func _apply() -> void:
	_refresh()
	var journal := get_tree().get_first_node_in_group("journal_screen")
	if journal and journal.has_method("set_entries"):
		journal.set_entries(_build_entries())


## Pushes the objective to the HUD -- as a live checklist when this level has
## objective components, or the plain title/text when it doesn't.
func _refresh() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		if not _entries.is_empty() and hud.has_method("set_objective_items"):
			hud.set_objective_items(objective_title, _entries)
		elif hud.has_method("set_objective"):
			hud.set_objective(objective_title, objective_text)
	objectives_changed.emit()


func _build_entries() -> Array[JournalEntry]:
	var entries: Array[JournalEntry] = []
	if objective_in_journal:
		var obj := JournalEntry.new()
		obj.title = objective_title
		obj.body = objective_text
		obj.category = "Objective"
		entries.append(obj)
	entries.append_array(journal_entries)
	return entries
