extends Node
class_name DamageReceiver
## Health-holding component. Add the DamageReceiver scene as a direct child of
## any body that should be damageable (player, enemies, props) and set
## max_health/death_behavior per instance. Anything that deals damage finds
## this component on the body it hit via DamageReceiver.find_in() -- the body
## itself never needs damage-specific code.

signal damaged(amount: float, remaining: float, source: Node)
## Fires on any health change (damage or heal) and once on _ready with the
## starting value, so UI can bind to it as the single source of truth.
signal health_changed(current: float, maximum: float)
signal died(source: Node)

enum DeathBehavior {
	## Only emit died -- something else owns what happens next.
	NONE,
	## queue_free() the parent body (enemies, destructible props).
	FREE_PARENT,
	## Reload the current scene (prototype player death).
	RELOAD_SCENE,
}

@export var max_health: float = 100.0
@export var death_behavior: DeathBehavior = DeathBehavior.FREE_PARENT
## Experience awarded to the player when this body dies. 0 = grants none
## (right for the player and neutral props); enemies set this above 0.
@export var xp_reward: float = 0.0
## Passive health regenerated per second while alive (0 = none). The player's
## is driven by CON via PlayerProgression; enemies/props can set it per instance.
@export var health_regen: float = 0.0

@export var drop_table : DropTable
@export var drop_scene : PackedScene

var health: float


func _ready() -> void:
	health = max_health
	health_changed.emit(health, max_health)


func _process(delta: float) -> void:
	if health_regen > 0.0 and health > 0.0 and health < max_health:
		heal(health_regen * delta)


## Changes max_health at runtime (e.g. CON increased), keeping current health
## (clamped) rather than refilling, and notifying bound UI.
func set_max_health(new_max: float) -> void:
	max_health = new_max
	health = minf(health, max_health)
	health_changed.emit(health, max_health)


func take_damage(amount: float, source: Node = null) -> void:
	if health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	damaged.emit(amount, health, source)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		roll_loot()
		died.emit(source)
		_award_experience()
		match death_behavior:
			DeathBehavior.FREE_PARENT:
				get_parent().queue_free()
			DeathBehavior.RELOAD_SCENE:
				get_tree().reload_current_scene.call_deferred()

func roll_loot():
	if drop_table == null or drop_scene == null:
		return
	print("Rolling Loot...")
	var dropped_item = drop_scene.instantiate()
	var parent : CharacterBody3D = get_parent()
	var spawn_pos = parent.global_position
	dropped_item.position = parent.to_local(spawn_pos)
	parent.add_child(dropped_item)

	var drops = drop_table.drops
	var loot_roll := randf()
	var cumulative := 0.0
	for item in drops:
		cumulative += drops[item]
		if loot_roll < cumulative:
			print(item)
			return item
	return ""

#Step 1 — Guard the two exports
#take_damage calls roll_loot() on every death, so the player's receiver and the barrel's both land in here with drop_table and drop_scene unset. Bail out first:
#
#
#if drop_table == null or drop_scene == null:
	#return ""
#Without this, killing the player or a barrel throws "Cannot call method 'instantiate' on a null value" before the death behaviour ever runs.
#
#Step 2 — Move the roll above the spawn
#Right now lines 83-87 spawn the sphere, and then lines 89-96 roll the table. So the roll result is thrown away and an item appears regardless of the outcome. Cut the roll block up to the top of the function and keep its result in a variable:
#
#
#var dropped_id := ""
#var loot_roll := randf()
#var cumulative := 0.0
#for item in drop_table.drops:
	#cumulative += drop_table.drops[item]
	#if loot_roll < cumulative:
		#dropped_id = item
		#break
#if dropped_id == "":
	#return ""          # table rolled nothing -- spawn nothing
#(Your spider's weights sum to exactly 1.0 so it always hits, but a table that sums to 0.6 should mean a 40% chance of no drop, and that only works if the spawn comes after the roll.)
#
#Step 3 — Parent the drop to the LEVEL, not the dying body
#This is the actual reason you see nothing. get_parent() on a DamageReceiver is the body the component sits on — the spider. So the drop becomes a child of the spider, and take_damage then runs get_parent().queue_free(), which frees the spider and everything under it, including the drop you just added.
#
#You need the body's parent, which is the level:
#
#
#var body := get_parent() as Node3D
#var level := body.get_parent()
#if level == null:
	#return dropped_id
#Note in enemy_spawner.gd:86-87 — the lines you borrowed — parent is already a sibling of the spawner, which is why it works there and not here.
#
#Step 4 — Convert the position into the level's space
#With parent being the body, parent.to_local(parent.global_position) is always Vector3.ZERO — it's converting a point into the space of the thing it came from. Now that the new parent is the level, the conversion means something:
#
#
#var dropped_item := drop_scene.instantiate() as Node3D
#dropped_item.position = level.to_local(body.global_position)
#level.add_child(dropped_item)
#return dropped_id
#Keep position before add_child — that's the physics-sync rule in CLAUDE.md. A PhysicsBody3D moved after it enters the tree doesn't reach the physics server until the frame ends, so for one frame its collider sits at the world origin.
#
#Also drop the : CharacterBody3D type hint you have on line 84. It's fine for the spider, but the moment you give a drop table to a barrel or a spawner (StaticBody3D) that typed assignment hard-errors.
#
#Step 5 — Delete the dead commented block
#Lines 65-72 in take_damage are the old copy of this code and have the same corpse-parenting bug. Worth removing so you don't come back and re-enable it later.
#
#Two things that are next, not now, so you know what to expect when the sphere starts appearing:
#
#It won't be pickable yet. dropped_item.tscn's root has an Interactable child, but the root node isn't in group "interactable", so PlayerInteractor's raycast skips it entirely — see the note at the top of interactable.gd. Add groups=["interactable"] to the root. (gold_stack.tscn and item_pickup.tscn have the same gap; bedroll.tscn is the one that does it right.)
#Your table keys aren't item ids. "Coin" / "Spider Leg" / "Mana Crystal" / "Spider Eye" have no match in MockItemDatabase, whose ids are gold_pouch, wolf_pelt, mana_draught and so on. When you get to the inventory link, the cheap path is to return the id from roll_loot(), spawn Objects/item_pickup.tscn instead of dropped_item.tscn, and set item_id on it before add_child — item_pickup.gd already resolves the id, names the prompt, tints the mesh and calls PlayerInventory.add_item(), so that's the whole "link it to the inventory" step done for you.
#
#


## Restores health up to max_health (no effect once dead). For potions/regen.
func heal(amount: float) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)


## Grants this body's xp_reward to the player's progression, if any. Looked up
## by autoload path so DamageReceiver stays decoupled -- no hard dependency on
## the progression system existing.
func _award_experience() -> void:
	if xp_reward <= 0.0:
		return
	var progression := get_tree().root.get_node_or_null("PlayerProgression")
	if progression:
		progression.add_experience(xp_reward)


## Returns the DamageReceiver child of the given body, or null if it has none
## (i.e. the body is not damageable).
static func find_in(body: Node) -> DamageReceiver:
	if body == null:
		return null
	for child in body.get_children():
		if child is DamageReceiver:
			return child
	return null
