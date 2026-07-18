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

var health: float


func _ready() -> void:
	health = max_health
	health_changed.emit(health, max_health)


func take_damage(amount: float, source: Node = null) -> void:
	if health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	damaged.emit(amount, health, source)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		died.emit(source)
		_award_experience()
		match death_behavior:
			DeathBehavior.FREE_PARENT:
				get_parent().queue_free()
			DeathBehavior.RELOAD_SCENE:
				get_tree().reload_current_scene.call_deferred()


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
