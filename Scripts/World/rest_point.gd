class_name RestPoint
extends Node
## Drop-in "sleep here" component -- the only player-facing way the calendar moves.
## Add as a child of any body with an Interactable (a bedroll, a bunk, an inn bed)
## and put that body in group "interactable" as usual.
##
## It doesn't rest on the raw `interacted` signal, because bedding down for three
## days on a misclick is miserable. Instead it PUSHES a dialogue override onto its
## sibling Interactable offering one choice per entry in `rest_options`, and listens
## for DialogueScreen.choice_selected to spot its own. That's the documented use of
## set_dialogue_override ("state-dependent barks want the same hook") and it means
## the confirm UI is the dialogue screen you already have, not a new one.
##
## NB a body can only carry ONE override pusher: putting a RestPoint and a
## QuestGiver on the same node would have them fighting over the Interactable.

## Emitted after the clock has actually moved.
signal rested(days: int)

## Shown above the options.
@export_multiline var rest_prompt: String = "A bedroll, and nobody minding it."
## One choice offered per entry, in order. Each is a number of days.
@export var rest_days_options: Array[int] = [1, 3]
## Label on the back-out option. Blank = no such button (Esc still closes).
@export var decline_text: String = "Stay awake."
## Shown as the reply after choosing, before the panel closes.
@export var rest_response: String = "You sleep, and the docks go on without you."
## Announces the new date on the HUD after resting.
@export var toast_on_rest: bool = true

## Our generated choices, keyed by the choice resource -> days it rests. Identity
## matching is what keeps us from reacting to some other NPC's dialogue choice.
var _own_choices: Dictionary = {}
var _interactable: Interactable = null


func _ready() -> void:
	add_to_group("rest_point")
	# Deferred: the Interactable and the dialogue screen both need to exist, and on
	# an NPC the profile hasn't seeded the Interactable's own lines yet.
	_setup.call_deferred()


func _setup() -> void:
	_interactable = Interactable.find_in(get_parent())
	if _interactable == null:
		push_warning("RestPoint on '%s' has no Interactable sibling -- it can never be used."
			% (get_parent().name if get_parent() else name))
		return

	var dialogue := get_tree().get_first_node_in_group("dialogue_screen")
	if dialogue and dialogue.has_signal("choice_selected") \
			and not dialogue.choice_selected.is_connected(_on_choice_selected):
		dialogue.choice_selected.connect(_on_choice_selected)

	_push_dialogue()


## Builds the rest menu and hands it to the Interactable. Rebuilt rather than
## cached so changing rest_days_options at runtime takes effect.
func _push_dialogue() -> void:
	if _interactable == null:
		return
	_own_choices.clear()
	var choices: Array[DialogueChoice] = []
	for days in rest_days_options:
		if days <= 0:
			continue
		var choice := DialogueChoice.new()
		choice.text = "Rest %d day%s." % [days, "" if days == 1 else "s"]
		choice.response = rest_response
		choices.append(choice)
		_own_choices[choice] = days
	if not decline_text.is_empty():
		var leave := DialogueChoice.new()
		leave.text = decline_text
		choices.append(leave)  # not in _own_choices, so selecting it rests 0 days

	var lines: Array[String] = []
	if not rest_prompt.is_empty():
		lines.append(rest_prompt)
	_interactable.set_dialogue_override(lines, choices)


func _on_choice_selected(choice: DialogueChoice, _target: Node) -> void:
	if not _own_choices.has(choice):
		return
	rest(_own_choices[choice])


## Advances the calendar. Public so a scripted "you are knocked out for a week"
## can reuse the same path.
func rest(days: int) -> void:
	var clock := _clock()
	if clock == null:
		push_warning("RestPoint: no WorldClock autoload -- resting does nothing.")
		return
	var moved := clock.advance_days(days)
	if moved <= 0:
		return
	if toast_on_rest:
		var hud := get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("show_toast"):
			hud.show_toast("You rest.", "%d day%s pass  •  %s" % [
				moved, "" if moved == 1 else "s", clock.date_text()])
	rested.emit(moved)


func _clock() -> WorldClockSystem:
	return get_node_or_null("/root/WorldClock") as WorldClockSystem


## Mirrors Interactable.find_in / ShopKeeper.find_in -- a direct-children scan.
static func find_in(body: Node) -> RestPoint:
	if body == null:
		return null
	for child in body.get_children():
		if child is RestPoint:
			return child
	return null
