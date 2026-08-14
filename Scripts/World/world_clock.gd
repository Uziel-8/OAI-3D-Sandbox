class_name WorldClockSystem
extends Node
## The game's calendar. Registered as the `WorldClock` autoload (the class/singleton
## names differ for the usual reason -- Godot rejects a global class whose name
## matches a singleton, exactly like ProgressionSystem/PlayerProgression).
##
## Time NEVER passes on its own. There is no wall-clock tick, no per-frame drift:
## the day advances only when something explicitly calls advance_days(), which in
## practice means the player rested (RestPoint) or a quest/event said so. That is
## deliberate -- a player mid-speculation should always know why the date moved.
##
## It also owns a SCHEDULE: things due on a future day, fired in date order as the
## clock walks forward. Scheduled entries are TAG + PAYLOAD rather than Callables,
## because the autoload outlives every scene: a Callable bound to a node would go
## stale across the death-reload or a level change, while a tag any listener can
## match survives both. MarketSystem is the first consumer (ambient events are
## scheduled days ahead so a rumour has time to reach the player).
##
## Nothing is written to disk; there is still no save system.

## Fired once per day crossed, in order, DURING advance_days -- so a three-day rest
## emits three times and every listener sees each day individually.
signal day_passed(day: int)
## Fired once at the end of an advance, after all the per-day work is done. Use this
## for UI that only wants the final state.
signal day_changed(day: int, days_elapsed: int)
## A scheduled entry came due. Listeners match on `tag` and read `payload`.
signal scheduled_fired(tag: StringName, payload: Dictionary)

## Day 1 is the start of play. Days are whole numbers; there is no time of day.
@export var starting_day: int = 1
## Hard stop on how many days one call may walk, so a bad caller can't hang the
## game processing a million day_passed emissions.
@export var max_advance: int = 30

var day: int

## Pending entries: {"id": int, "day": int, "tag": StringName, "payload": Dictionary}.
## Kept sorted by day so firing is just walking the front of the list.
var _schedule: Array[Dictionary] = []
var _next_id: int = 1
## Guards against a listener calling advance_days() from inside day_passed, which
## would interleave two walks and fire scheduled entries out of order.
var _advancing: bool = false


func _ready() -> void:
	day = starting_day


## Walks the calendar forward. The ONE entry point -- resting, a quest that costs a
## week, a debug key all come through here. Returns the number of days actually
## advanced (0 if the call was a no-op or came from inside a day_passed handler).
func advance_days(days: int = 1) -> int:
	if days <= 0 or _advancing:
		return 0
	var count: int = mini(days, max_advance)
	_advancing = true
	for _i in count:
		day += 1
		# Scheduled entries fire BEFORE day_passed, so a listener reacting to the new
		# day already sees the world that day's events created.
		_fire_due()
		day_passed.emit(day)
	_advancing = false
	day_changed.emit(day, count)
	return count


## Books `tag` for `days_from_now` days ahead (minimum tomorrow -- scheduling
## something for today would never fire, since the queue is only drained on a
## crossing). Returns an id that cancel() takes.
func schedule(days_from_now: int, tag: StringName, payload: Dictionary = {}) -> int:
	var due: int = day + maxi(days_from_now, 1)
	var id: int = _next_id
	_next_id += 1
	_schedule.append({"id": id, "day": due, "tag": tag, "payload": payload})
	_schedule.sort_custom(func(a, b): return a["day"] < b["day"])
	return id


## Drops a pending entry. Returns true if one was actually removed.
func cancel(id: int) -> bool:
	for i in _schedule.size():
		if _schedule[i]["id"] == id:
			_schedule.remove_at(i)
			return true
	return false


## Pending entries, soonest first. Copies, so a caller can't reorder the queue.
func pending(tag: StringName = &"") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _schedule:
		if String(tag).is_empty() or entry["tag"] == tag:
			out.append(entry.duplicate(true))
	return out


## How many days until an entry is due (negative if overdue, which shouldn't happen).
func days_until(entry: Dictionary) -> int:
	return int(entry.get("day", day)) - day


## Everything due on or before today, emitted in date order and removed.
func _fire_due() -> void:
	while not _schedule.is_empty() and _schedule[0]["day"] <= day:
		var entry: Dictionary = _schedule.pop_front()
		scheduled_fired.emit(entry["tag"], entry["payload"])


## "Day 4". Shown on the HUD and wherever a date is quoted in prose.
func date_text() -> String:
	return "Day %d" % day


## Wipes the calendar back to the start. No UI yet -- here so a future new-game has
## one call, matching ReputationSystem.reset() / SkillSystem.reset().
func reset() -> void:
	_schedule.clear()
	day = starting_day
	day_changed.emit(day, 0)
