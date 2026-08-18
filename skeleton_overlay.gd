extends Node
class_name SkeletonOverlay

@export var playermodel : PlayerModel
@export var source_skeleton: Skeleton3D
@export var target_skeleton: Skeleton3D
@export var IK_mods_disable : Array[IKModifier3D]
@export var IK_mods_disable_LH : Array[IKModifier3D]
@export var bone_mask: PackedStringArray = []
@export_range(0.0, 1.0, 0.01) var weight: float = 1.0
@export var active: bool = true

@export_enum("X", "Y", "Z") var mirror_axis: int = 0:
	set(value):
		mirror_axis = value
		_mask_dirty = true

var _pairs: Array[Vector2i] = []
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

## Mirrors a rotation quaternion across the plane perpendicular to mirror_axis.
## For each axis, the component along that axis and w are kept; the other
## two imaginary components are negated. This is the standard trick for
## turning a "copy" of a pose into a true left/right mirror of it.
func _mirror_rotation(q: Quaternion) -> Quaternion:
	match mirror_axis:
		0: # X
			return Quaternion(q.x, -q.y, -q.z, q.w)
		1: # Y
			return Quaternion(-q.x, q.y, -q.z, q.w)
		2: # Z
			return Quaternion(-q.x, -q.y, q.z, q.w)
	return q

## Swaps "Left"/"Right" in a bone name for left_handed_mode source lookups.
## Bones without a Left/Right prefix (e.g. spine, head) are returned unchanged
## and still get their rotation mirrored (useful for e.g. mirrored lean/twist).
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

## Force a rebuild, e.g. after swapping source_skeleton/target_skeleton at runtime.
func refresh() -> void:
	_mask_dirty = true
