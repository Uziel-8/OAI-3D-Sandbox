class_name JournalScreen
extends Control
## Read-only journal: a list of titled rows on the left, the selected row's text on
## the right. Registered as the `JournalUI` autoload and toggled by the `journal`
## action (J), mirroring the inventory screen's conventions -- pause + mouse
## release, shared theme, click-eating backdrop, process_mode ALWAYS so it keeps
## working while it pauses the tree.
##
## The list is composed from TWO independent sources, which is what stops a level
## load from wiping quest progress:
##   * SIDEQUESTS, read live from the QuestSystem autoload each rebuild. Never
##     stored here, so they survive scene reloads and level changes for free, and
##     their objective checklists are always current.
##   * The LEVEL's entries (its objective + lore), replaced wholesale by that
##     level's LevelObjectives node via set_entries().
## Sections are rendered as non-selectable header rows in the ItemList.

@onready var _entry_list: ItemList = %EntryList
@onready var _entry_title: Label = %EntryTitle
@onready var _entry_body: RichTextLabel = %EntryBody
@onready var _close_button: Button = %CloseButton

const HEADER_COLOR := Color(0.95, 0.86, 0.6)
const COMPLETE_COLOR := Color(0.55, 0.78, 0.55)

var is_open := false

## Rows currently in the ItemList, parallel to it. Each is
## {"kind": "header"/"quest"/"entry", "quest_id": StringName, "entry": JournalEntry}.
var _rows: Array[Dictionary] = []
## This level's entries only -- what set_entries() replaces.
var _level_entries: Array[JournalEntry] = []
var _track_button: Button
var _quests: QuestTracker


func _ready() -> void:
	add_to_group("menu_screen")
	add_to_group("journal_screen")
	visible = false
	_close_button.pressed.connect(close)
	_entry_list.item_selected.connect(_on_entry_selected)
	_build_track_button()

	_quests = get_node_or_null("/root/QuestSystem")
	if _quests:
		_quests.quest_accepted.connect(_on_quest_changed)
		_quests.quest_ready.connect(_on_quest_changed)
		_quests.quest_completed.connect(_on_quest_changed)
		_quests.quest_progress_changed.connect(_on_quest_changed)
		_quests.tracked_changed.connect(_on_tracked_changed)

	# Generic fallback log; a level's LevelObjectives node replaces this on load
	# with that level's own entries (see set_entries).
	set_entries(MockJournal.starting_entries())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("journal"):
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	_close_other_menus()
	is_open = true
	visible = true
	_set_hud_visible(false)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	is_open = false
	visible = false
	_set_hud_visible(true)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Appends a read-only entry to this level's log and returns its index. The
## reusable entry point for lore pickups and one-off notes.
func add_entry(entry: JournalEntry) -> int:
	_level_entries.append(entry)
	_rebuild()
	return _level_entries.size() - 1


## Replaces this level's entries (objective + lore) and selects the first row.
## Used by a level's LevelObjectives node so each level shows its own log.
## Quest rows are NOT touched -- they're owned by QuestSystem.
func set_entries(entries: Array[JournalEntry]) -> void:
	_level_entries = entries.duplicate()
	_rebuild()


# --- List building ------------------------------------------------------------

func _on_quest_changed(_quest: Quest) -> void:
	_rebuild()


func _on_tracked_changed(_id: StringName) -> void:
	_rebuild()


## Rebuilds the whole list from the two sources, preserving the selected row where
## it still exists.
func _rebuild() -> void:
	var previous := _selected_row()
	_rows.clear()
	_entry_list.clear()

	var active: Array[Quest] = _quests.active_quests() if _quests else []
	var done: Array[Quest] = _quests.completed_quests() if _quests else []

	if not active.is_empty():
		_add_header("ACTIVE QUESTS")
		for quest in active:
			_add_quest(quest)
	if not done.is_empty():
		_add_header("COMPLETED")
		for quest in done:
			_add_quest(quest)
	# Only label the level's own log once there are quest sections above it to
	# separate from; otherwise the list reads exactly as it did before.
	if not _level_entries.is_empty() and (not active.is_empty() or not done.is_empty()):
		_add_header("JOURNAL")
	for entry in _level_entries:
		_add_entry_row(entry)

	_restore_selection(previous)


func _add_header(text: String) -> void:
	var index := _entry_list.add_item(text)
	_entry_list.set_item_disabled(index, true)  # non-selectable divider
	_entry_list.set_item_custom_fg_color(index, HEADER_COLOR)
	_rows.append({"kind": "header", "quest_id": &"", "entry": null})


func _add_quest(quest: Quest) -> void:
	var label := "  " + quest.title
	if _quests and _quests.is_ready(quest.id):
		label += "  (ready)"
	var index := _entry_list.add_item(label)
	if _quests and _quests.is_completed(quest.id):
		_entry_list.set_item_custom_fg_color(index, COMPLETE_COLOR)
	_rows.append({"kind": "quest", "quest_id": quest.id, "entry": null})


