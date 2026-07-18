extends Node
class_name DamageDealer
## Damage-applying component. Add the DamageDealer scene as a child of anything
## that should hurt DamageReceivers (projectiles, enemies with touch damage)
## and set damage/cooldown per instance. The owner decides *when* contact
## happens (impact callback, slide collision, hitbox overlap...) and calls
## try_deal(body) -- this component decides whether the hit lands and how hard.

@export var damage: float = 10.0
## Minimum seconds between successive hits on the same receiver. 0 means every
## try_deal() call lands (right for one-shot projectiles); continuous-contact
## dealers like enemy touch damage should set this so the target isn't hit
## every physics frame.
@export var cooldown: float = 0.0

# receiver instance id -> time of last successful hit, in seconds.
var _last_hit_times: Dictionary = {}


## Damages the DamageReceiver on the given body, if it has one and isn't still
## inside this dealer's cooldown window. Returns true if the hit landed.
func try_deal(body: Node) -> bool:
	var receiver := DamageReceiver.find_in(body)
	if receiver == null:
		return false

	if cooldown > 0.0:
		var now := Time.get_ticks_msec() / 1000.0
		var id := receiver.get_instance_id()
		if _last_hit_times.has(id) and now - _last_hit_times[id] < cooldown:
			return false
		_last_hit_times[id] = now

	receiver.take_damage(damage, get_parent())
	return true
