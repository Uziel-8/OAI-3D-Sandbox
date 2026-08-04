extends CanvasLayer
## Always-on gameplay overlay: health / mana / stamina / XP bars, gold counter,
## mission objective, and the level-up toast. Registered as the `HUD` autoload
## so it exists in every scene. Binds to three sources: the player's
## DamageReceiver (group "player_health", re-acquired on scene reload), the
## PlayerProgression autoload (XP/level + level-up toast), and the PlayerState
## autoload (gold/mana/stamina). Display-only -- every node ignores mouse input
## so it never intercepts casting clicks.

@onready var _root: Control = $Root
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _mana_bar: ProgressBar = %ManaBar
@onready var _stamina_bar: ProgressBar = %StaminaBar
@onready var _xp_bar: ProgressBar = %XPBar
@onready var _level_label: Label = %LevelLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _objective_title: Label = %ObjectiveTitle
@onready var _objective_text: Label = %ObjectiveText
@onready var _objective_list: VBoxContainer = %ObjectiveList
@onready var _toast: Label = %LevelUpToast
@onready var _interact_prompt: Label = %InteractPrompt

var _health_receiver: DamageReceiver
var _toast_tween: Tween
var _quests: QuestTracker
## Tracked-sidequest block, appended under the objective panel at runtime.
var _quest_sep: HSeparator
var _quest_title: Label
var _quest_list: VBoxContainer
## Spell bar: one socket per SpellCaster.LOADOUT_ACTIONS entry, bound to the
## player's live SpellCaster (re-acquired on scene reload, like health).
var _spell_slots: Array[HudSpellSlot] = []
var _caster: SpellCaster
var _mana: float = 0.0


func _ready() -> void:
	add_to_group("hud")
	_toast.modulate.a = 0.0

	var prog := get_node_or_null("/root/PlayerProgression")
	if prog:
		prog.experience_gained.connect(_on_xp_changed)
		prog.leveled_up.connect(_on_leveled_up)
		_on_xp_changed(prog.current_xp, prog.xp_to_next(), prog.level)

	var state := get_node_or_null("/root/PlayerState")
	if state:
		state.gold_changed.connect(_on_gold_changed)
		state.mana_changed.connect(_on_mana_changed)
		state.stamina_changed.connect(_on_stamina_changed)
		_on_gold_changed(state.gold)
		_on_mana_changed(state.mana, state.max_mana)
		_on_stamina_changed(state.stamina, state.max_stamina)

	# Health and the SpellCaster both live on the player body, which is recreated
	# on the death-reload, so (re)bind whenever one enters the tree.
	get_tree().node_added.connect(_on_node_added)
	_bind_player_health.call_deferred()

	_build_spell_bar()
	_bind_spell_caster.call_deferred()

	# Neutral default; each level's LevelObjectives node sets its own objective.
	set_objective("No Objective", "Your current objective will appear here.")
	set_interact_prompt("")

	# Sidequest tracker: its own block below the level mission, so accepting a
	# quest never disturbs the level's checklist.
	_build_quest_block()
	_quests = get_node_or_null("/root/QuestSystem")
	if _quests:
		_quests.quest_accepted.connect(_on_quest_changed)
		_quests.quest_ready.connect(_on_quest_changed)
		_quests.quest_completed.connect(_on_quest_changed)
		_quests.quest_progress_changed.connect(_on_quest_changed)
		_quests.tracked_changed.connect(_on_tracked_changed)
		_refresh_quest_tracker()


## Shows/hides the centred interaction prompt (e.g. "[F]  Speak"). Driven by the
## player's PlayerInteractor; empty text hides it.
func set_interact_prompt(text: String) -> void:
	_interact_prompt.text = text
	_interact_prompt.visible = text != ""


func _on_node_added(node: Node) -> void:
	if node.is_in_group("player_health"):
		_bind_player_health()
	# Matched on type, not on group: SpellCaster joins "spell_caster" in _ready,
	# which hasn't run yet at node_added time.
	elif node is SpellCaster:
		_bind_spell_caster.call_deferred()


