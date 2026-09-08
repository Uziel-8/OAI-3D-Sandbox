class_name CelShaderApplier
extends Node

## Drop-in preview: swaps every mesh material below [member target] for the cel
## shader at runtime, deriving each cel material's colour and texture from the
## material it replaces.
##
## Nothing is written back to the scene -- overrides are assigned in [method _ready]
## on the live nodes -- so the level's authored materials are untouched. That is the
## whole point: the KayKit props keep their materials inside their .gltf imports, and
## converting those for real would mean an editable instance and a hand-authored
## override for every surface in the level.

## Set false to see the level with its normal materials without removing the node.
@export var enabled: bool = true
@export var cel_shader: Shader
## Assigned to each generated material's next_pass. This is the inverted-hull
## outline, which only exists as a second pass -- there is no screen-space step.
@export var outline_material: Material
@export var apply_outline: bool = true
## Leave null to convert this node's parent, i.e. the level root.
@export var target: Node

## The cel base shader is opaque, so converting a flame card or a glass pane would
## turn it into a solid block. Their originals are left alone.
@export var skip_transparent: bool = true
## Meshes already driven by a custom shader are left alone rather than clobbered.
@export var skip_shader_materials: bool = true
## The cel base shader compiles emission out (USE_EMISSION is 0), so converting a
## torch flame would extinguish it. Their originals are left alone.
@export var skip_emissive: bool = true
## Nodes in any of these groups are skipped, along with everything beneath them.
@export var skip_groups: Array[StringName] = []
## Colour used for a surface that had no material of its own. White matches what
## Godot renders such a surface as, but cel shading pins a lit white surface at
## full brightness, so a greybox level usually wants this knocked down.
@export var default_color: Color = Color.WHITE

var _converted: int = 0
var _skipped: int = 0


func _ready() -> void:
	if not enabled:
		return
	if cel_shader == null:
		push_warning("CelShaderApplier: no cel_shader assigned, nothing to apply.")
		return

	var root: Node = target if target != null else get_parent()
	if root == null:
		push_warning("CelShaderApplier: no target and no parent to convert.")
		return

	_convert(root)
	print("CelShaderApplier: converted %d surface(s), skipped %d." % [_converted, _skipped])


func _convert(node: Node) -> void:
	for group in skip_groups:
		if node.is_in_group(group):
			return

	if node is MeshInstance3D:
		_convert_mesh(node)
	elif node is CSGPrimitive3D:
		_convert_csg(node)

	for child in node.get_children():
		_convert(child)


func _convert_mesh(mesh_instance: MeshInstance3D) -> void:
	# material_override beats every per-surface slot, so replacing a surface while
	# one is set would silently do nothing. Convert the override itself instead.
	if mesh_instance.material_override != null:
		var overridden := _make_material(mesh_instance.material_override)
		if overridden != null:
			mesh_instance.material_override = overridden
		return

	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return

	for surface in mesh.get_surface_count():
		# get_active_material resolves override > surface override > mesh material,
		# which is the material actually on screen and the one worth deriving from.
		var cel := _make_material(mesh_instance.get_active_material(surface))
		if cel != null:
			mesh_instance.set_surface_override_material(surface, cel)


func _convert_csg(csg: CSGPrimitive3D) -> void:
	var cel := _make_material(csg.material)
	if cel != null:
		csg.material = cel


## Returns null when [param source] should keep the material it already has.
func _make_material(source: Material) -> ShaderMaterial:
	if skip_shader_materials and source is ShaderMaterial:
		_skipped += 1
		return null

	var base := source as BaseMaterial3D
	if base != null:
		if skip_transparent and base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			_skipped += 1
			return null
		if skip_emissive and base.emission_enabled:
			_skipped += 1
			return null

	var cel := ShaderMaterial.new()
	cel.shader = cel_shader

	# A surface with no material at all renders white in Godot. Either way it must be
	# set explicitly, or it falls through to the shader's own lurid default colour.
	cel.set_shader_parameter("color", default_color)

	# An unassigned base_texture samples as white, so a colour-only material needs
	# no texture at all -- same as the hand-authored materials in Materials/Cel.
	if base != null:
		cel.set_shader_parameter("color", base.albedo_color)
		if base.albedo_texture != null:
			cel.set_shader_parameter("base_texture", base.albedo_texture)

	if apply_outline and outline_material != null:
		cel.next_pass = outline_material

	_converted += 1
	return cel
