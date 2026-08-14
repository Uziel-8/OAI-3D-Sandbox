class_name DialogueScreen
extends Control
## Dialogue panel opened by an Interactable via start(). Shows a speaker + the
## intro lines one at a time (advance on click / ui_accept), then, if the
## Interactable authored any, a list of CHOICE buttons. A choice can cost gold
## (spent via PlayerState; the button is disabled when unaffordable) and shift the
## TARGET NPC's disposition, then show a response line before closing.
##
## Registered as the `DialogueUI` autoload; follows the menu-screen conventions
## (pause + mouse release, shared theme, backdrop, process_mode ALWAYS, HUD-hide,
## mutually exclusive via group "menu_screen"). Flat "lines -> choices" model for
## now; branching (a choice leading to more dialogue) is the next step.

## Emitted after a choice's effects are applied. Lets quests/objectives react to a
## specific dialogue OUTCOME rather than to the fact that talking happened at all.
signal choice_selected(choice: DialogueChoice, target: Node)

@onready var _speaker_label: Label = %SpeakerLabel
@onready var _body_label: RichTextLabel = %BodyLabel
@onready var _advance_button: Button = %AdvanceButton
@onready var _choices_box: VBoxContainer = %ChoicesBox

var is_open := false
var _lines: Array[String] = []
var _choices: Array[DialogueChoice] = []
var _target: Node = null
var _index := 0
## Counter to hand over to once the player dismisses the chosen line -- a
## ShopKeeper (opens_shop) or a TradeExchange (opens_market). Deferring to the
## dismissal rather than opening immediately is what lets a merchant still deliver
## his "Of course, young man!" before the counter appears; backing out with Escape
## drops it (close() clears this). Kept generic (component + which screen opens it +
## what the button reads) so the next counter type needs no new fields here.
var _pending_counter: Node = null
var _pending_screen_group: StringName = &""
var _pending_label: String = ""


func _ready() -> void:
	add_to_group("menu_screen")
	add_to_group("dialogue_screen")
	visible = false
	_choices_box.visible = false
	_advance_button.pressed.connect(_advance)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	# ui_accept only advances lines -- never auto-picks a choice, so Enter can't
	# skip the decision.
	elif event.is_action_pressed("ui_accept") and not _choices_box.visible:
		_advance()
		get_viewport().set_input_as_handled()


## Opens the panel. `choices`/`target` are optional -- with none it's a plain
## linear reader. `target` receives choice effects (e.g. change_disposition).
func start(speaker: String, lines: Array[String], choices: Array[DialogueChoice] = [],
		target: Node = null) -> void:
	if lines.is_empty() and choices.is_empty():
		return
	_close_other_menus()
	_lines = lines.duplicate()
	_choices = choices
	_target = target
	_index = 0
	_speaker_label.text = speaker
	_speaker_label.visible = speaker != ""
	is_open = true
	visible = true
	_set_hud_visible(false)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _lines.is_empty():
		_show_choices()
	else:
		_show_line()


func close() -> void:
	is_open = false
	visible = false
	_clear_choices()
	_lines = []
	_choices = []
	_target = null
	_clear_pending_counter()
	_set_hud_visible(true)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show_line() -> void:
	_choices_box.visible = false
	_advance_button.visible = true
	_body_label.text = _lines[_index]
	var last := _index >= _lines.size() - 1
	# On the last line, the button leads to the choices (if any) or leaves.
	_advance_button.text = "Continue" if not last else ("Consider…" if not _choices.is_empty() else "Leave")


func _advance() -> void:
	if not is_open:
		return
	if _index < _lines.size() - 1:
		_index += 1
		_show_line()
	elif not _choices.is_empty():
		_show_choices()
	elif _pending_counter:
		_open_pending_counter()
	else:
		close()


## Hands over to whichever counter screen was queued. close() clears the pending
## fields, so they're captured first -- and closing before opening keeps the tree
## from being left paused by two screens at once (the same ordering
## LevelCompleteScreen needs).
func _open_pending_counter() -> void:
	var component := _pending_counter
	var group := _pending_screen_group
	close()
	if not is_instance_valid(component):
		return
	var screen := get_tree().get_first_node_in_group(group)
	if screen and screen.has_method("open"):
		screen.open(component)


