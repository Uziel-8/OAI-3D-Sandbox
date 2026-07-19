class_name MockJournal
extends RefCounted
## Generic FALLBACK journal shown only when a level provides no LevelObjectives
## node of its own. Real per-level content lives on each level's LevelObjectives
## node (edited in the inspector), which replaces this via JournalScreen.set_entries().

static func _make(title: String, body: String, category := "") -> JournalEntry:
	var e := JournalEntry.new()
	e.title = title
	e.body = body
	e.category = category
	return e

static func starting_entries() -> Array[JournalEntry]:
	return [
		_make("Journal",
			"Your current objective and the things you learn along the way are recorded here. Entries change from place to place.",
			""),
	]
