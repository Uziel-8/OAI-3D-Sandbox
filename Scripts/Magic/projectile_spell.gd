extends Spell
class_name ProjectileSpell
## Instant spell that spawns a Projectile scene in front of the camera, aimed
## along the look direction, then hands off entirely -- this script is just the
## "press button, spawn thing" trigger. Fireball and Ice Bolt are the same
## script with a different projectile_scene assigned, so adding a third
## projectile spell means authoring a new Projectile scene, not new code.

@export var projectile_scene: PackedScene
@export var muzzle_offset: float = 0.6

@onready var muzzle_particles: GPUParticles3D = $MuzzleParticles


func _init() -> void:
	instant = true


func start_cast() -> void:
	if projectile_scene == null:
		return
	var cam := _get_camera()
	var forward := -cam.global_transform.basis.z
	var spawn_pos := cam.global_position + forward * muzzle_offset

	muzzle_particles.global_position = spawn_pos
	muzzle_particles.restart()

	var projectile: Node3D = projectile_scene.instantiate()
	cam.get_tree().current_scene.add_child(projectile)
	projectile.global_position = spawn_pos
	if projectile.has_method("launch"):
		projectile.launch(forward, _get_player().get_rid())
