extends Node
class_name AttachmentController

## Skeleton used to resolve bone transforms for bone-attached bodies.
@export var skeleton: Skeleton3D

var attachments: Array[Dictionary] = []


func _ready() -> void:
	if skeleton:
		_connect_skeleton(skeleton)


func _connect_skeleton(s: Skeleton3D) -> void:
	# Make sure IK / modifiers run on the physics tick, matching RigidBody3D updates,
	# instead of the default _process timing.
	s.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	if not s.skeleton_updated.is_connected(_on_skeleton_updated):
		s.skeleton_updated.connect(_on_skeleton_updated)


func attach(child_body: RigidBody3D, parent_body: Node3D, bone_name: String = "") -> void:
	child_body.get_parent().remove_child(child_body)
	parent_body.add_child(child_body)
	child_body.transform = Transform3D.IDENTITY
	child_body.freeze = true
	child_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	child_body.linear_velocity = Vector3.ZERO
	child_body.angular_velocity = Vector3.ZERO
	child_body.set_collision_layer_value(1, false)

	var bone_idx: int = -1
	if bone_name != "":
		if skeleton == null:
			push_warning("AttachmentController: bone_name '%s' given but no skeleton is set." % bone_name)
		else:
			bone_idx = skeleton.find_bone(bone_name)
			if bone_idx == -1:
				push_warning("AttachmentController: bone '%s' not found on skeleton." % bone_name)

	attachments.append({
		"child": child_body,
		"parent": parent_body,
		"local_xform": Transform3D.IDENTITY,
		"bone_name": bone_name,
		"bone_idx": bone_idx,
	})


func detach(child_body: RigidBody3D) -> void:
	for i in attachments.size():
		if attachments[i]["child"] == child_body:
			attachments.remove_at(i)
			break
	child_body.freeze = false
	child_body.set_collision_layer_value(1, true)


func _on_skeleton_updated() -> void:
	for entry in attachments:
		var child: RigidBody3D = entry["child"]
		var parent: Node3D = entry["parent"]
		if not (is_instance_valid(child) and is_instance_valid(parent)):
			continue

		var bone_idx: int = entry["bone_idx"]
		if bone_idx != -1 and is_instance_valid(skeleton):
			var bone_global_pose: Transform3D = skeleton.get_bone_global_pose(bone_idx)
			child.global_transform = skeleton.global_transform * bone_global_pose * entry["local_xform"]
		else:
			child.global_transform = parent.global_transform * entry["local_xform"]
