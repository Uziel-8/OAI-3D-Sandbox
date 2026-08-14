class_name MarketEventTrigger
extends Node
## Base for a drop-in "this happening moves the market" component. Place one
## anywhere in a level, point it at a MarketEvent, and whatever the subclass watches
## becomes a price move.
##
## Deliberately the same shape as LevelObjective: subclasses hook their condition in
## _setup() and call fire(). Adding a NEW way to move the market is a new subclass
## and nothing else changes -- no edits here, in MarketSystem, or in the UI.
##
## `player_caused` defaults TRUE because a trigger placed in a level is almost
## always something the player did. That flag is what feeds MarketSystem's insider
## check, so a scripted world event the player merely witnesses should clear it.

## Emitted after the event has been applied (or booked, with delay_days).
signal fired(event: MarketEvent)

## What this does to the board. Author inline on the node or point at a .tres.
@export var event: MarketEvent
## False for world events the player merely witnessed -- no insider suspicion.
@export var player_caused: bool = true
## Fires at most once. Off makes it repeatable (a market that can be flooded twice).
@export var one_shot: bool = true
## News travels: 0 lands the move immediately, higher books it that many days out
## through WorldClock. A delay means the player must already be positioned, which
## is exactly what the guild is watching for.
@export var delay_days: int = 0

var has_fired: bool = false


func _ready() -> void:
	add_to_group("market_event_trigger")
	# Deferred, like LevelObjective: the things _setup() goes looking for need to
	# exist, and on an NPC the profile hasn't been applied yet.
	_register.call_deferred()


func _register() -> void:
	if event == null:
		push_warning("MarketEventTrigger '%s' has no event -- it can never do anything." % name)
		return
	_setup()


## Subclasses override: connect whatever signal decides this fires. Runs deferred,
## so firing immediately from here is safe.
func _setup() -> void:
	pass


## Applies (or books) the event. Idempotent while one_shot is set. Public so a quest
## script or a cutscene can pull the same trigger.
func fire() -> void:
	if event == null or (one_shot and has_fired):
		return
	has_fired = true
	var market := get_node_or_null("/root/Market") as MarketSystem
	if market == null:
		push_warning("MarketEventTrigger '%s': no Market autoload." % name)
		return

	# The HUD toasts off MarketSystem.event_fired, so nothing is announced from here
	# -- one announcer means ambient news and player sabotage read identically, and
	# a delayed event announces when it LANDS rather than when it was booked.
	if delay_days > 0:
		market.schedule_event(event, delay_days)
	else:
		market.apply_event(event, player_caused)
	fired.emit(event)


## The body this trigger watches: an explicit target if the subclass has one, else
## the node it's parented to. Lets a trigger be either dropped under the thing or
## pointed at it from elsewhere, matching LevelObjective's convention.
func _resolve_target(explicit: Node) -> Node:
	if explicit and is_instance_valid(explicit):
		return explicit
	return get_parent()
