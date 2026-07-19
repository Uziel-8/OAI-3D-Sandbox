class_name JournalEntry
extends Resource
## Data-only journal log entry: a titled block of read-only text. Added by code
## (quests/objectives/lore pickups) via JournalScreen.add_entry(), and seeded
## with placeholders by MockJournal until a real quest/save system exists --
## the same data-shape role SpellDefinition/InventoryItem play for their screens.

@export var title: String = "Untitled"
@export_multiline var body: String = ""
## Optional flavour/grouping tag (e.g. "Objective", "Lore"). Not shown by the UI
## yet -- here so entries can be categorised/filtered later.
@export var category: String = ""
