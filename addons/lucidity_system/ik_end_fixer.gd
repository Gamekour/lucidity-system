@tool
class_name IKEndFixer extends SkeletonModifier3D

@export var target_node: Node3D
@export var bone_name: String

var _bone_idx: int = -1

func _ready() -> void:
	if get_skeleton():
		_bone_idx = get_skeleton().find_bone(bone_name)

func _process_modification() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	
	if not skeleton or not target_node or _bone_idx == -1:
		return
		
	# 1. Convert the target's world transform into the Skeleton's local space.
	# (In Godot, bone "global" poses are actually local to the Skeleton3D node).
	var target_local_xform = skeleton.global_transform.affine_inverse() * target_node.global_transform
	
	# 2. Get the bone's current position (already solved by the CCDIK3D above it).
	var current_pose = skeleton.get_bone_global_pose(_bone_idx)
	
	# 3. Combine the target's rotation (basis) with the IK-solved position (origin).
	var new_pose = Transform3D(target_local_xform.basis, current_pose.origin)
	
	# 4. Apply the rotation, factoring in the modifier's built-in influence slider.
	var final_pose = current_pose.interpolate_with(new_pose, influence)
	skeleton.set_bone_global_pose(_bone_idx, final_pose)
