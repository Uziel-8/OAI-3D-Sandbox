class_name DialogueScreen
extends Control
## Simple read-only dialogue panel, opened by an Interactable via start(). Shows a
## speaker name + one line at a time, advancing on click / ui_accept, closing on
## the last line or ui_cancel. Registered as the `DialogueUI` autoload and follows
## the menu-screen conventions (pause + mouse release, shared theme, backdrop,
## process_mode ALWAYS, HUD-hide, mutually exclusive via group "menu_screen").
## Built to grow into branching choices + disposition later; for now it's lines.

@onready var _speaker_label: Label = %SpeakerLabel
@onready var _body_label: RichTextLabel = %BodyLabel
@onready var _advance_button: Button = %AdvanceButton

var is_open := false
var _lines: Array[String] = []
var _index := 0


func _ready() -> void:
	add_to_group("menu_screen")
	add_to_group("dialogue_screen")
	visible = false
	_advance_button.pressed.connect(_advance)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_accept"):
		_advance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Opens the panel with the given speaker and lines. No-op if there are no lines.
func start(speaker: String, lines: Array[String]) -> void:
	if lines.is_empty():
		return
	_close_other_menus()
	_lines = lines.duplicate()
	_index = 0
	_speaker_label.text = speaker
	_speaker_label.visible = speaker != ""
	is_open = true
	visible = true
	_set_hud_visible(false)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_line()


func close() -> void:
	is_open = false
	visible = false
	_set_hud_visible(true)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show_line() -> void:
	_body_label.text = _lines[_index]
	_advance_button.text = "Leave" if _index >= _lines.size() - 1 else "Continue"


func _advance() -> void:
	if not is_open:
		return
	_index += 1
	if _index >= _lines.size():
		close()
	else:
		_show_line()


func _close_other_menus() -> void:
	for menu in get_tree().get_nodes_in_group("menu_screen"):
		if menu != self and menu.is_open:
			menu.close()


func _set_hud_visible(shown: bool) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hud_visible"):
		hud.set_hud_visible(shown)
