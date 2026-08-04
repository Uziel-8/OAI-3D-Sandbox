extends Projectile
class_name StickyBombProjectile
## A Projectile that does NOT burst on contact: it ATTACHES to the first thing it
## touches -- world geometry, a crate, or a walking enemy -- and then detonates in
## a radius, either when its fuse burns down or when the caster triggers it
## remotely (the "Remote Detonator" pyromancy upgrade, driven by StickyBombSpell).
##
## Sticking TRACKS the target's transform rather than reparenting to it: the bomb
## remembers the local offset it hit at and re-derives its world position each
## frame. That way it rides a moving body without inheriting that body's scale,
## and it survives the body being freed -- a dead enemy just leaves the bomb
## hanging in the air where it fell, still live.
##
## The blast is a ONE-SHOT sphere query at detonation time (same intersect_shape
## pattern as TelekinesisPushSpell) rather than a second monitoring Area3D, so
## blast_radius stays a single exported number instead of also being baked into a
## CollisionShape that could silently drift out of sync with it.

## Emitted the instant this bomb goes off, so StickyBombSpell can drop it from
## its live list without polling.
signal detonated(bomb: StickyBombProjectile)

## Seconds between sticking and going off. Ignored entirely when remote_detonation
## is set -- an upgraded bomb waits indefinitely for the trigger.
@export var fuse_time: float = 3.0
@export var blast_radius: float = 4.0
@export var blast_force: float = 14.0
## Damage multiplier at the very edge of the blast; the centre always takes full
## damage and everything between is lerped, so hugging the bomb hurts most.
@export_range(0.0, 1.0) var edge_damage_scale: float = 0.35
## Whether the blast damages / shoves the player who cast it. Damage is off and
## knockback on by default: your own bomb can launch you but can't kill you.
@export var damages_caster: bool = false
@export var pushes_caster: bool = true
## Multiplier on blast_force when the blast catches the CASTER. blast_force is
## tuned for shoving props and enemies around; the player is a CharacterBody3D
## whose apply_impulse() folds the impulse straight into velocity as if mass were
## 1, so full force launches them absurdly far. Tune the self-launch here without
## touching how hard the blast hits everything else.
@export var caster_force_scale: float = 0.6
## Failsafe for a REMOTE bomb whose caster went away (spell unequipped in the
## spellbook, player died and the scene reloaded). Without this such a bomb would
## sit armed forever with nothing left alive that could trigger it.
@export var orphan_fuse: float = 8.0
## How far back along its flight path the bomb settles on stick, so it rests on
## the surface it hit instead of half-buried in it.
@export var surface_offset: float = 0.12
@export var max_blast_targets: int = 32

## Set by StickyBombSpell.arm() at spawn from the skill tree. True = no fuse.
var remote_detonation: bool = false

@onready var _trail: GPUParticles3D = get_node_or_null("Visual/Trail")
@onready var _light: OmniLight3D = get_node_or_null("Visual/Light")
@onready var _stick_particles: GPUParticles3D = get_node_or_null("StickParticles")
@onready var _blast_light: OmniLight3D = get_node_or_null("ExplosionLight")

var _owner_spell: Node = null
var _stuck_to: Node3D = null
var _stuck_offset: Vector3 = Vector3.ZERO
var _is_stuck: bool = false
var _detonated: bool = false
var _stuck_time: float = 0.0
var _light_energy: float = 3.0


## Called by StickyBombSpell right after launch(). `spell` is only held so an
## orphaned remote bomb can notice its caster is gone; nothing is called on it.
func arm(spell: Node, remote: bool) -> void:
	_owner_spell = spell
	remote_detonation = remote


func _ready() -> void:
	super()
	if _light:
		_light_energy = _light.light_energy


func _physics_process(delta: float) -> void:
	super(delta)  # inherited straight-line flight, which stops once _spent
	if not _is_stuck or _detonated:
		return

	# Ride the target. A freed target (enemy killed mid-fuse) just leaves the
	# bomb at its last position rather than taking it with them.
	if is_instance_valid(_stuck_to):
		global_position = _stuck_to.global_transform * _stuck_offset

	_stuck_time += delta
	_pulse()

	if remote_detonation and not is_instance_valid(_owner_spell) and _stuck_time >= orphan_fuse:
		detonate()