func _clear_pending_counter() -> void:
	_pending_counter = null
	_pending_screen_group = &""
	_pending_label = ""


func _show_choices() -> void:
	_advance_button.visible = false
	_clear_choices()
	var gold := _player_gold()
	for choice in _choices:
		var button := Button.new()
		var label := choice.text
		if choice.gold_cost > 0:
			label += "   (%d gold)" % choice.gold_cost
		button.text = label
		button.focus_mode = Control.FOCUS_NONE
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if choice.gold_cost > 0 and gold < choice.gold_cost:
			button.disabled = true  # can't afford this bribe
		button.pressed.connect(apply_choice.bind(choice))
		_choices_box.add_child(button)
	_choices_box.visible = true


## Applies a choice's effects then shows its response (or closes). Public so it's
## unit-testable; the choice buttons call it via bind().
func apply_choice(choice: DialogueChoice) -> void:
	if choice.gold_cost > 0:
		var ps := get_node_or_null("/root/PlayerState")
		if ps == null or not ps.spend_gold(choice.gold_cost):
			return  # unaffordable -- button should have been disabled
	if _target and _target.has_method("change_disposition") and choice.disposition_delta != 0:
		_target.change_disposition(choice.disposition_delta)
	# Quest effects run after the gold spend, so an unaffordable choice bails out
	# above without changing any quest state.
	_apply_quest_action(choice)
	# Counter handoffs. A choice that sets both takes the shop, arbitrarily -- an
	# NPC who is both a vendor and a broker should offer two choices, not one.
	_clear_pending_counter()
	if choice.opens_shop:
		_queue_counter(ShopKeeper.find_in(_target), &"shop_screen", "Browse Wares")
	elif choice.opens_market:
		_queue_counter(TradeExchange.find_in(_target), &"market_screen", "See the Board")
	choice_selected.emit(choice, _target)

	_choices_box.visible = false
	if choice.response != "":
		# Reset to a single "Leave" step: clearing lines+choices makes _advance close.
		_body_label.text = choice.response
		_lines = []
		_choices = []
		_index = 0
		_advance_button.visible = true
		_advance_button.text = _pending_label if _pending_counter else "Leave"
	elif _pending_counter:
		_open_pending_counter()
	else:
		close()


## Queues a counter component for handoff once the response line is dismissed.
## A missing component is simply not queued, so a choice pointed at an NPC with no
## such component just closes rather than dead-ending.
func _queue_counter(component: Node, screen_group: StringName, button_label: String) -> void:
	if component == null:
		return
	_pending_counter = component
	_pending_screen_group = screen_group
	_pending_label = button_label


## Routes a choice's quest_action to QuestSystem, with the dialogue's target (the
## NPC) as the giver so giver_disposition rewards land on the right body. Looked up
## by autoload path so the dialogue screen keeps working with no quest system.
func _apply_quest_action(choice: DialogueChoice) -> void:
	if choice.quest == null or choice.quest_action == DialogueChoice.QuestAction.NONE:
		return
	var quests := get_node_or_null("/root/QuestSystem")
	if quests == null:
		return
	match choice.quest_action:
		DialogueChoice.QuestAction.ACCEPT:
			quests.accept(choice.quest, _target)
		DialogueChoice.QuestAction.TURN_IN:
			quests.turn_in(choice.quest, _target)


func _clear_choices() -> void:
	for child in _choices_box.get_children():
		_choices_box.remove_child(child)
		child.queue_free()


func _player_gold() -> int:
	var ps := get_node_or_null("/root/PlayerState")
	return ps.gold if ps else 0


func _close_other_menus() -> void:
	for menu in get_tree().get_nodes_in_group("menu_screen"):
		if menu != self and menu.is_open:
			menu.close()


func _set_hud_visible(shown: bool) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hud_visible"):
		hud.set_hud_visible(shown)
