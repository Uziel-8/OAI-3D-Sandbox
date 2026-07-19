class_name MockJournal
extends RefCounted
## Placeholder journal entries so the journal screen has something to show.
## Replace with real quest/lore/save data once that exists -- same role
## MockItemDatabase / MockSpellbook play for their screens.

static func _make(title: String, body: String, category := "") -> JournalEntry:
	var e := JournalEntry.new()
	e.title = title
	e.body = body
	e.category = category
	return e

static func starting_entries() -> Array[JournalEntry]:
	return [
		_make("Remove the Foreman",
			"The dockmaster wants Karrick, the yard foreman, gone from the port — quietly or otherwise, they didn't much care which.\n\nHow it's done is left to me. He might be bought off, frightened off, talked into leaving, or simply removed. The men who answer to him won't take kindly to the last option out in the open.",
			"Objective"),
		_make("Arrival at the Docks",
			"Salt, tar, and rot. The harbour district runs on cheap labour and cheaper loyalty, its warehouses stacked to the rafters with crates nobody asks about.\n\nBarrels everywhere — some full, some not. Worth remembering that a heavy thing dropped from a height asks no questions.",
			"Lore"),
		_make("On the Art of Telekinesis",
			"The Force discipline is blunt but honest: what you can see, you can shove. Reach out to hold a thing at arm's length, then release to send it flying. A firm push clears a path — or a person.\n\nThe scholars insist there is subtlety to be learned. For now, there is leverage.",
			"Lore"),
	]
