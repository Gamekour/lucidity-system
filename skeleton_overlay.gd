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
@export var active: bool = true:
	set(value):
		var changed := active != value
		active = value
		if changed and is_instance_valid(playermodel):
			toggle_ik()

@export_enum("X", "Y", "Z") var mirror_axis: int = 0:
	set(value):
		mirror_axis = value
		_mask_dirty = true

@export_group("Camera Aim")
## Bones the camera-driven aim rotation is applied to (e.g. chest/upper-spine bone).
## These may overlap with bone_mask: when they do, the aim rotation is applied
## as an offset on top of the copied source pose rotation instead of the rest pose.
@export var camera_aim_bone_names: PackedStringArray = ["RightUpperArm", "LeftUpperArm"]:
	set(value):
		camera_aim_bone_names = value
		_mask_dirty = true
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

# One entry per resolved camera-aim bone:
#   "idx"       -> bone index in target_skeleton
#   "in_overlay"-> true if this bone is also driven by bone_mask (copied pose this frame)
var _aim_bone_data: Array[Dictionary] = []

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

func toggle_ik():
	var active_disable_list = IK_mods_disable_LH if playermodel.left_handed else IK_mods_disable
	for ikmod in active_disable_list:
		ikmod.influence = 0 if active else 1

func _apply_camera_aim() -> void:
	if not camera_aim_active or camera_aim_weight <= 0.0:
		return
	if _aim_bone_data.is_empty() or not is_instance_valid(cam_ref):
		return
	if not camera_aim_pitch_enabled and not camera_aim_yaw_enabled and not camera_aim_roll_enabled:
		return

	var aim_rot := _compute_aim_rotation()
	var aim_basis := Basis(aim_rot)

	for data in _aim_bone_data:
		var idx: int = data["idx"]
		var in_overlay: bool = data["in_overlay"]

		if not in_overlay:
			# Not refreshed by _apply_overlay this frame - reset to a clean rest-relative
			# pose first so the aim offset doesn't compound frame after frame.
			target_skeleton.set_bone_pose_rotation(idx, Quaternion.IDENTITY)

		var base_pose_rot := target_skeleton.get_bone_pose_rotation(idx)

		# Current orientation of the bone in skeleton-local space (matches the frame
		# aim_rot was computed in), including rest pose + parent chain + current pose.
		var current_global_basis := target_skeleton.get_bone_global_pose(idx).basis
		var desired_global_basis := aim_basis * current_global_basis

		# Convert the desired skeleton-space orientation back into this bone's own
		# local pose space (relative to its parent and its own rest orientation),
		# instead of assuming world axes line up with the bone's local axes.
		var parent_idx := target_skeleton.get_bone_parent(idx)
		var parent_global_basis := Basis.IDENTITY if parent_idx == -1 else target_skeleton.get_bone_global_pose(parent_idx).basis
		var rest_basis := target_skeleton.get_bone_rest(idx).basis

		var new_pose_basis := rest_basis.inverse() * parent_global_basis.inverse() * desired_global_basis
		var new_pose_rot := new_pose_basis.orthonormalized().get_rotation_quaternion()

		if camera_aim_weight >= 1.0:
			target_skeleton.set_bone_pose_rotation(idx, new_pose_rot)
		else:
			target_skeleton.set_bone_pose_rotation(idx, base_pose_rot.slerp(new_pose_rot, camera_aim_weight))

## Computes the camera-driven aim offset rotation (pitch/yaw/roll) relative to
## the target skeleton's orientation. This is the same for every aim bone;
## it's applied as an offset on top of each bone's own base rotation.
func _compute_aim_rotation() -> Quaternion:
	var skeleton_basis := target_skeleton.global_transform.basis.orthonormalized()
	var cam_basis := cam_ref.global_transform.basis.orthonormalized()

	var local_forward := skeleton_basis.inverse() * (-cam_basis.z)
	var horizontal_len := Vector2(local_forward.x, local_forward.z).length()

	var aim_rot := Quaternion.IDENTITY

	if camera_aim_yaw_enabled && playermodel.is_fp:
		var yaw_axis := camera_aim_yaw_axis.normalized()
		if yaw_axis.length_squared() > 0.0:
			var yaw_deg := rad_to_deg(atan2(local_forward.x, local_forward.z))
			yaw_deg = clamp(yaw_deg + camera_aim_yaw_offset, camera_aim_yaw_clamp_min, camera_aim_yaw_clamp_max)
			aim_rot = aim_rot * Quaternion(yaw_axis, deg_to_rad(-yaw_deg))

	if camera_aim_pitch_enabled:
		var pitch_axis := camera_aim_pitch_axis.normalized()
		if pitch_axis.length_squared() > 0.0:
			var pitch_deg := -rad_to_deg(atan2(local_forward.y, horizontal_len))
			pitch_deg = clamp(pitch_deg + camera_aim_pitch_offset, camera_aim_pitch_clamp_min, camera_aim_pitch_clamp_max)
			aim_rot = aim_rot * Quaternion(pitch_axis, deg_to_rad(pitch_deg + 180))

	if camera_aim_roll_enabled:
		var roll_axis := camera_aim_roll_axis.normalized()
		if roll_axis.length_squared() > 0.0:
			var local_up := skeleton_basis.inverse() * cam_basis.y
			var roll_deg := rad_to_deg(atan2(local_up.x, local_up.y))
			roll_deg = clamp(roll_deg + camera_aim_roll_offset, camera_aim_roll_clamp_min, camera_aim_roll_clamp_max)
			aim_rot = aim_rot * Quaternion(roll_axis, deg_to_rad(roll_deg))

	return aim_rot

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
	_aim_bone_data.clear()
	_mask_dirty = false
	if not is_instance_valid(source_skeleton) or not is_instance_valid(target_skeleton):
		return

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

		_pairs.append(Vector2i(target_idx, source_idx))

	for bone_name in camera_aim_bone_names:
		var resolved_name := _mirror_bone_name(bone_name) if playermodel.left_handed else bone_name
		var idx := target_skeleton.find_bone(resolved_name)
		if idx == -1:
			if not bone_name.is_empty():
				push_warning("SkeletonOverlay: camera aim bone '%s' not found in target_skeleton" % bone_name)
			continue

		var in_overlay := false
		for pair in _pairs:
			if pair.x == idx:
				in_overlay = true
				break

		_aim_bone_data.append({"idx": idx, "in_overlay": in_overlay})

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

## Camera-aim bone list management, mirrors the bone_mask helpers above.
func enable_camera_aim_bone(bone_name: String) -> void:
	if bone_name not in camera_aim_bone_names:
		camera_aim_bone_names.append(bone_name)
		_mask_dirty = true

func disable_camera_aim_bone(bone_name: String) -> void:
	var idx := camera_aim_bone_names.find(bone_name)
	if idx != -1:
		camera_aim_bone_names.remove_at(idx)
		_mask_dirty = true

func set_camera_aim_bones(bone_names: PackedStringArray) -> void:
	camera_aim_bone_names = bone_names
	_mask_dirty = true

func clear_camera_aim_bones() -> void:
	camera_aim_bone_names.clear()
	_mask_dirty = true

func refresh() -> void:
	_mask_dirty = true
