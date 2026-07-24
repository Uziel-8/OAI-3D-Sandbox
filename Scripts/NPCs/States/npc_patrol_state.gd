extends NpcState
class_name NpcPatrolState
## Walks the NPC's `patrol_points` in order, pausing patrol_wait seconds at each,
## looping. A hostile patroller breaks off to Chase when the player nears. With no
## waypoints set it just idles in place (and does nothing harmful).

var _index: int = 0
var _wait: float = 0.0


func enter(_msg: Dictionary = {}) -> void:
	_wait = 0.0


func physics_update(delta: float) -> void:
	if npc.tick_stagger(delta):
		return
	npc.apply_gravity(delta)

	if npc.should_start_chase():
		transition_to("Chase")
		return

	if npc.patrol_points.is_empty():
		npc.halt(delta)
		npc.move_and_slide()
		return

	var target: Node3D = npc.patrol_points[_index]
	if target == null or not is_instance_valid(target):
		_index = (_index + 1) % npc.patrol_points.size()
		npc.move_and_slide()
		return

	var dist := npc.steer_towards(target.global_position, delta, Npc.ARRIVE_DISTANCE)
	npc.move_and_slide()

	if dist <= Npc.ARRIVE_DISTANCE:
		_wait += delta
		if _wait >= npc.patrol_wait:
			_wait = 0.0
			_index = (_index + 1) % npc.patrol_points.size()
