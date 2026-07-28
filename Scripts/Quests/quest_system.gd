class_name QuestTracker
extends Node
## The single owner of sidequest state. Registered as the `QuestSystem` autoload
## (the class_name deliberately differs -- Godot rejects a global class whose name
## matches a singleton, which is why player_progression.gd is
## ProgressionSystem/PlayerProgression).
##
## Being an autoload it persists across the player-death scene reload AND level
## changes, which is the whole point: PROGRESS COUNTERS LIVE HERE, NOT ON THE
## OBJECTIVE NODES. A LevelObjective with its `quest` export set registers its row
## here and is seeded back from the store when the scene is rebuilt, so "2 of 3
## spiders killed" survives dying. Nothing is written to disk -- there is no save
## system yet.
##
## Sidequests are deliberately INDEPENDENT of LevelObjectives: a quest objective
## registers here instead of with the level tracker, so it can never gate the
## mission-complete screen.

## Emitted when the player takes a quest on.
signal quest_accepted(quest: Quest)
## Emitted when every required objective is done and the quest awaits turn-in.
signal quest_ready(quest: Quest)
## Emitted when the quest is handed in (or auto-completes) and rewards are paid.
signal quest_completed(quest: Quest)
## Emitted on any objective progress change, so the HUD/journal can refresh.
signal quest_progress_changed(quest: Quest)
## Emitted when the HUD-tracked quest changes.
signal tracked_changed(quest_id: StringName)

enum QuestState {
	NOT_STARTED,  ## never accepted
	ACTIVE,       ## accepted, objectives outstanding
	READY,        ## objectives done, waiting on the giver (requires_turn_in)
	COMPLETED,    ## handed in, rewards paid
}

## quest_id -> QuestState
var _states: Dictionary = {}
## quest_id -> Quest (populated as givers/objectives register theirs)
var _quests: Dictionary = {}
## quest_id -> { key: {"description", "optional", "current", "total", "complete"} }
var _progress: Dictionary = {}

## The quest shown in the HUD tracker. Empty = none.
var tracked_id: StringName = &""


# --- Registration -------------------------------------------------------------

## Makes a quest resolvable by id. Called by QuestGiver and by quest objectives, so
## a quest is known as soon as anything in the level references it.
func register_quest(quest: Quest) -> void:
	if quest == null or String(quest.id).is_empty():
		if quest != null:
			push_warning("Quest '%s' has no id -- it cannot be tracked." % quest.title)
		return
	_quests[quest.id] = quest
	if not _states.has(quest.id):
		_states[quest.id] = QuestState.NOT_STARTED
	if not _progress.has(quest.id):
		_progress[quest.id] = {}


## Records an objective's row and hooks its signals. MERGES rather than overwrites:
## on a scene reload the row already exists, so the stored counts win and are pushed
## back onto the fresh node (see LevelObjective.restore_state). Returns the row.
func register_objective(objective: LevelObjective) -> Dictionary:
	var quest: Quest = objective.quest
	if quest == null:
		return {}
	register_quest(quest)
	var key: StringName = objective.progress_key()
	var rows: Dictionary = _progress[quest.id]

	if rows.has(key):
		# Reload: keep the stored counts, refresh the authored text/shape.
		var row: Dictionary = rows[key]
		row["description"] = objective.description
		row["optional"] = objective.optional
	else:
		rows[key] = {
			"description": objective.description,
			"optional": objective.optional,
			"current": 0,
			"total": 0,
			"complete": false,
		}

	if not objective.changed.is_connected(_on_objective_changed):
		objective.changed.connect(_on_objective_changed)
	if not objective.completed.is_connected(_on_objective_completed):
		objective.completed.connect(_on_objective_completed)
	return rows[key]


# --- Queries ------------------------------------------------------------------

func quest_by_id(id: StringName) -> Quest:
	return _quests.get(id)


func state_of(id: StringName) -> QuestState:
	return _states.get(id, QuestState.NOT_STARTED)


func is_active(id: StringName) -> bool:
	return state_of(id) == QuestState.ACTIVE


func is_ready(id: StringName) -> bool:
	return state_of(id) == QuestState.READY


func is_completed(id: StringName) -> bool:
	return state_of(id) == QuestState.COMPLETED


## True when the quest has never been taken and every prerequisite is completed.
func can_offer(quest: Quest) -> bool:
	if quest == null or String(quest.id).is_empty():
		return false
	if state_of(quest.id) != QuestState.NOT_STARTED:
		return false
	return prerequisites_met(quest)


func prerequisites_met(quest: Quest) -> bool:
	for prereq in quest.prerequisites:
		if not is_completed(prereq):
			return false
	return true


## True when the giver can accept a hand-in right now: either the objectives are
## done, or the quest has no objectives at all (a pure "go speak to X" errand).
func can_turn_in(quest: Quest) -> bool:
	if quest == null:
		return false
	if is_ready(quest.id):
		return true
	return is_active(quest.id) and _rows(quest.id).is_empty()


## Checklist rows in the exact {"text", "complete", "optional"} shape that
## HUD.set_objective_items already consumes.
func checklist_for(id: StringName) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for key in _rows(id):
		var row: Dictionary = _rows(id)[key]
		var text: String = row["description"]
		var total: int = row["total"]
		if total > 0 and not row["complete"]:
			text += " (%d/%d)" % [row["current"], total]
		items.append({
			"text": text,
			"complete": row["complete"],
			"optional": row["optional"],
		})
	return items


