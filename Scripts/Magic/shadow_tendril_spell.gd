extends Spell
class_name ShadowTendrilSpell
## Shadow Tendril: a claw of shadow bursts from the ground beneath whatever you
## are looking at and holds it in place. Pure control -- it deals no damage.
##
## The first spell that acts on a target DIRECTLY rather than by launching
## something at it, so it is the template for that shape: aim with the shared
## Spell.aim_ray(), validate the target by DUCK TYPING (has_method("apply_root"))
## rather than by class or group, and spawn a self-contained effect that owns the
## rest. Nothing here knows what a SpiderWalker or an Npc is.
##
## Targets are rejected before anything is spent: with no valid target under the
## crosshair the press does nothing at all -- no mana, no cooldown -- exactly how
## TelekinesisGrabSpell treats a press with nothing grabbable in reach.
##
## The "Grasping Dark" shadow node upgrades it from one target to a GROUND BURST:
## the shadow erupts wherever the crosshair lands and takes everything around it.
## Like the sticky bomb's Remote Detonator the upgrade is read LIVE on every press
## (never cached at _ready), so buying it applies to the very next cast of an
## already-equipped spell.

## Must match the upgrade_id of the Grasping Dark node in MockSkillTrees.
const BURST_UPGRADE_ID := "shadow_tendril_burst"
## How far up the ancestor chain to look for a rootable body, so a target whose
## collider is a child node still counts.
const MAX_ANCESTOR_LOOKUP := 2

## Scene spawned on the target. Set on the .tscn.
@export var tendril_scene: PackedScene
## How far the crosshair ray reaches for a target.
@export var cast_range: float = 30.0
## Seconds the target is held.
@export var hold_duration: float = 3.0
## Whether a wound frees the target early (see ShadowTendril.ensnare).
@export var break_on_damage: bool = true
## How far below the target to look for the floor the claws erupt from.
@export var ground_probe: float = 3.0

@export_group("Ground Burst (Grasping Dark)")
## Radius around the aim point that the burst ensnares. Only used once the
## upgrade is unlocked; without it the spell stays strictly single-target.
@export var burst_radius: float = 4.0
## Ceiling on how many bodies one burst can catch, so a crowd can't spawn a
## tendril per body and tank the frame.
@export var max_burst_targets: int = 5
## Whether the burst can catch the caster. False by default -- the player is
## rootable (PlayerController implements apply_root), so without this a burst at
## your own feet would pin you for three seconds. Exported like the sticky bomb's
## damages_caster/pushes_caster, so self-snaring is one checkbox away.
@export var roots_caster: bool = false


func _init() -> void:
	instant = true


## No valid target = no cast. SpellCaster checks this before charging mana or
## starting the cooldown, so aiming at a wall (or bursting over empty ground) is
## free rather than punishing.
func can_cast() -> bool:
	return not _acquire_targets().is_empty()


func start_cast() -> void:
	if tendril_scene == null:
		return
	for target in _acquire_targets():
		_ensnare(target)


## Spawns a tendril on ONE target. The burst is just a loop over this: a
## ShadowTendril holds exactly one target by design, so catching five means five
## tendrils, each erupting at its own victim's feet, rather than teaching one
## claw to hold a crowd.
func _ensnare(target: Node3D) -> void:
	var tendril: Node3D = tendril_scene.instantiate()
	get_tree().current_scene.add_child(tendril)
	tendril.global_position = _ground_under(target)
	if tendril.has_method("ensnare"):
		tendril.ensnare(target, hold_duration, break_on_damage)


## Everything this press should grab. One body at the crosshair normally; with
## Grasping Dark, everything standing within burst_radius of the aim point.
## Duck-typed either way: anything implementing apply_root() is a legal target,
## so new enemy types are catchable the moment they adopt the convention.
func _acquire_targets() -> Array[Node3D]:
	var hit := aim_ray(cast_range)
	if hit.is_empty():
		return []

	if not _burst_unlocked():
		var single := _rootable_from(hit.get("collider"))
		return [single] if single else []

	# The burst centres on the impact POINT, not on whatever was hit -- so it
	# works aimed at bare ground, and aiming straight at an enemy still catches
	# them plus their neighbours. Strictly better than single target, never worse.
	return _rootable_within(hit.get("position", Vector3.ZERO), burst_radius)


func _burst_unlocked() -> bool:
	var skills := get_node_or_null("/root/SkillSystem") as SkillTreeSystem
	return skills != null and skills.has_upgrade(BURST_UPGRADE_ID)


## Every rootable body inside a sphere at `centre`. A one-shot intersect_shape
## query, the same pattern as the sticky bomb's blast and TelekinesisPush -- so
## burst_radius stays one exported number instead of also being baked into a
## CollisionShape that could drift out of sync with it.
func _rootable_within(centre: Vector3, radius: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var player := _get_player()
	if player == null:
		return found

	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), centre)
	params.collide_with_bodies = true
	params.collide_with_areas = false
	if not roots_caster:
		params.exclude = [player.get_rid()]

	var space := player.get_world_3d().direct_space_state
	# Room for several shapes per body -- results are de-duped by instance id
	# below, since a multi-collider body reports once per shape.
	var results := space.intersect_shape(params, maxi(max_burst_targets * 4, 8))
	var seen := {}
	for result in results:
		var body := _rootable_from(result.get("collider"))
		if body == null or seen.has(body.get_instance_id()):
			continue
		seen[body.get_instance_id()] = true
		found.append(body)
		if found.size() >= max_burst_targets:
			break
	return found


func _rootable_from(node: Variant) -> Node3D:
	var current := node as Node
	var steps := 0
	while current != null and steps <= MAX_ANCESTOR_LOOKUP:
		if current.has_method("apply_root") and current is Node3D:
			return current
		current = current.get_parent()
		steps += 1
	return null


## The floor under the target, so the claws erupt from the ground rather than out
## of the target's midriff. Falls back to the target's own position if the probe
## finds nothing (mid-air targets, gaps in level geometry).
func _ground_under(target: Node3D) -> Vector3:
	var space := target.get_world_3d().direct_space_state
	var from := target.global_position + Vector3.UP * 0.5
	var to := from + Vector3.DOWN * (ground_probe + 0.5)
	var exclude: Array[RID] = []
	if target is CollisionObject3D:
		exclude.append((target as CollisionObject3D).get_rid())
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, exclude))
	return hit.position if not hit.is_empty() else target.global_position
