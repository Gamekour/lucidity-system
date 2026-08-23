extends Node
class_name AttachmentController

## Skeleton used to resolve bone transforms for bone-attached bodies.
@export var skeleton: Skeleton3D

## Metadata key that a RigidBody3D must carry (via set_meta) whose value
## is the name of the slot it wants to attach to.
const SLOT_META_KEY: String = "attachment_slot"

## Editor-facing list of slot definitions.
@export var slot_definitions: Array[AttachmentSlot]

## Runtime slot table, keyed by slot name.
## Each value: {"parent": Node3D, "bone_name": String, "bone_idx": int, "local_xform": Transform3D, "occupant": RigidBody3D}
var attachment_slots: Dictionary = {}

func _ready() -> void:
	if skeleton:
		_connect_skeleton(skeleton)
	_build_slots()

func _connect_skeleton(s: Skeleton3D) -> void:
	# Make sure IK / modifiers run on the physics tick, matching RigidBody3D updates,
	# instead of the default _process timing.
	s.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	if not s.skeleton_updated.is_connected(_on_skeleton_updated):
		s.skeleton_updated.connect(_on_skeleton_updated)

func _build_slots() -> void:
	attachment_slots.clear()
	for def in slot_definitions:
		if def == null or def.slot_name == "":
			push_warning("AttachmentController: skipping slot definition with empty name.")
			continue
		if attachment_slots.has(def.slot_name):
			push_warning("AttachmentController: duplicate slot name '%s', skipping." % def.slot_name)
			continue

		var parent_node: Node3D = get_parent()
		if parent_node == null:
			push_warning("AttachmentController: slot '%s' has invalid parent_path." % def.slot_name)
			continue

		var bone_idx: int = -1
		if def.bone_name != "":
			if skeleton == null:
				push_warning("AttachmentController: slot '%s' specifies bone_name but no skeleton is set." % def.slot_name)
			else:
				bone_idx = skeleton.find_bone(def.bone_name)
				if bone_idx == -1:
					push_warning("AttachmentController: bone '%s' not found for slot '%s'." % [def.bone_name, def.slot_name])

		# Build the local offset transform from the slot definition's pos/rot offsets.
		# rot_offset is treated as degrees (matches Godot's editor-facing rotation convention).
		var offset_basis: Basis = Basis.from_euler(Vector3(
			deg_to_rad(def.rot_offset.x),
			deg_to_rad(def.rot_offset.y),
			deg_to_rad(def.rot_offset.z)
		))
		var offset_xform: Transform3D = Transform3D(offset_basis, def.pos_offset)

		attachment_slots[def.slot_name] = {
			"parent": parent_node,
			"bone_name": def.bone_name,
			"bone_idx": bone_idx,
			"local_xform": offset_xform,
			"occupant": null,
		}

## Attempts to attach child_body to the slot named in its "attachment_slot" metadata.
## Returns true on success.
func attach(child_body: RigidBody3D) -> bool:
	if not child_body.has_meta(SLOT_META_KEY):
		push_warning("AttachmentController: '%s' has no '%s' metadata set." % [child_body.name, SLOT_META_KEY])
		return false

	var slot_name: String = str(child_body.get_meta(SLOT_META_KEY))
	if not attachment_slots.has(slot_name):
		push_warning("AttachmentController: no slot named '%s' exists." % slot_name)
		return false

	var slot: Dictionary = attachment_slots[slot_name]
	if slot["occupant"] != null:
		push_warning("AttachmentController: slot '%s' is already occupied." % slot_name)
		return false

	var parent_body: Node3D = slot["parent"]

	child_body.get_parent().remove_child(child_body)
	parent_body.add_child(child_body)
	child_body.transform = Transform3D.IDENTITY
	child_body.freeze = true
	child_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	child_body.linear_velocity = Vector3.ZERO
	child_body.angular_velocity = Vector3.ZERO
	child_body.set_collision_layer_value(1, false)

	slot["occupant"] = child_body
	return true

func detach(child_body: RigidBody3D) -> void:
	for slot_name in attachment_slots.keys():
		var slot: Dictionary = attachment_slots[slot_name]
		if slot["occupant"] == child_body:
			slot["occupant"] = null
			break
	child_body.freeze = false
	child_body.set_collision_layer_value(1, true)

func _on_skeleton_updated() -> void:
	for slot_name in attachment_slots.keys():
		var slot: Dictionary = attachment_slots[slot_name]
		var child: RigidBody3D = slot["occupant"]
		if child == null or not is_instance_valid(child):
			continue
		var parent: Node3D = get_parent()

		var bone_idx: int = slot["bone_idx"]
		if bone_idx != -1 and is_instance_valid(skeleton):
			var bone_global_pose: Transform3D = skeleton.get_bone_global_pose(bone_idx)
			child.global_transform = skeleton.global_transform * bone_global_pose * slot["local_xform"]
		else:
			child.global_transform = parent.global_transform * slot["local_xform"]
