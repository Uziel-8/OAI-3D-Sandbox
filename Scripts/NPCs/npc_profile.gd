class_name NpcProfile
extends Resource
## Shared, IMMUTABLE archetype data for an NPC -- the "iterate the majority in one
## place" half of the NPC system. Author a `.tres` per archetype (Foreman, Guard,
## Patroller...) and drop it on an NPC scene's `profile` slot; many NPCs can share
## one profile, so editing the archetype updates every instance.
##
## Treat this as read-only at runtime. The NPC copies these into LIVE state on its
## node in _ready (current health on the DamageReceiver, current `disposition` on
## the Npc) -- never mutate the profile, or you'd change it for every NPC sharing
## it (and, in-editor, write it back to disk).
##
## DATA lives here; BEHAVIOUR does not. Movement is an enum that picks which FSM
## state the NPC starts in -- the actual logic is in Scripts/NPCs/States/.

enum Movement {
	STATIC,   ## holds position; a hostile one still breaks off to chase when the player nears
	PATROL,   ## walks its scene-placed waypoints; same chase break-off
	CHASE,    ## pursues the player from the start (a plain aggressor)
}

@export_group("Identity")
@export var display_name: String = "Stranger"
## Free-form faction tag; the NPC also joins group "faction_<faction>" for future
## faction-vs-faction queries. Hostility today is driven by `starting_disposition`.
@export var faction: StringName = &"neutral"
## Label only for now (fighter/mage/...). A stat block / ability set can hang off
## this later without touching the NPC scene.
@export var char_class: StringName = &"commoner"

@export_group("Disposition")
## < 0 hostile (chases the player), 0 neutral, > 0 friendly. Seeded onto the NPC's
## live `disposition`; the profile itself is never changed at runtime.
@export var starting_disposition: int = 0

@export_group("Vitals")
@export var max_health: float = 30.0
@export var health_regen: float = 0.0
## XP granted to the player when this NPC dies (0 = none).
@export var xp_reward: float = 0.0

@export_group("Movement")
@export var movement: Movement = Movement.STATIC
@export var move_speed: float = 3.0
@export var turn_speed: float = 8.0
## How close the player must get before a hostile STATIC/PATROL NPC starts chasing.
@export var chase_range: float = 8.0
## How far the player must get before a chaser gives up (returns to STATIC/PATROL).
## A pure CHASE archetype ignores this and pursues relentlessly.
@export var give_up_range: float = 14.0
## A chaser stops advancing within this distance so it doesn't jitter into the player.
@export var stop_distance: float = 1.6
## Seconds a PATROL NPC pauses at each waypoint.
@export var patrol_wait: float = 1.5

@export_group("Interaction")
## Defaults for the NPC's Interactable. Any of these left blank/empty keeps whatever
## the NPC scene authored, so a specific NPC can override the archetype's lines.
@export var interact_prompt: String = ""
@export var speaker_name: String = ""
@export var dialogue_lines: Array[String] = []


func is_hostile() -> bool:
	return starting_disposition < 0
