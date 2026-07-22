class_name LevelCompleteScreen
extends Control
## "Mission Complete" screen, opened when a level's LevelObjectives reports every
## required objective satisfied. Registered as the `LevelCompleteUI` autoload and
## follows the menu-screen conventions (pause + mouse release, shared theme,
## click-eating backdrop, process_mode ALWAYS, HUD-hide, "menu_screen" group).
## Like DialogueScreen, the script sits on the autoload's `Screen` child, so it's
## found via the "level_complete_screen" group -- NOT /root/LevelCompleteUI, which
## is the CanvasLayer.
##
## Unlike the other menus this one is NOT toggleable: the level opens it, and it's
## dismissed only via Continue, which loads that level's `next_level` (or just
## closes when there isn't one). Progression carries across the scene change for
## free, since PlayerProgression / SkillSystem / PlayerState are autoloads.

@onready var _heading: Label = %Heading
@onready var _subheading: Label = %Subheading
@onready var _objective_list: VBoxContainer = %ObjectiveList
@onready var _xp_label: Label = %XPLabel
@onready var _continue_button: Button = %ContinueButton

var is_open := false
var _next_level: PackedScene


func _ready() -> void:
	add_to_group("menu_screen")
	add_to_group("level_complete_screen")
	visible = false
	_continue_button.pressed.connect(_on_continue_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	# While this is up, swallow the other menu toggles so nothing can open over it
	# (which would also close this via the menu_screen mutual exclusion, stranding
	# the player in a finished level). This autoload is registered LAST so it sees
	# unhandled input before InventoryUI / JournalUI.
	if event.is_action_pressed("inventory") or event.is_action_pressed("journal") \
			or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()


## Called by a level's LevelObjectives once the mission is won. `entries` is the
## same {"text", "optional", "complete"} row shape the HUD checklist uses.
func show_result(heading: String, mission: String, entries: Array, xp_earned: float,
		next_level: PackedScene) -> void:
	_next_level = next_level
	_heading.text = heading
	_subheading.text = mission

	for child in _objective_list.get_children():
		_objective_list.remove_child(child)
		child.queue_free()
	for entry in entries:
		var done: bool = entry.get("complete", false)
		var text: String = str(entry.get("text", ""))
		if entry.get("optional", false):
			text += "  (optional)"
		var line := Label.new()
		line.text = ("[x]  " if done else "[  ]  ") + text
		line.add_theme_font_size_override("font_size", 15)
		line.add_theme_color_override("font_color",
			Color(0.55, 0.78, 0.55) if done else Color(0.6, 0.58, 0.55))
		_objective_list.add_child(line)

	_xp_label.text = "Experience earned:  %d" % int(round(xp_earned))
	_xp_label.visible = xp_earned > 0.0
	_continue_button.text = "Continue" if _next_level else "Close"
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


func _on_continue_pressed() -> void:
	var next := _next_level
	# close() first: unpauses and recaptures the mouse BEFORE the swap, so the next
	# level starts live rather than inheriting a paused tree.
	close()
	if next:
		get_tree().change_scene_to_packed(next)


func _close_other_menus() -> void:
	for menu in get_tree().get_nodes_in_group("menu_screen"):
		if menu != self and menu.is_open:
			menu.close()


func _set_hud_visible(shown: bool) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hud_visible"):
		hud.set_hud_visible(shown)
