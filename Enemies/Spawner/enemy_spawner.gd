extends StaticBody3D
class_name EnemySpawner
## Drop-in, destructible enemy spawner. Instance the scene anywhere in a level:
## with zero config it periodically spawns SpiderWalkers near itself, keeping up
## to `max_alive` alive at once and refilling a slot whenever one dies. It's
## itself killable via a DamageReceiver child (destroying it just stops future
## spawns -- already-spawned enemies live on, since they're parented as siblings
## rather than children).
##
## Built to grow: tune the exports, swap `enemy_scene` for any enemy, or override
## `_configure_spawned()` to set up each enemy as it appears (aggro, faction,
## difficulty scaling, buffs...).

## The enemy scene to instance. Defaults to the SpiderWalker in the .tscn.
@export var enemy_scene: PackedScene
## Seconds between spawn attempts.
@export var spawn_interval: float = 5.0
## Delay before the first spawn attempt after becoming active.
@export var first_spawn_delay: float = 1.0
## Max enemies from THIS spawner alive at once (0 = unlimited). A slot frees when
## a spawned enemy dies; the next tick refills it.
@export var max_alive: int = 3
## Total enemies this spawner will ever produce (0 = unlimited).
@export var max_total: int = 0
## Enemies appear at a random point within this horizontal radius of the spawner
## (0 = exactly at the spawner's position).
@export var spawn_radius: float = 2.0
## If > 0, the spawner only ticks while a node in group "player" is within this
## distance -- lets far-off spawners stay dormant until approached.
@export var activation_radius: float = 0.0
## Begin spawning automatically on ready. If false, call start() to begin.
@export var auto_start: bool = true

var _alive: Array[Node] = []
var _total_spawned: int = 0
var _timer: float = 0.0
var _active: bool = false


func _ready() -> void:
	add_to_group("enemy_spawner")
	if enemy_scene == null:
		push_warning("EnemySpawner on %s has no enemy_scene set." % get_path())
	if auto_start:
		start()


## Begins (or resumes) spawning, resetting the delay to first_spawn_delay.
func start() -> void:
	_active = true
	_timer = first_spawn_delay


## Halts spawning. Existing enemies are unaffected.
func stop() -> void:
	_active = false


func _physics_process(delta: float) -> void:
	if not _active or enemy_scene == null:
		return
	if max_total > 0 and _total_spawned >= max_total:
		_active = false
		return
	if activation_radius > 0.0 and not _player_in_range():
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval
		_try_spawn()


func _try_spawn() -> void:
	_prune_dead()
	if max_alive > 0 and _alive.size() >= max_alive:
		return

	var enemy := enemy_scene.instantiate()
	var parent := get_parent()
	var spawn_pos := _spawn_position()
	# Set the position BEFORE adding to the tree: add_child runs the enemy's
	# _ready synchronously, and self-contained enemies (e.g. SpiderWalker) read
	# their spawn position there to anchor wander/AI. Convert to the parent's
	# local space so it lands correctly regardless of the parent's transform.
	if enemy is Node3D and parent is Node3D:
		enemy.position = parent.to_local(spawn_pos)
	parent.add_child(enemy)

	_alive.append(enemy)
	_total_spawned += 1
	_configure_spawned(enemy)


## Override / extend to configure each freshly spawned enemy. No-op by default.
func _configure_spawned(_enemy: Node) -> void:
	pass


func _spawn_position() -> Vector3:
	if spawn_radius <= 0.0:
		return global_position
	# Uniform within the disc (sqrt keeps it from clustering at the centre).
	var angle := randf() * TAU
	var dist := sqrt(randf()) * spawn_radius
	return global_position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


func _prune_dead() -> void:
	# filter() returns an untyped Array, so assign() it back rather than a plain
	# `=`, which would fail to convert Array -> Array[Node].
	_alive.assign(_alive.filter(func(e: Node) -> bool: return is_instance_valid(e)))


func _player_in_range() -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return false
	return global_position.distance_to(player.global_position) <= activation_radius