func _add_entry_row(entry: JournalEntry) -> void:
	_entry_list.add_item(entry.title)
	_rows.append({"kind": "entry", "quest_id": &"", "entry": entry})


# --- Selection / content ------------------------------------------------------

func _on_entry_selected(index: int) -> void:
	_show_row(index)


func _selected_row() -> Dictionary:
	var selected := _entry_list.get_selected_items()
	if selected.is_empty() or selected[0] >= _rows.size():
		return {}
	return _rows[selected[0]]


## Re-selects the row that was showing before a rebuild, falling back to the first
## selectable row.
func _restore_selection(previous: Dictionary) -> void:
	var target := -1
	if not previous.is_empty():
		for i in _rows.size():
			var row := _rows[i]
			if row["kind"] != previous["kind"]:
				continue
			if row["kind"] == "quest" and row["quest_id"] == previous["quest_id"]:
				target = i
				break
			if row["kind"] == "entry" and row["entry"] == previous["entry"]:
				target = i
				break
	if target < 0:
		target = _first_selectable()
	if target < 0:
		_entry_title.text = ""
		_entry_body.text = ""
		_track_button.visible = false
		return
	_entry_list.select(target)
	_show_row(target)


func _first_selectable() -> int:
	for i in _rows.size():
		if _rows[i]["kind"] != "header":
			return i
	return -1


func _show_row(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	var row := _rows[index]
	match row["kind"]:
		"quest":
			_show_quest(row["quest_id"])
		"entry":
			var entry: JournalEntry = row["entry"]
			_entry_title.text = entry.title
			_entry_body.text = entry.body
			_track_button.visible = false
		_:
			pass  # headers are non-selectable


## Renders a quest live: status, giver, summary, its objective checklist, rewards.
func _show_quest(id: StringName) -> void:
	if _quests == null:
		return
	var quest := _quests.quest_by_id(id)
	if quest == null:
		return
	_entry_title.text = quest.title

	var parts: Array[String] = []
	parts.append("Status:  %s" % _status_text(id))
	if quest.giver_name != "":
		parts.append("Given by %s" % quest.giver_name)
	if quest.summary != "":
		parts.append("\n%s" % quest.summary)

	var checklist := _quests.checklist_for(id)
	if not checklist.is_empty():
		var lines: Array[String] = ["\nObjectives:"]
		for item in checklist:
			# Plain ASCII ticks, matching the HUD checklist -- renders in the
			# default font regardless of glyph coverage.
			var text: String = str(item.get("text", ""))
			if item.get("optional", false):
				text += "  (optional)"
			lines.append(("  [x]  " if item.get("complete", false) else "  [  ] ") + text)
		parts.append("\n".join(lines))

	var rewards := quest.reward_text()
	if rewards != "":
		parts.append("\nReward:  %s" % rewards)

	_entry_body.text = "\n".join(parts)
	_update_track_button(id)


func _status_text(id: StringName) -> String:
	if _quests.is_completed(id):
		return "Completed"
	if _quests.is_ready(id):
		return "Ready to report"
	if _quests.is_active(id):
		return "Active"
	return "Not started"


# --- Track button -------------------------------------------------------------

## Built in code rather than added to journal_screen.tscn -- the same approach the
## dialogue screen uses for its choice buttons and the character sheet for its
## attribute rows, and it avoids editing NodePaths in the scene file.
func _build_track_button() -> void:
	_track_button = Button.new()
	_track_button.focus_mode = Control.FOCUS_NONE
	_track_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_track_button.visible = false
	_track_button.pressed.connect(_on_track_pressed)
	var content := _entry_title.get_parent()
	content.add_child(_track_button)
	content.move_child(_track_button, _entry_title.get_index() + 1)


func _update_track_button(id: StringName) -> void:
	if _quests == null or _quests.is_completed(id):
		_track_button.visible = false
		return
	var tracked: bool = _quests.tracked_id == id
	_track_button.visible = true
	_track_button.disabled = tracked
	_track_button.text = "Tracked on HUD" if tracked else "Track on HUD"


func _on_track_pressed() -> void:
	var row := _selected_row()
	if row.is_empty() or row["kind"] != "quest" or _quests == null:
		return
	_quests.set_tracked(row["quest_id"])


# --- Menu conventions ---------------------------------------------------------

## Closes any other open menu screen (inventory/journal) so only one is up at a
## time -- otherwise closing one would unpause/recapture the mouse under another.
func _close_other_menus() -> void:
	for menu in get_tree().get_nodes_in_group("menu_screen"):
		if menu != self and menu.is_open:
			menu.close()


func _set_hud_visible(shown: bool) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hud_visible"):
		hud.set_hud_visible(shown)