func active_quests() -> Array[Quest]:
	return _quests_in([QuestState.ACTIVE, QuestState.READY])


func completed_quests() -> Array[Quest]:
	return _quests_in([QuestState.COMPLETED])


# --- Mutations ----------------------------------------------------------------

## Takes the quest on. `giver` is the NPC offering it (used only for logging today;
## rewards resolve their own targets on turn-in).
func accept(quest: Quest, _giver: Node = null) -> bool:
	if quest == null or not can_offer(quest):
		return false
	register_quest(quest)
	_states[quest.id] = QuestState.ACTIVE
	set_tracked(quest.id)
	quest_accepted.emit(quest)
	_toast("QUEST ACCEPTED", quest.title)
	# An objective may already be satisfied (or the quest may have none), so
	# evaluate immediately rather than waiting for the next world event.
	_check_quest(quest)
	return true


## Pays out and closes the quest. Safe to call more than once.
func turn_in(quest: Quest, giver: Node = null) -> bool:
	if quest == null:
		return false
	var state := state_of(quest.id)
	if state != QuestState.ACTIVE and state != QuestState.READY:
		return false
	_states[quest.id] = QuestState.COMPLETED
	_award(quest, giver)
	if tracked_id == quest.id:
		_retrack()
	quest_completed.emit(quest)
	_toast("QUEST COMPLETE", quest.title)
	return true


## Pins a quest to the HUD tracker. Pass &"" to clear.
func set_tracked(id: StringName) -> void:
	if tracked_id == id:
		return
	tracked_id = id
	tracked_changed.emit(id)


## Clears all quest state. No UI yet -- here so a future new-game has one call.
func reset() -> void:
	_states.clear()
	_progress.clear()
	tracked_id = &""
	tracked_changed.emit(tracked_id)


# --- Objective plumbing -------------------------------------------------------

func _on_objective_changed(objective: LevelObjective) -> void:
	_sync(objective)
	var quest: Quest = objective.quest
	if quest:
		quest_progress_changed.emit(quest)
		_check_quest(quest)


func _on_objective_completed(objective: LevelObjective) -> void:
	_sync(objective)
	# Per-objective XP pays out as it's earned, mirroring LevelObjectives; the
	# quest's own xp_reward is a separate lump on turn-in.
	if objective.xp_reward > 0.0:
		var progression := get_node_or_null("/root/PlayerProgression")
		if progression and progression.has_method("add_experience"):
			progression.add_experience(objective.xp_reward)


func _sync(objective: LevelObjective) -> void:
	var quest: Quest = objective.quest
	if quest == null or not _progress.has(quest.id):
		return
	var rows: Dictionary = _progress[quest.id]
	var key: StringName = objective.progress_key()
	if not rows.has(key):
		return
	var row: Dictionary = rows[key]
	row["description"] = objective.description
	row["optional"] = objective.optional
	row["current"] = objective.current_count()
	row["total"] = objective.total_count()
	row["complete"] = objective.is_complete


## Promotes an ACTIVE quest to READY (or straight to completed) once every
## non-optional row is done. A quest with no rows yet is never auto-promoted --
## its objectives may simply live in a level that isn't loaded.
func _check_quest(quest: Quest) -> void:
	if not is_active(quest.id):
		return
	var rows: Dictionary = _rows(quest.id)
	if rows.is_empty():
		return
	for key in rows:
		var row: Dictionary = rows[key]
		if not row["optional"] and not row["complete"]:
			return
	if quest.requires_turn_in:
		_states[quest.id] = QuestState.READY
		quest_ready.emit(quest)
		_toast("OBJECTIVES COMPLETE", "Report back: %s" % quest.title)
	else:
		turn_in(quest)


# --- Rewards ------------------------------------------------------------------

func _award(quest: Quest, giver: Node) -> void:
	var progression := get_node_or_null("/root/PlayerProgression")
	if progression:
		if quest.xp_reward > 0.0 and progression.has_method("add_experience"):
			progression.add_experience(quest.xp_reward)
		if quest.skill_point_reward > 0 and progression.has_method("grant_skill_points"):
			progression.grant_skill_points(quest.skill_point_reward)

	if quest.gold_reward > 0:
		var state := get_node_or_null("/root/PlayerState")
		if state and state.has_method("add_gold"):
			state.add_gold(quest.gold_reward)

	if quest.giver_disposition != 0 and giver and giver.has_method("change_disposition"):
		giver.change_disposition(quest.giver_disposition)

	var reputation := get_node_or_null("/root/Reputation")
	if reputation and reputation.has_method("adjust"):
		for reward in quest.faction_rewards:
			if reward:
				reputation.adjust(reward.faction, reward.delta)


# --- Internals ----------------------------------------------------------------

func _rows(id: StringName) -> Dictionary:
	return _progress.get(id, {})


func _quests_in(states: Array) -> Array[Quest]:
	var out: Array[Quest] = []
	for id in _quests:
		if state_of(id) in states:
			out.append(_quests[id])
	return out


## Moves the HUD tracker to another active quest once the tracked one closes.
func _retrack() -> void:
	for id in _quests:
		var state := state_of(id)
		if state == QuestState.ACTIVE or state == QuestState.READY:
			set_tracked(id)
			return
	set_tracked(&"")


func _toast(title: String, subtitle: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_toast"):
		hud.show_toast(title, subtitle)