func _bind_player_health() -> void:
	var receiver := get_tree().get_first_node_in_group("player_health") as DamageReceiver
	if receiver == null or receiver == _health_receiver:
		return
	_health_receiver = receiver
	if not receiver.health_changed.is_connected(_on_health_changed):
		receiver.health_changed.connect(_on_health_changed)
	_on_health_changed(receiver.health, receiver.max_health)


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current


func _on_mana_changed(current: float, maximum: float) -> void:
	_mana_bar.max_value = maximum
	_mana_bar.value = current
	_mana = current


func _on_stamina_changed(current: float, maximum: float) -> void:
	_stamina_bar.max_value = maximum
	_stamina_bar.value = current


func _on_gold_changed(gold: int) -> void:
	_gold_label.text = str(gold)


func _on_xp_changed(current_xp: float, xp_to_next: float, level: int) -> void:
	_xp_bar.max_value = xp_to_next
	_xp_bar.value = current_xp
	_level_label.text = "Lv %d" % level


func _on_leveled_up(new_level: int, _attribute_points: int, _skill_points: int) -> void:
	var prog := get_node_or_null("/root/PlayerProgression")
	if prog:
		_on_xp_changed(prog.current_xp, prog.xp_to_next(), prog.level)
		show_toast("LEVEL UP!", "Level %d   •   +%d attribute, +%d skill points" % [
			new_level, prog.attribute_points_per_level, prog.skill_points_per_level])
	else:
		show_toast("LEVEL UP!", "Level %d" % new_level)


## Fades a message in and out over the centre of the screen. Used for level-ups and
## for quest accepted/complete; public so any system can announce something.
func show_toast(title: String, subtitle: String) -> void:
	_toast.text = "%s\n%s" % [title, subtitle]
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.3)
	_toast_tween.tween_interval(2.2)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)


## Sets the on-screen mission objective as plain prose. Used for levels with no
## objective components, and for the neutral default.
func set_objective(title: String, text: String) -> void:
	_objective_title.text = title
	_objective_text.text = text
	_objective_text.visible = true
	_clear_objective_list()
	_objective_list.visible = false


## Sets the objective panel to a live checklist. `items` is one dictionary per
## objective: {"text": String, "complete": bool, "optional": bool} -- pushed by a
## level's LevelObjectives node as its LevelObjective components report in.
func set_objective_items(title: String, items: Array) -> void:
	_objective_title.text = title
	_objective_text.visible = false
	_clear_objective_list()
	_fill_checklist(_objective_list, items)
	_objective_list.visible = true


func _clear_objective_list() -> void:
	for child in _objective_list.get_children():
		_objective_list.remove_child(child)
		child.queue_free()


## Renders {"text", "complete", "optional"} rows into a container. Shared by the
## level checklist and the sidequest tracker so both read identically.
func _fill_checklist(container: VBoxContainer, items: Array) -> void:
	for item in items:
		var done: bool = item.get("complete", false)
		var line := Label.new()
		var text: String = str(item.get("text", ""))
		if item.get("optional", false):
			text += "  (optional)"
		# Plain ASCII ticks so this renders in the default font regardless of glyph coverage.
		line.text = ("[x]  " if done else "[  ]  ") + text
		line.add_theme_font_size_override("font_size", 13)
		line.add_theme_color_override("font_color",
			Color(0.55, 0.78, 0.55) if done else Color(0.82, 0.8, 0.76))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(line)


# --- Sidequest tracker --------------------------------------------------------

## Appends the tracked-quest block (separator + title + checklist) under the
## existing objective rows. Built in code rather than in hud.tscn, matching how
## the checklist rows themselves are made.
func _build_quest_block() -> void:
	var parent := _objective_list.get_parent()

	_quest_sep = HSeparator.new()
	_quest_sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_sep.visible = false
	parent.add_child(_quest_sep)

	_quest_title = Label.new()
	_quest_title.add_theme_font_size_override("font_size", 14)
	_quest_title.add_theme_color_override("font_color", Color(0.78, 0.72, 0.95))
	_quest_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_title.visible = false
	parent.add_child(_quest_title)

	_quest_list = VBoxContainer.new()
	_quest_list.add_theme_constant_override("separation", 2)
	_quest_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_list.visible = false
	parent.add_child(_quest_list)


