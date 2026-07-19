extends Node
class_name LevelObjectives
## Drop this node into a level scene to define that level's objective and journal.
## On load it pushes them to the HUD objective panel and the Journal, replacing
## whatever the previous level set -- so each level shows its own goals.
##
## THIS is the place to edit a level's objective as the game grows: select the
## LevelObjectives node in the level scene and edit these fields in the inspector.

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


func _ready() -> void:
	# Deferred so it runs once the whole scene (and the UI autoloads) are ready,
	# and re-applies cleanly on scene reload / level change.
	_apply.call_deferred()


## Pushes this level's objective + journal to the UI. Public so a future quest
## system could re-apply after mutating the fields at runtime.
func apply() -> void:
	_apply()


func _apply() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_objective"):
		hud.set_objective(objective_title, objective_text)

	var journal := get_tree().get_first_node_in_group("journal_screen")
	if journal and journal.has_method("set_entries"):
		journal.set_entries(_build_entries())


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
