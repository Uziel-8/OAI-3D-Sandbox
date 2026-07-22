extends Node
class_name LevelObjective
## Base for a drop-in objective component -- the "when is this mission done?" half
## of a level, where LevelObjectives holds the "what is the mission?" half.
##
## Add one or more anywhere in a level scene; each registers itself with that
## level's LevelObjectives tracker (found via the "level_objectives" group), so an
## objective can sit wherever makes sense -- inside the Area3D it watches, next to
## the NPC it targets, or grouped under the tracker. Mirrors the drop-in component
## convention used by DamageReceiver / DamageDealer / Interactable.
##
## Subclasses hook their completion signals in _setup() and then call complete()
## (or set_progress() for counted goals). Adding a NEW condition type is a new
## subclass -- nothing here or in the tracker changes.

## Emitted once, when this objective is satisfied.
signal completed(objective: LevelObjective)
## Emitted on any state/progress change, so the HUD checklist can refresh.
signal changed(objective: LevelObjective)

## The line shown in the HUD checklist and on the mission-complete screen.
@export var description: String = "Objective"
## Optional objectives are tracked and displayed but do NOT gate the win.
@export var optional: bool = false
## XP granted when this objective completes (0 = none). Awarded via
## PlayerProgression.add_experience, the documented entry point for quest rewards.
@export var xp_reward: float = 0.0

var is_complete: bool = false

var _current: int = 0
var _total: int = 0  ## 0 = not a counted objective


func _ready() -> void:
	add_to_group("level_objective")
	# Deferred so the tracker and the rest of the level exist before we register
	# and before _setup() goes looking for the things it watches.
	_register.call_deferred()


func _register() -> void:
	var tracker := get_tree().get_first_node_in_group("level_objectives")
	if tracker and tracker.has_method("register_objective"):
		tracker.register_objective(self)
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


## " (2/3)" for counted objectives that aren't finished yet, "" otherwise.
func progress_text() -> String:
	if _total > 0 and not is_complete:
		return " (%d/%d)" % [_current, _total]
	return ""


## The full checklist line, e.g. "Destroy the nests (2/3)".
func checklist_text() -> String:
	return description + progress_text()