func _on_quest_changed(_quest: Quest) -> void:
	_refresh_quest_tracker()


func _on_tracked_changed(_id: StringName) -> void:
	_refresh_quest_tracker()


func _refresh_quest_tracker() -> void:
	if _quests == null:
		return
	var quest := _quests.quest_by_id(_quests.tracked_id)
	if quest == null or _quests.is_completed(quest.id):
		clear_quest_tracker()
		return
	var title := quest.title
	if _quests.is_ready(quest.id):
		title += "  (ready to report)"
	set_quest_tracker(title, _quests.checklist_for(quest.id))


## Shows a tracked sidequest below the level mission. `items` uses the same row
## shape as set_objective_items.
func set_quest_tracker(title: String, items: Array) -> void:
	_quest_title.text = title
	for child in _quest_list.get_children():
		_quest_list.remove_child(child)
		child.queue_free()
	_fill_checklist(_quest_list, items)
	_quest_sep.visible = true
	_quest_title.visible = true
	_quest_list.visible = not items.is_empty()


func clear_quest_tracker() -> void:
	if _quest_sep == null:
		return
	for child in _quest_list.get_children():
		_quest_list.remove_child(child)
		child.queue_free()
	_quest_sep.visible = false
	_quest_title.visible = false
	_quest_list.visible = false


# --- Spell bar ----------------------------------------------------------------
# One socket per hotbar binding, showing what's equipped there and how far its
# cooldown has left to run. Built in code (like the quest block) because the
# sockets come from SpellCaster.LOADOUT_ACTIONS rather than being hand-placed.

## Centred above the XP strip along the bottom edge.
func _build_spell_bar() -> void:
	var separation := 8
	var actions := SpellCaster.LOADOUT_ACTIONS
	var width := actions.size() * HudSpellSlot.SIZE.x + (actions.size() - 1) * separation

	var bar := HBoxContainer.new()
	bar.name = "SpellBar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", separation)
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_left = -width * 0.5
	bar.offset_right = width * 0.5
	bar.offset_top = -HudSpellSlot.SIZE.y - 44.0
	bar.offset_bottom = -44.0
	_root.add_child(bar)

	for action in actions:
		var slot := HudSpellSlot.new()
		slot.action = action
		bar.add_child(slot)
		slot.set_key_text(_key_text_for(action))
		_spell_slots.append(slot)


## Human-readable label for whatever is currently bound to an action, read from
## the InputMap so rebinding a key relabels the bar with no extra bookkeeping.
func _key_text_for(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
			return OS.get_keycode_string(code)
		if event is InputEventMouseButton:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					return "LMB"
				MOUSE_BUTTON_RIGHT:
					return "RMB"
				MOUSE_BUTTON_MIDDLE:
					return "MMB"
				_:
					return "M%d" % event.button_index
	return ""


func _bind_spell_caster() -> void:
	var caster := get_tree().get_first_node_in_group("spell_caster") as SpellCaster
	if caster == _caster:
		return
	_caster = caster
	if _caster and not _caster.loadout_changed.is_connected(_refresh_spell_bar):
		_caster.loadout_changed.connect(_refresh_spell_bar)
	_refresh_spell_bar()


## Re-reads which spell sits in each slot. Cooldown state is polled per frame in
## _process instead -- this only runs when the loadout itself changes.
func _refresh_spell_bar() -> void:
	var caster_valid := _caster != null and is_instance_valid(_caster)
	for slot in _spell_slots:
		var spell: Spell = _caster.equipped_spell(slot.action) if caster_valid else null
		var definition: SpellDefinition = null
		if spell:
			definition = MockSpellbook.find_by_scene_path(spell.scene_file_path)
		slot.set_spell(spell, definition)


func _process(_delta: float) -> void:
	if not _root.visible:
		return
	if _caster != null and not is_instance_valid(_caster):
		_caster = null
		_refresh_spell_bar()
		return
	for slot in _spell_slots:
		slot.refresh(_mana)


## Toggled by the inventory/character screen so the HUD doesn't show behind its
## full-screen backdrop.
func set_hud_visible(shown: bool) -> void:
	_root.visible = shown
