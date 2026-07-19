extends Node3D
class_name HealthBar3D
## Floating, screen-aligned health bar built from two quads (dark background +
## colored fill) -- no texture assets. Add as a child of any body that also has
## a DamageReceiver component; it auto-binds to that receiver, follows the body,
## billboards toward the active camera, and recolors green -> red as health
## drops. Reusable across player/enemies/props, same as the damage components.

@export var bar_width: float = 0.9
@export var bar_height: float = 0.12
## Keep the bar hidden while at full health, revealing it once damaged.
@export var hide_when_full: bool = false
@export var full_color: Color = Color(0.35, 0.8, 0.3)
@export var empty_color: Color = Color(0.85, 0.2, 0.2)

@onready var _background: MeshInstance3D = $Background
@onready var _fill: MeshInstance3D = $Fill

var _receiver: DamageReceiver


func _ready() -> void:
	_receiver = DamageReceiver.find_in(get_parent())
	if _receiver == null:
		push_warning("HealthBar3D on %s: no DamageReceiver found on parent." % get_path())
		set_process(false)
		visible = false
		return

	# Make the exported width/height authoritative over whatever the mesh
	# sub-resources were saved at, so tuning one instance is a single change.
	(_background.mesh as QuadMesh).size = Vector2(bar_width, bar_height)
	(_fill.mesh as QuadMesh).size = Vector2(bar_width, bar_height)

	_receiver.damaged.connect(_on_health_changed)
	_receiver.died.connect(_on_died)
	_refresh(_receiver.health / _receiver.max_health)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Screen-aligned billboard: adopt the camera's orientation so the bar always
	# faces the viewer and stays upright relative to the screen. Only the basis
	# is overwritten, so the bar keeps floating at its parent-driven position.
	global_transform.basis = cam.global_transform.basis


func _on_health_changed(_amount: float, remaining: float, _source: Node) -> void:
	_refresh(remaining / _receiver.max_health)
	visible = true


func _on_died(_source: Node) -> void:
	visible = false


func _refresh(fraction: float) -> void:
	fraction = clampf(fraction, 0.0, 1.0)
	visible = not (hide_when_full and is_equal_approx(fraction, 1.0))
	# Shrink the fill quad and slide it left so it drains toward the left edge
	# instead of shrinking about its center.
	_fill.scale.x = maxf(fraction, 0.0001)
	_fill.position.x = -bar_width * (1.0 - fraction) * 0.5
	var mat := _fill.get_surface_override_material(0)
	if mat is StandardMaterial3D:
		mat.albedo_color = empty_color.lerp(full_color, fraction)
