extends Skeleton3D
## Builds a 4-legged spider skeleton (1 body bone + 2 bones per leg) entirely
## in code and attaches placeholder capsule/box meshes via BoneAttachment3D.
## Zero animation clips: every leg pose comes from a TwoBoneIK3D modifier
## (one per leg, added here as a child of this Skeleton3D) tracking a foot
## Marker3D target that spider_gait.gd repositions every physics frame.

const BODY_SIZE := Vector3(0.5, 0.25, 0.7)
const UPPER_RADIUS := 0.06
const LOWER_RADIUS := 0.045

## Populated by build(): {upper, lower, lower_length} per leg, in case a
## caller wants the resolved bone data (not required by the gait controller).
var leg_bone_info: Array[Dictionary] = []


func build(leg_dirs: Array, hip_radius: float, foot_radius: float, ride_height: float, knee_lift: float, foot_targets: Array) -> void:
	clear_bones()
	leg_bone_info.clear()

	var body_bone := add_bone("body")
	set_bone_rest(body_bone, Transform3D.IDENTITY)
	_attach_mesh(body_bone, _make_box_mesh(BODY_SIZE), Vector3.ZERO)

	for i in leg_dirs.size():
		var dir: Vector3 = leg_dirs[i]
		var hip_pos := dir * hip_radius
		var foot_pos := Vector3(dir.x * foot_radius, -ride_height, dir.z * foot_radius)
		# Bend the rest-pose knee up and out, like a real spider's femur joint.
		var knee_pos := hip_pos.lerp(foot_pos, 0.5) + Vector3.UP * knee_lift

		var upper_name := "leg%d_upper" % i
		var lower_name := "leg%d_lower" % i

		var upper_dir := knee_pos - hip_pos
		var upper_len := upper_dir.length()
		var upper_basis := _basis_from_y(upper_dir)
		var upper_bone := add_bone(upper_name)
		set_bone_parent(upper_bone, body_bone)
		set_bone_rest(upper_bone, Transform3D(upper_basis, hip_pos))
		_attach_mesh(upper_bone, _make_capsule_mesh(UPPER_RADIUS, upper_len), Vector3(0.0, upper_len * 0.5, 0.0))

		# The lower bone's rest transform is relative to the upper bone, so
		# its world-space direction has to be re-expressed in the upper
		# bone's local frame before it can be used as the lower bone's Y axis.
		var lower_dir_world := foot_pos - knee_pos
		var lower_len := lower_dir_world.length()
		var lower_dir_local := upper_basis.inverse() * lower_dir_world
		var lower_bone := add_bone(lower_name)
		set_bone_parent(lower_bone, upper_bone)
		set_bone_rest(lower_bone, Transform3D(_basis_from_y(lower_dir_local), Vector3(0.0, upper_len, 0.0)))
		_attach_mesh(lower_bone, _make_capsule_mesh(LOWER_RADIUS, lower_len), Vector3(0.0, lower_len * 0.5, 0.0))

		leg_bone_info.append({"upper": upper_name, "lower": lower_name, "lower_length": lower_len})
		_setup_two_bone_ik(i, upper_name, lower_name, lower_len, knee_pos, dir, foot_targets[i])

	reset_bone_poses()


func _setup_two_bone_ik(index: int, upper_name: String, lower_name: String, lower_len: float, knee_pos: Vector3, outward_dir: Vector3, foot_target: Marker3D) -> void:
	# Static pole target: sits up+outward from the knee so the solver always
	# bends the knee outward like a spider leg instead of collapsing inward.
	var pole := Marker3D.new()
	pole.name = "Pole_leg%d" % index
	add_child(pole)
	pole.position = knee_pos + outward_dir * 0.4 + Vector3.UP * 0.4

	var ik := TwoBoneIK3D.new()
	ik.name = "IK_leg%d" % index
	add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, upper_name)
	ik.set_middle_bone_name(0, lower_name)
	# Only 2 real bones per leg (upper/lower) -- no dedicated "foot" bone --
	# so the effector is a virtual point extended past the lower bone's tip,
	# continuing in the same direction the lower bone already points.
	ik.set_use_virtual_end(0, true)
	ik.set_end_bone_direction(0, SkeletonModifier3D.BONE_DIRECTION_FROM_PARENT)
	ik.set_end_bone_length(0, lower_len)
	ik.set_target_node(0, ik.get_path_to(foot_target))
	ik.set_pole_node(0, ik.get_path_to(pole))
	ik.influence = 1.0


func _basis_from_y(y_axis: Vector3) -> Basis:
	var y := y_axis.normalized()
	var reference := Vector3.UP
	if absf(y.dot(reference)) > 0.98:
		reference = Vector3.FORWARD
	var x := reference.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _attach_mesh(bone_idx: int, mesh: Mesh, local_offset: Vector3) -> void:
	var bone_name := get_bone_name(bone_idx)
	var attachment := BoneAttachment3D.new()
	attachment.name = "Attach_%s" % bone_name
	add_child(attachment)
	attachment.bone_name = bone_name
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.position = local_offset
	attachment.add_child(mesh_instance)


func _make_capsule_mesh(radius: float, length: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(length, radius * 2.0 + 0.01)
	return mesh


func _make_box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh
