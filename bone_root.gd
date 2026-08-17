extends Node3D
# Put this on your camera (or a rig node above it)

@export var skeleton: Skeleton3D
@export var bone_name: String = "Head"

var bone_idx: int

func _ready():
	bone_idx = skeleton.find_bone(bone_name)

func _process(_delta):
	var bone_pose = skeleton.get_bone_global_pose(bone_idx)
	var world_pose = skeleton.global_transform * bone_pose
	world_pose.basis = world_pose.basis.orthonormalized()  # strips scale, keeps rotation
	global_transform = world_pose
