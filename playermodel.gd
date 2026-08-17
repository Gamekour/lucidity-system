extends Skeleton3D

@export var cam_spring : SpringArm3D
@export var fp_deadzone : float = 0.05
@export var head_bone_name : String = "Head"

func _process(delta: float) -> void:
	var head_bone_index : int = find_bone(head_bone_name)
	var target_basis : Basis = global_transform.basis.inverse() * cam_spring.global_transform.basis

	target_basis.y = -target_basis.y

	var parent_index : int = get_bone_parent(head_bone_index)
	var parent_global_basis : Basis = Basis.IDENTITY
	if parent_index >= 0:
		parent_global_basis = get_bone_global_pose(parent_index).basis

	var local_basis : Basis = parent_global_basis.inverse() * target_basis
	local_basis = local_basis.orthonormalized()
	
	if (cam_spring.spring_length <= fp_deadzone):
		set_bone_pose_scale(head_bone_index, Vector3.ONE * 0.001) # eventually toggle by camera activity
		set_bone_pose_rotation(head_bone_index, local_basis.get_rotation_quaternion())
	else:
		set_bone_pose_scale(head_bone_index, Vector3.ONE)
		set_bone_pose_rotation(head_bone_index, basis.get_rotation_quaternion())