# --- Sticking ----------------------------------------------------------------

## Overrides Projectile._impact: contact attaches instead of bursting.
func _impact(body: Node) -> void:
	_stick_to(body)


## Overrides Projectile._expire: a bomb that flies its whole lifetime without
## hitting anything freezes in mid-air and arms there, rather than vanishing.
func _expire() -> void:
	if not _spent:
		_stick_to(null)


func _stick_to(body: Node) -> void:
	if _is_stuck or _detonated:
		return
	_is_stuck = true
	_spent = true  # stops the inherited flight integration
	# Deferred: Area3D forbids toggling monitoring from inside its own body_entered.
	set_deferred("monitoring", false)

	global_position -= _direction * surface_offset
	if body is Node3D:
		_stuck_to = body
		_stuck_offset = body.global_transform.affine_inverse() * global_position

	if _trail:
		_trail.emitting = false
	if _stick_particles:
		_stick_particles.emitting = true

	if not remote_detonation:
		get_tree().create_timer(fuse_time).timeout.connect(detonate)


## Fuse tell: the light throbs, accelerating as the fuse runs down. A remote bomb
## has no countdown to telegraph, so it just blinks steadily to read as "armed".
func _pulse() -> void:
	if _light == null:
		return
	var rate := 5.0
	if not remote_detonation and fuse_time > 0.0:
		rate = lerpf(4.0, 22.0, clampf(_stuck_time / fuse_time, 0.0, 1.0))
	_light.light_energy = _light_energy * (0.55 + 0.45 * sin(_stuck_time * rate))


# --- Detonation --------------------------------------------------------------

## Blows the bomb up now. Safe to call repeatedly and at any point in its life
## (in flight, stuck, or already spent) -- only the first call does anything.
func detonate() -> void:
	if _detonated:
		return
	_detonated = true
	_spent = true
	_is_stuck = false
	detonated.emit(self)

	_blast()

	_visual.visible = false
	set_physics_process(false)
	set_deferred("monitoring", false)
	if _stick_particles:
		_stick_particles.emitting = false
	if _impact_particles:
		_impact_particles.restart()
		_impact_particles.emitting = true
	if _blast_light:
		_blast_light.omni_range = blast_radius * 1.5
		_blast_light.light_energy = 8.0
		create_tween().tween_property(_blast_light, "light_energy", 0.0, impact_lifetime)
	get_tree().create_timer(impact_lifetime).timeout.connect(queue_free)


func _blast() -> void:
	var shape := SphereShape3D.new()
	shape.radius = blast_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position)

	var hits := get_world_3d().direct_space_state.intersect_shape(query, max_blast_targets)

	# The dealer's damage is the FULL-strength figure (already scaled by INT/WIL
	# through ProjectileSpell), so read it once, drive falloff off it per target,
	# and hand it back untouched afterwards.
	var full_damage := _damage_dealer.damage if _damage_dealer else 0.0
	var handled: Dictionary = {}
	for hit in hits:
		var body := hit.collider as Node3D
		if body == null or handled.has(body.get_instance_id()):
			continue  # a multi-shape body reports once per shape
		handled[body.get_instance_id()] = true
		_apply_blast(body, full_damage)
	if _damage_dealer:
		_damage_dealer.damage = full_damage


func _apply_blast(body: Node3D, full_damage: float) -> void:
	var offset := body.global_position - global_position
	var distance := offset.length()
	var falloff := 1.0 - clampf(distance / blast_radius, 0.0, 1.0)
	var is_caster := body.is_in_group("player")

	# Knockback via the project's duck-typed apply_impulse() convention, with a
	# touch of lift folded in so blasts pop things up rather than only outward.
	if body.has_method("apply_impulse") and (pushes_caster or not is_caster):
		var dir := offset.normalized() if distance > 0.01 else Vector3.UP
		dir = (dir + Vector3.UP * 0.35).normalized()
		var force := blast_force * maxf(falloff, 0.3)
		if is_caster:
			force *= caster_force_scale
		body.apply_impulse(dir * force)

	if _damage_dealer and (damages_caster or not is_caster):
		_damage_dealer.damage = full_damage * lerpf(edge_damage_scale, 1.0, falloff)
		_damage_dealer.try_deal(body)
