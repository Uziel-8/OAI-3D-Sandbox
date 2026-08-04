extends Area3D
class_name Projectile
## Generic flying spell bolt: travels forward at a constant speed (or on a lobbed
## arc, when `flight_gravity` is set above 0) and, on first
## contact with anything (world geometry or an actor), applies an impulse via
## the project's duck-typed apply_impulse() convention (see TelekinesisPushSpell),
## plays an impact burst, and frees itself. Fireball and Ice Bolt are this same
## script with different meshes/particles/speed/impact_force set per scene --
## the flight/impact behavior itself never needs to change per spell.

@export var speed: float = 22.0
## Downward acceleration (m/s^2) while in flight. 0 -- the default -- keeps the
## dead-straight laser flight Fireball and Ice Bolt use. Anything above 0 turns
## the projectile into a LOBBED arc that has to be aimed high to reach distance,
## since ProjectileSpell still aims flat along the crosshair.
## NB: NOT named `gravity` -- Area3D already has a property by that name, and
## redefining it is a hard parse error.
@export var flight_gravity: float = 0.0
## Extra upward speed added on top of the aim direction at launch. Only meaningful
## alongside flight_gravity: it makes an arc read as a deliberate throw rather
## than a dropped rock.
@export var lob_boost: float = 0.0
@export var impact_force: float = 12.0
@export var max_lifetime: float = 4.0
@export var impact_lifetime: float = 0.6

@onready var _visual: Node3D = $Visual
@onready var _impact_particles: GPUParticles3D = $ImpactParticles
## Optional DamageDealer child; projectiles without one just knock back.
@onready var _damage_dealer: DamageDealer = get_node_or_null("DamageDealer")

## The CURRENT travel direction -- with gravity it curves over the flight, so
## impact knockback (and the sticky bomb's surface offset) stay correct.
var _direction: Vector3 = Vector3.FORWARD
var _velocity: Vector3 = Vector3.ZERO
var _exclude_rid: RID
var _spent: bool = false


## Called by ProjectileSpell right after spawning, before the first physics frame.
func launch(direction: Vector3, exclude_rid: RID) -> void:
	_velocity = direction.normalized() * speed + Vector3.UP * lob_boost
	_direction = _velocity.normalized()
	_exclude_rid = exclude_rid


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Seeded here as well so a projectile placed directly in a scene, with no
	# launch() call, still flies. launch() runs after add_child and overwrites it.
	if _velocity == Vector3.ZERO:
		_velocity = _direction * speed
	get_tree().create_timer(max_lifetime).timeout.connect(_expire)


func _physics_process(delta: float) -> void:
	if _spent:
		return
	if flight_gravity != 0.0:
		_velocity.y -= flight_gravity * delta
		_direction = _velocity.normalized()
	global_position += _velocity * delta


func _on_body_entered(body: Node3D) -> void:
	if _spent:
		return
	# The caster is excluded by RID, but only CollisionObject3D bodies have
	# get_rid(). CSG greybox geometry (use_collision on a CSGBox3D, which is a
	# VisualInstance3D) registers a collider without being one, so guard the
	# call -- such bodies aren't the caster anyway and should just be impacted.
	if body.has_method("get_rid") and body.get_rid() == _exclude_rid:
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
