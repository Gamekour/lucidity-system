extends Node
class_name SkeletonOverlay

@export var playermodel : PlayerModel
@export var source_skeleton: Skeleton3D
@export var target_skeleton: Skeleton3D
@export var cam_ref : Node3D
@export var IK_mods_disable : Array[IKModifier3D]
@export var IK_mods_disable_LH : Array[IKModifier3D]
@export var bone_mask: PackedStringArray
@export_range(0.0, 1.0, 0.01) var weight: float = 1.0
@export var active: bool = true

@export_enum("X", "Y", "Z") var mirror_axis: int = 0:
	set(value):
		mirror_axis = value
		_mask_dirty = true

@export_group("Camera Aim")
## Bone the camera-driven aim rotation is applied to (typically the chest/upper-spine bone).
@export var chest_bone_name: String = "Chest"
@export var camera_aim_active: bool = true
@export_range(0.0, 1.0, 0.01) var camera_aim_weight: float = 1.0

@export_subgroup("Pitch (look up / down)")
@export var camera_aim_pitch_enabled: bool = true
@export var camera_aim_pitch_axis: Vector3 = Vector3.RIGHT
@export_range(-180.0, 180.0, 0.1) var camera_aim_pitch_offset: float = 0.0
@export_range(-180.0, 180.0, 0.1) var camera_aim_pitch_clamp_min: float = -80.0
@export_range(-180.0, 180.0, 0.1) var camera_aim_pitch_clamp_max: float = 80.0

@export_subgroup("Yaw (turn left / right)")
@export var camera_aim_yaw_enabled: bool = false
@export var camera_aim_yaw_axis: Vector3 = Vector3.UP
@export_range(-180.0, 180.0, 0.1) var camera_aim_yaw_offset: float = 0.0
@export_range(-180.0, 180.0, 0.1) var camera_aim_yaw_clamp_min: float = -80.0
@export_range(-180.0, 180.0, 0.1) var camera_aim_yaw_clamp_max: float = 80.0

@export_subgroup("Roll (lean / tilt)")
@export var camera_aim_roll_enabled: bool = false
@export var camera_aim_roll_axis: Vector3 = Vector3.FORWARD
@export_range(-180.0, 180.0, 0.1) var camera_aim_roll_offset: float = 0.0
@export_range(-180.0, 180.0, 0.1) var camera_aim_roll_clamp_min: float = -80.0
@export_range(-180.0, 180.0, 0.1) var camera_aim_roll_clamp_max: float = 80.0

var _pairs: Array[Vector2i] = []
var _chest_bone_idx: int = -1
var _chest_in_overlay: bool = false
var _chest_rest_rotation: Quaternion = Quaternion.IDENTITY
var _mask_dirty: bool = true

func _ready() -> void:
	process_priority = 100
	_rebuild_pairs()

func _process(_delta: float) -> void:
	if not active or weight <= 0.0:
		return
	if not is_instance_valid(source_skeleton) or not is_instance_valid(target_skeleton):
		return
	if _mask_dirty:
		_rebuild_pairs()
	_apply_overlay()
	_apply_camera_aim()

func _apply_overlay() -> void:
	var active_disable_list = IK_mods_disable_LH if playermodel.left_handed else IK_mods_disable
	for ikmod in active_disable_list:
		ikmod.influence = 0 if active else 1
	for pair in _pairs:
		var target_idx := pair.x
		var source_idx := pair.y
		var source_rot := source_skeleton.get_bone_pose_rotation(source_idx)
		if playermodel.left_handed:
			source_rot = _mirror_rotation(source_rot)
		if weight >= 1.0:
			target_skeleton.set_bone_pose_rotation(target_idx, source_rot)
		else:
			var current_rot := target_skeleton.get_bone_pose_rotation(target_idx)
			target_skeleton.set_bone_pose_rotation(target_idx, current_rot.slerp(source_rot, weight))

