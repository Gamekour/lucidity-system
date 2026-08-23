extends Node
class_name AttachmentController

## Skeleton used to resolve bone transforms for bone-attached bodies.
@export var skeleton: Skeleton3D

## Metadata key that a RigidBody3D must carry (via set_meta) whose value
## is the name of the slot it wants to attach to.
const SLOT_META_KEY: String = "attachment_slot"

## Name of the optional child node on an attaching body whose local transform
## is used as an additional offset on top of the slot's own offset.
const ATTACHMENT_ORIGIN_NAME: String = "attachment_origin"

## Editor-facing list of slot definitions.
@export var slot_definitions: Array[AttachmentSlot]
var hotbar : Array[AttachmentSlot]
var current_hotbar_slot : int = 0

var attachment_slots: Dictionary = {}

func _ready() -> void:
	if skeleton:
		_connect_skeleton(skeleton)
	_build_slots()
	for slot in slot_definitions:
		if (slot["is_hotbar"]):
			hotbar.append(slot)

func _input(event: InputEvent) -> void:
	if (event.is_action_pressed("hotbar_direct")):
		print(event.as_text())

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
			"origin_xform_inv": Transform3D.IDENTITY,
			"is_hotbar" : def.is_hotbar,
			"is_hidden" : def.is_hidden
		}

## Looks for a child node named ATTACHMENT_ORIGIN_NAME on the given body and
## returns its local transform (relative to the body). Returns identity if
## no such node exists, so bodies without an origin marker behave as before.
func _find_attachment_origin(body: Node3D) -> Transform3D:
	var origin_node := body.get_node_or_null(ATTACHMENT_ORIGIN_NAME)
	if origin_node == null or not (origin_node is Node3D):
		return Transform3D.IDENTITY
	return origin_node.transform
	
func _find_skeleton_overlay(body : Node3D) -> SkeletonOverlay:
	var origin_node := body.get_node_or_null("SkeletonOverlay")
	if origin_node == null or not (origin_node is SkeletonOverlay):
		return null
	return origin_node

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
	
	if (child_body.has_meta("allow_grab")):
		if (parent_body is PhysicsPlayerController):
			parent_body.allow_grab = child_body.get_meta("allow_grab")

	# Resolve and cache the body's attachment_origin offset (if any) so we don't
	# need to re-fetch the node every skeleton update.
	var origin_xform: Transform3D = _find_attachment_origin(child_body)
	var skeleton_overlay = _find_skeleton_overlay(child_body)
	if (skeleton_overlay != null):
		skeleton_overlay.target_skeleton = skeleton
		skeleton_overlay.active = true
	slot["origin_xform_inv"] = origin_xform.affine_inverse()

	child_body.get_parent().remove_child(child_body)
	parent_body.add_child(child_body)
	child_body.transform = Transform3D.IDENTITY
	child_body.freeze = true
	child_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	child_body.linear_velocity = Vector3.ZERO
	child_body.angular_velocity = Vector3.ZERO
	child_body.set_collision_layer_value(1, false)

	slot["occupant"] = child_body
	
	if (parent_body is RigidBody3D and child_body is RigidBody3D):
		parent_body.mass += child_body.mass
	return true

func detach(child_body: RigidBody3D) -> void:
	var former_parent : Node3D = child_body.get_parent_node_3d()
	for slot_name in attachment_slots.keys():
		var slot: Dictionary = attachment_slots[slot_name]
		if slot["occupant"] == child_body:
			slot["occupant"] = null
			slot["origin_xform_inv"] = Transform3D.IDENTITY
			break
	child_body.freeze = false
	child_body.set_collision_layer_value(1, true)
	var skeleton_overlay = _find_skeleton_overlay(child_body)
	if (skeleton_overlay != null):
		skeleton_overlay.active = false
	if (former_parent is RigidBody3D and child_body is RigidBody3D):
		former_parent.mass -= child_body.mass
	if (former_parent is PhysicsPlayerController):
		former_parent.allow_grab = former_parent.allow_grab_default

func _on_skeleton_updated() -> void:
	for slot_name in attachment_slots.keys():
		var slot: Dictionary = attachment_slots[slot_name]
		var child: RigidBody3D = slot["occupant"]
		if child == null or not is_instance_valid(child):
			continue
		var parent: Node3D = get_parent()

		var target_xform: Transform3D
		var is_equipped = false
		if (slot["is_hotbar"]):
			var hotbar_index = 0
			var i = 0
			for chk_slot in hotbar:
				if (chk_slot.slot_name == slot_name):
					hotbar_index = i
					continue
				else:
					i += 1
			is_equipped = hotbar_index == current_hotbar_slot
		var bone_idx: int = slot["bone_idx"] if !slot["is_hotbar"] else skeleton.find_bone("RightHand")
		if bone_idx != -1 and is_instance_valid(skeleton):
			var bone_global_pose: Transform3D = skeleton.get_bone_global_pose(bone_idx)
			target_xform = skeleton.global_transform * bone_global_pose * slot["local_xform"]
		else:
			target_xform = parent.global_transform * slot["local_xform"]

		# Post-multiply by the inverse of the body's attachment_origin local transform
		# so that the origin node (not the body's own origin) lands on the target.
		child.global_transform = target_xform * slot["origin_xform_inv"]
