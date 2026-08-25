extends Node3D
class_name BoneRoot

@export var skeleton: Skeleton3D
@export var bone_name: String = "Head"

var bone_idx: int = -1

func _ready():
	if (skeleton != null):
		bone_idx = skeleton.find_bone(bone_name)

func _process(_delta):
	if bone_idx == -1:
		if skeleton == null: return
		else:
			bone_idx = skeleton.find_bone(bone_name)
	
	var bone_pose = skeleton.get_bone_global_pose(bone_idx)
	var world_pose = skeleton.global_transform * bone_pose
	world_pose.basis = world_pose.basis.orthonormalized()  # strips scale, keeps rotation
	global_transform = world_pose
