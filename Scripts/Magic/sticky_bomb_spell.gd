extends ProjectileSpell
class_name StickyBombSpell
## Pyromancy sticky bomb: a thrown charge that ATTACHES to whatever it hits and
## bursts in a radius. It aims and spawns exactly like any other ProjectileSpell
## -- the difference is that this script keeps hold of what it fired.
##
## With the "Remote Detonator" pyromancy node unlocked, bombs stop burning a fuse
## and pressing the slot again detonates every live bomb instead of throwing
## another, turning the spell into plant-then-trigger. This is the FIRST consumer
## of the skill tree's UPGRADE effect (SkillSystem.has_upgrade) -- until now that
## side of SkillSystem was queryable scaffolding nothing read.
##
## The upgrade is read live on every press rather than cached at _ready, so
## unlocking it mid-game applies immediately to the next throw.

## Must match the upgrade_id of the Remote Detonator node in MockSkillTrees.
const REMOTE_UPGRADE_ID := "sticky_bomb_remote"

## How many bombs may be stuck at once. Throwing past the cap detonates the
## oldest, so the player can never quietly litter the level with live charges.
@export var max_live_bombs: int = 3

var _live: Array[StickyBombProjectile] = []

## True while THIS press is a detonation rather than a throw. Set at the top of
## start_cast and consumed by begin_cooldown, because detonate_all() empties
## _live -- so _should_detonate() can no longer answer the question afterwards.
var _detonating_press: bool = false


func start_cast() -> void:
	_detonating_press = _should_detonate()
	if _detonating_press:
		detonate_all()
		return

	var bomb := _spawn_projectile() as StickyBombProjectile
	if bomb == null:
		return
	bomb.detonated.connect(_on_bomb_detonated)
	bomb.arm(self, _remote_unlocked())
	_live.append(bomb)

	while _live.size() > max_live_bombs:
		var oldest: StickyBombProjectile = _live[0]
		_live.remove_at(0)
		if is_instance_valid(oldest):
			oldest.detonate()


## Detonating is FREE -- SpellCaster charges mana before start_cast() runs, so
## without this a trigger press would be billed as if it were a fresh throw.
func try_pay_cost() -> bool:
	if _should_detonate():
		return true
	return super()


## Setting off what's already planted is never gated by the throw's cooldown --
## otherwise throwing a bomb would lock the trigger that detonates it, which is
## the whole point of the upgrade.
func is_on_cooldown() -> bool:
	if _should_detonate():
		return false
	return super()


## ...and for the same reason a detonation doesn't START one either, matching how
## try_pay_cost treats it as a trigger press rather than a cast.
func begin_cooldown() -> void:
	if _detonating_press:
		_detonating_press = false
		return
	super()


## Sets off every bomb currently stuck to the world.
func detonate_all() -> void:
	var bombs := _live.duplicate()
	_live.clear()
	for bomb in bombs:
		if is_instance_valid(bomb):
			bomb.detonate()


## True when this press should trigger what's already planted instead of throwing
## something new: only ever with the upgrade, and only with a bomb still live.
func _should_detonate() -> bool:
	_prune()
	return _remote_unlocked() and not _live.is_empty()


func _remote_unlocked() -> bool:
	var skills := get_node_or_null("/root/SkillSystem") as SkillTreeSystem
	return skills != null and skills.has_upgrade(REMOTE_UPGRADE_ID)


## Drops bombs that were freed without signalling (level torn down under them).
func _prune() -> void:
	for i in range(_live.size() - 1, -1, -1):
		if not is_instance_valid(_live[i]):
			_live.remove_at(i)


func _on_bomb_detonated(bomb: StickyBombProjectile) -> void:
	_live.erase(bomb)
