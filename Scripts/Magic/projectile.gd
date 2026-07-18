extends Area3D
class_name Projectile
## Generic flying spell bolt: travels forward at a constant speed and, on first
## contact with anything (world geometry or an actor), applies an impulse via
## the project's duck-typed apply_impulse() convention (see TelekinesisPushSpell),
## plays an impact burst, and frees itself. Fireball and Ice Bolt are this same
## script with different meshes/particles/speed/impact_force set per scene --
## the flight/impact behavior itself never needs to change per spell.

@export var speed: float = 22.0
@export var impact_force: float = 12.0
@export var max_lifetime: float = 4.0
@export var impact_lifetime: float = 0.6

@onready var _visual: Node3D = $Visual
@onready var _impact_particles: GPUParticles3D = $ImpactParticles
## Optional DamageDealer child; projectiles without one just knock back.
@onready var _damage_dealer: DamageDealer = get_node_or_null("DamageDealer")

var _direction: Vector3 = Vector3.FORWARD
var _exclude_rid: RID
var _spent: bool = false


## Called by ProjectileSpell right after spawning, before the first physics frame.
func launch(direction: Vector3, exclude_rid: RID) -> void:
	_direction = direction.normalized()
	_exclude_rid = exclude_rid


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(max_lifetime).timeout.connect(_expire)


func _physics_process(delta: float) -> void:
	if _spent:
		return
	global_position += _direction * speed * delta


func _on_body_entered(body: Node3D) -> void:
	if _spent or body.get_rid() == _exclude_rid:
		return
	_impact(body)


func _expire() -> void:
	if not _spent:
		_impact(null)


func _impact(body: Node) -> void:
	_spent = true
	if body and body.has_method("apply_impulse"):
		body.apply_impulse(_direction * impact_force, global_position)
	if body and _damage_dealer:
		_damage_dealer.try_deal(body)
	_visual.visible = false
	set_physics_process(false)
	monitoring = false
	if _impact_particles:
		_impact_particles.restart()
		_impact_particles.emitting = true
	get_tree().create_timer(impact_lifetime).timeout.connect(queue_free)
