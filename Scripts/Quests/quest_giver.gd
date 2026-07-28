class_name QuestGiver
extends Node
## Drop-in component that makes an NPC offer sidequests. Add it as a child of the
## NPC body (the same way DispositionReaction is added under a guard) and fill
## `quests`. No code, no subclassing.
##
## It works by PUSHING a dialogue override onto the NPC's Interactable, swapping
## which of the quest's four line sets is shown -- offer / in-progress / ready /
## completed -- and generating the Accept / Decline / Turn-in choice buttons. It
## refreshes on every QuestSystem signal, so what the NPC says is never stale.
## With nothing quest-related to say it clears the override, and the NPC falls
## back to its normal profile chatter.
##
## When several quests apply at once the most urgent wins: something to hand in
## beats something in progress beats something new to offer.

## Quests this NPC can give. Order is the tie-break when several are offerable.
@export var quests: Array[Quest] = []

## When true, a quest of this giver's that is READY auto-turns-in if the giver
## dies -- so doing an NPC's errand and then killing them still pays out, rather
## than stranding the quest with nobody to report to. Set false to let death
## strand it.
@export var complete_on_death: bool = true

var _interactable: Interactable
var _quests: QuestTracker


func _ready() -> void:
	_quests = get_node_or_null("/root/QuestSystem")
	if _quests == null:
		push_warning("QuestGiver on '%s': QuestSystem autoload missing." % get_parent().name)
		return
	_interactable = Interactable.find_in(get_parent())
	if _interactable == null:
		push_warning("QuestGiver on '%s': no Interactable on the body, so its quests can't be offered." % get_parent().name)

	for quest in quests:
		_quests.register_quest(quest)

	_quests.quest_accepted.connect(_on_quest_changed)
	_quests.quest_ready.connect(_on_quest_changed)
	_quests.quest_completed.connect(_on_quest_changed)
	_quests.quest_progress_changed.connect(_on_quest_changed)

	if complete_on_death:
		var receiver := DamageReceiver.find_in(get_parent())
		if receiver:
			receiver.died.connect(_on_giver_died)

	# Deferred so the NPC's _apply_profile (which seeds the Interactable's own
	# lines) has already run -- otherwise clearing the override could reveal
	# nothing at all.
	_refresh.call_deferred()


func _on_quest_changed(_quest: Quest) -> void:
	_refresh()


## Rebuilds the dialogue override from whichever quest is most urgent.
func _refresh() -> void:
	if _interactable == null or _quests == null:
		return
	var quest := _current_quest()
	if quest == null:
		_interactable.clear_dialogue_override()
		return

	var lines: Array[String] = []
	var choices: Array[DialogueChoice] = []

	if _quests.can_turn_in(quest):
		lines = quest.ready_lines.duplicate()
		choices.append(_make_choice(quest, quest.turn_in_text, quest.turn_in_response,
			DialogueChoice.QuestAction.TURN_IN))
	elif _quests.is_active(quest.id):
		lines = quest.in_progress_lines.duplicate()
	elif _quests.is_completed(quest.id):
		lines = quest.completed_lines.duplicate()
	else:
		lines = quest.offer_lines.duplicate()
		choices.append(_make_choice(quest, quest.accept_text, quest.accept_response,
			DialogueChoice.QuestAction.ACCEPT))
		if quest.decline_text != "":
			# No action and no response: picking it just closes the panel.
			choices.append(_make_choice(quest, quest.decline_text, "",
				DialogueChoice.QuestAction.NONE))

	if lines.is_empty() and choices.is_empty():
		# e.g. a completed quest with no completed_lines -- let the NPC go back to
		# whatever it normally says rather than falling silent.
		_interactable.clear_dialogue_override()
		return
	_interactable.set_dialogue_override(lines, choices)


## The quest this NPC should talk about: ready to hand in > in progress >
## completed-with-something-to-say > offerable.
func _current_quest() -> Quest:
	var active: Quest = null
	var offerable: Quest = null
	var completed: Quest = null
	for quest in quests:
		if quest == null or String(quest.id).is_empty():
			continue
		if _quests.can_turn_in(quest):
			return quest  # most urgent -- stop here
		if active == null and _quests.is_active(quest.id):
			active = quest
		elif offerable == null and _quests.can_offer(quest):
			offerable = quest
		elif completed == null and _quests.is_completed(quest.id) \
				and not quest.completed_lines.is_empty():
			completed = quest
	if active:
		return active
	if offerable:
		return offerable
	return completed


## Pays out any of this giver's quests that were finished but never reported, so
## killing the NPC afterwards doesn't void the work. See `complete_on_death`.
func _on_giver_died(_source: Node) -> void:
	if _quests == null:
		return
	for quest in quests:
		if quest and _quests.can_turn_in(quest):
			_quests.turn_in(quest, get_parent())


func _make_choice(quest: Quest, text: String, response: String,
		action: DialogueChoice.QuestAction) -> DialogueChoice:
	var choice := DialogueChoice.new()
	choice.text = text
	choice.response = response
	choice.quest = quest
	choice.quest_action = action
	return choice
