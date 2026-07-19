class_name JournalScreen
extends Control
## Read-only journal: a list of titled entries on the left, the selected entry's
## text on the right. Registered as the `JournalUI` autoload and toggled by the
## `journal` action (J), mirroring the inventory screen's conventions -- pause +
## mouse release, shared theme, click-eating backdrop, process_mode ALWAYS so it
## keeps working while it pauses the tree. Entries are seeded from MockJournal;
## real code logs new ones at runtime via add_entry().

@onready var _entry_list: ItemList = %EntryList
@onready var _entry_title: Label = %EntryTitle
@onready var _entry_body: RichTextLabel = %EntryBody
@onready var _close_button: Button = %CloseButton

var is_open := false
var _entries: Array[JournalEntry] = []


func _ready() -> void:
	add_to_group("menu_screen")
	visible = false
	_close_button.pressed.connect(close)
	_entry_list.item_selected.connect(_on_entry_selected)
	for entry in MockJournal.starting_entries():
		add_entry(entry)
	if not _entries.is_empty():
		_entry_list.select(0)
		_show_entry(0)


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


## Appends a read-only entry and returns its index. The reusable entry point for
## quests/objectives/lore pickups to log to the journal later.
func add_entry(entry: JournalEntry) -> int:
	_entries.append(entry)
	_entry_list.add_item(entry.title)
	return _entries.size() - 1


func _on_entry_selected(index: int) -> void:
	_show_entry(index)


func _show_entry(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	var entry := _entries[index]
	_entry_title.text = entry.title
	_entry_body.text = entry.body


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