func _apply_camera_aim() -> void:
	if not camera_aim_active or camera_aim_weight <= 0.0:
		return
	if _chest_bone_idx == -1 or not is_instance_valid(cam_ref):
		return
	if not camera_aim_pitch_enabled and not camera_aim_yaw_enabled and not camera_aim_roll_enabled:
		return

	var base_rot: Quaternion
	if _chest_in_overlay:
		base_rot = target_skeleton.get_bone_pose_rotation(_chest_bone_idx)
	else:
		base_rot = _chest_rest_rotation

	var skeleton_basis := target_skeleton.global_transform.basis.orthonormalized()
	var cam_basis := cam_ref.global_transform.basis.orthonormalized()

	var local_forward := skeleton_basis.inverse() * (-cam_basis.z)
	var horizontal_len := Vector2(local_forward.x, local_forward.z).length()

	var aim_rot := Quaternion.IDENTITY

	if camera_aim_yaw_enabled:
		var yaw_axis := camera_aim_yaw_axis.normalized()
		if yaw_axis.length_squared() > 0.0:
			var yaw_deg := rad_to_deg(atan2(local_forward.x, local_forward.z))
			yaw_deg = clamp(yaw_deg + camera_aim_yaw_offset, camera_aim_yaw_clamp_min, camera_aim_yaw_clamp_max)
			aim_rot = aim_rot * Quaternion(yaw_axis, deg_to_rad(yaw_deg))

	if camera_aim_pitch_enabled:
		var pitch_axis := camera_aim_pitch_axis.normalized()
		if pitch_axis.length_squared() > 0.0:
			var pitch_deg := -rad_to_deg(atan2(local_forward.y, horizontal_len))
			pitch_deg = clamp(pitch_deg + camera_aim_pitch_offset, camera_aim_pitch_clamp_min, camera_aim_pitch_clamp_max)
			aim_rot = aim_rot * Quaternion(pitch_axis, deg_to_rad(pitch_deg))

	if camera_aim_roll_enabled:
		var roll_axis := camera_aim_roll_axis.normalized()
		if roll_axis.length_squared() > 0.0:
			var local_up := skeleton_basis.inverse() * cam_basis.y
			var roll_deg := rad_to_deg(atan2(local_up.x, local_up.y))
			roll_deg = clamp(roll_deg + camera_aim_roll_offset, camera_aim_roll_clamp_min, camera_aim_roll_clamp_max)
			aim_rot = aim_rot * Quaternion(roll_axis, deg_to_rad(roll_deg))

	var new_rot := base_rot * aim_rot

	if camera_aim_weight >= 1.0:
		target_skeleton.set_bone_pose_rotation(_chest_bone_idx, new_rot)
	else:
		target_skeleton.set_bone_pose_rotation(_chest_bone_idx, base_rot.slerp(new_rot, camera_aim_weight))

func _mirror_rotation(q: Quaternion) -> Quaternion:
	match mirror_axis:
		0: # X
			return Quaternion(q.x, -q.y, -q.z, q.w)
		1: # Y
			return Quaternion(-q.x, q.y, -q.z, q.w)
		2: # Z
			return Quaternion(-q.x, -q.y, q.z, q.w)
	return q

func _mirror_bone_name(bone_name: String) -> String:
	if bone_name.find("Left") != -1:
		return bone_name.replace("Left", "Right")
	elif bone_name.find("Right") != -1:
		return bone_name.replace("Right", "Left")
	return bone_name

func _rebuild_pairs() -> void:
	_pairs.clear()
	_mask_dirty = false
	if not is_instance_valid(source_skeleton) or not is_instance_valid(target_skeleton):
		return

	_chest_bone_idx = target_skeleton.find_bone(chest_bone_name)
	_chest_in_overlay = false
	if _chest_bone_idx == -1 and not chest_bone_name.is_empty():
		push_warning("SkeletonOverlay: chest bone '%s' not found in target_skeleton" % chest_bone_name)
	else:
		_chest_rest_rotation = target_skeleton.get_bone_rest(_chest_bone_idx).basis.get_rotation_quaternion()

	for bone_name in bone_mask:
		var target_idx := target_skeleton.find_bone(_mirror_bone_name(bone_name) if playermodel.left_handed else bone_name)
		if target_idx == -1:
			push_warning("SkeletonOverlay: bone '%s' not found in target_skeleton" % bone_name)
			continue

		var source_bone_name := bone_name

		var source_idx := source_skeleton.find_bone(source_bone_name)
		if source_idx == -1:
			push_warning("SkeletonOverlay: bone '%s' not found in source_skeleton" % source_bone_name)
			continue

		if target_idx == _chest_bone_idx:
			_chest_in_overlay = true

		_pairs.append(Vector2i(target_idx, source_idx))

func enable_bone(bone_name: String) -> void:
	if bone_name not in bone_mask:
		bone_mask.append(bone_name)
		_mask_dirty = true

func disable_bone(bone_name: String) -> void:
	var idx := bone_mask.find(bone_name)
	if idx != -1:
		bone_mask.remove_at(idx)
		_mask_dirty = true

func enable_bone_chain(root_bone_name: String) -> void:
	if not is_instance_valid(target_skeleton):
		return
	var root_idx := target_skeleton.find_bone(root_bone_name)
	if root_idx == -1:
		push_warning("SkeletonOverlay: bone '%s' not found in target_skeleton" % root_bone_name)
		return
	var stack: Array[int] = [root_idx]
	while not stack.is_empty():
		var idx: int = stack.pop_back()
		enable_bone(target_skeleton.get_bone_name(idx))
		for child_idx in target_skeleton.get_bone_children(idx):
			stack.append(child_idx)

func set_mask(bone_names: PackedStringArray) -> void:
	bone_mask = bone_names
	_mask_dirty = true

func clear_mask() -> void:
	bone_mask.clear()
	_mask_dirty = true

func refresh() -> void:
	_mask_dirty = true
