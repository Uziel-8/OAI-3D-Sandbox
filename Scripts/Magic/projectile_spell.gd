extends Spell
class_name ProjectileSpell
## Instant spell that spawns a Projectile scene from the player's body, aimed
## at whatever the camera crosshair is pointing at, then hands off entirely --
## this script is just the "press button, spawn thing" trigger. Fireball and
## Ice Bolt are the same script with a different projectile_scene assigned, so
## adding a third projectile spell means authoring a new Projectile scene, not
## new code.

@export var projectile_scene: PackedScene
## Height above the player's origin the projectile leaves from (chest/hand level).
@export var cast_height: float = 1.4
## How far in front of the player's body the projectile spawns, so it doesn't
## immediately collide with the caster.
@export var muzzle_offset: float = 0.7
## How far out the crosshair aim ray is cast when it hits nothing.
@export var aim_range: float = 100.0

@onready var muzzle_particles: GPUParticles3D = $MuzzleParticles


func _init() -> void:
	instant = true


func start_cast() -> void:
	if projectile_scene == null:
		return
	var cam := _get_camera()
	var player := _get_player()

	# Aim: raycast from the camera through the crosshair so the projectile
	# lands where the player is actually pointing, even though it launches
	# from the body and not the lens.
	var aim_from := cam.global_position
	var aim_to := aim_from - cam.global_transform.basis.z * aim_range
	var aim_query := PhysicsRayQueryParameters3D.create(aim_from, aim_to, 0xFFFFFFFF, [player.get_rid()])
	var aim_hit := cam.get_world_3d().direct_space_state.intersect_ray(aim_query)
	var aim_point: Vector3 = aim_hit.position if not aim_hit.is_empty() else aim_to

	var spawn_pos := player.global_position + Vector3.UP * cast_height
	var direction := (aim_point - spawn_pos).normalized()
	spawn_pos += direction * muzzle_offset

	muzzle_particles.global_position = spawn_pos
	muzzle_particles.restart()

	var projectile: Node3D = projectile_scene.instantiate()
	cam.get_tree().current_scene.add_child(projectile)
	projectile.global_position = spawn_pos
	if projectile.has_method("launch"):
		projectile.launch(direction, player.get_rid())

	# Magic damage scales with INT/WIL: each projectile instance's dealer is
	# fresh, so scaling it here never compounds across casts.
	var dealer := projectile.get_node_or_null("DamageDealer") as DamageDealer
	var prog := get_node_or_null("/root/PlayerProgression") as ProgressionSystem
	if dealer and prog:
		dealer.damage *= prog.magic_damage_multiplier()
