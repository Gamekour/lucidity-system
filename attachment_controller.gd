extends Node
class_name AttachmentController

@export var body : PhysicsPlayerController
@export var shapecast : ShapeCast3D
@export var skeleton: Skeleton3D
@export var playermodel: PlayerModel

const SLOT_META_KEY: String = "attachment_slot"

const ATTACHMENT_ORIGIN_NAME: String = "attachment_origin"

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
		current_hotbar_slot = int(event.as_text()) - 1
		_on_hotbar_change()
	if (event.is_action_pressed("drop")):
		detach_hotbar_slot(current_hotbar_slot)

func detach_hotbar_slot(hotbar_index: int) -> void:
	if hotbar_index < 0 or hotbar_index >= hotbar.size():
		push_warning("AttachmentController: invalid hotbar index '%d'." % hotbar_index)
		return

	var slot_def: AttachmentSlot = hotbar[hotbar_index]
	if slot_def == null or not attachment_slots.has(slot_def.slot_name):
		push_warning("AttachmentController: hotbar slot at index '%d' not found in attachment_slots." % hotbar_index)
		return

	var slot: Dictionary = attachment_slots[slot_def.slot_name]
	var occupant: RigidBody3D = slot["occupant"]
	if occupant == null or not is_instance_valid(occupant):
		return

	detach(occupant)

func _connect_skeleton(s: Skeleton3D) -> void:
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
			"is_hidden" : def.is_hidden,
			"temp_shown" : false
		}

func _find_attachment_origin(body: Node3D) -> Transform3D:
	var origin_node := body.get_node_or_null(ATTACHMENT_ORIGIN_NAME)
	if origin_node == null or not (origin_node is Node3D):
		return Transform3D.IDENTITY
	return origin_node.transform
	
func _is_left_handed() -> bool:
	return is_instance_valid(playermodel) and playermodel.left_handed

func _mirror_bone_name(bone_name: String) -> String:
	if bone_name.find("Left") != -1:
		return bone_name.replace("Left", "Right")
	elif bone_name.find("Right") != -1:
		return bone_name.replace("Right", "Left")
	return bone_name

func _resolve_bone_idx(slot: Dictionary) -> int:
	var bone_name: String = slot["bone_name"]
	if bone_name == "" or not is_instance_valid(skeleton):
		return -1
	if _is_left_handed():
		bone_name = _mirror_bone_name(bone_name)
	return skeleton.find_bone(bone_name)

func _find_skeleton_overlay(body : Node3D) -> SkeletonOverlay:
	var origin_node := body.get_node_or_null("SkeletonOverlay")
	if origin_node == null or not (origin_node is SkeletonOverlay):
		return null
	return origin_node

func _on_hotbar_change() -> void:
	for i in range(hotbar.size()):
		var slot_def: AttachmentSlot = hotbar[i]
		if slot_def == null or not attachment_slots.has(slot_def.slot_name):
			continue

		var slot: Dictionary = attachment_slots[slot_def.slot_name]
		var occupant: RigidBody3D = slot["occupant"]
		if occupant == null or not is_instance_valid(occupant):
			continue

		var skeleton_overlay := _find_skeleton_overlay(occupant)
		if skeleton_overlay == null:
			continue

		var is_equipped: bool = i == current_hotbar_slot
		if is_equipped and not slot["is_hidden"]:
			skeleton_overlay.active = true
		else:
			skeleton_overlay.active = false
			if (body != null):
				if (body is PhysicsPlayerController):
					body.overlay_eulers = Vector3.ZERO

func _set_meshes_and_collisions_enabled(node: Node, enabled: bool) -> void:
	if node is MeshInstance3D:
		node.visible = enabled
	elif node is CollisionShape3D:
		node.disabled = not enabled
	elif node is CollisionPolygon3D:
		node.disabled = not enabled
	for child in node.get_children():
		_set_meshes_and_collisions_enabled(child, enabled)

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

	var origin_xform: Transform3D = _find_attachment_origin(child_body)
	var skeleton_overlay = _find_skeleton_overlay(child_body)
	var is_equipped := false
	var is_hotbar = slot["is_hotbar"]
	if (is_hotbar):
			var hotbar_index = 0
			var i = 0
			for chk_slot in hotbar:
				if (chk_slot.slot_name == slot_name):
					hotbar_index = i
					continue
				else:
					i += 1
			is_equipped = hotbar_index == current_hotbar_slot
	var holstered = is_hotbar and not is_equipped
	if (skeleton_overlay != null):
		skeleton_overlay.playermodel = playermodel
		if (parent_body is PhysicsPlayerController):
			skeleton_overlay.body = parent_body
		if (not slot["is_hidden"] and not holstered):
			skeleton_overlay.set_deferred("active", true)
	slot["origin_xform_inv"] = origin_xform.affine_inverse()

	child_body.get_parent().remove_child(child_body)
	parent_body.add_child(child_body)
	child_body.transform = Transform3D.IDENTITY
	child_body.freeze = true
	child_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	child_body.linear_velocity = Vector3.ZERO
	child_body.angular_velocity = Vector3.ZERO
	
	body.add_collision_exception_with(child_body)
	for i in body.find_children("*", "SpringArm3D", true, false):
		i.add_excluded_object(child_body.get_rid())
	for i in body.find_children("*", "ShapeCast3D", true, false):
		i.add_exception(child_body)

	if slot["is_hidden"]:
		_set_meshes_and_collisions_enabled(child_body, false)
		slot["temp_shown"] = false

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
			if slot["is_hidden"]:
				_set_meshes_and_collisions_enabled(child_body, true)
			slot["temp_shown"] = false
			break
	child_body.freeze = false
	
	body._queue_collision_exception_release(child_body)
	shapecast.remove_exception(child_body)
	for i in body.find_children("*", "SpringArm3D", true, false):
		i.remove_excluded_object(child_body.get_rid())
	for i in body.find_children("*", "ShapeCast3D", true, false):
		i.remove_exception(child_body)
	var skeleton_overlay = _find_skeleton_overlay(child_body)
	if (skeleton_overlay != null):
		skeleton_overlay.active = false
	if (former_parent is RigidBody3D and child_body is RigidBody3D):
		former_parent.mass -= child_body.mass
	if (former_parent is PhysicsPlayerController):
		former_parent.allow_grab = former_parent.allow_grab_default
		former_parent.overlay_eulers = Vector3.ZERO
	child_body.reparent(get_tree().root)

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

		if slot["is_hidden"]:
			var should_show: bool = is_equipped
			if slot["temp_shown"] != should_show:
				_set_meshes_and_collisions_enabled(child, should_show)
				slot["temp_shown"] = should_show

		var bone_idx: int
		if is_equipped:
			var hand_bone_name: String = _mirror_bone_name("RightHand") if _is_left_handed() else "RightHand"
			bone_idx = skeleton.find_bone(hand_bone_name) if is_instance_valid(skeleton) else -1
		else:
			bone_idx = _resolve_bone_idx(slot)
		if bone_idx != -1 and is_instance_valid(skeleton):
			var bone_global_pose: Transform3D = skeleton.get_bone_global_pose(bone_idx)
			target_xform = skeleton.global_transform * bone_global_pose * slot["local_xform"]
		else:
			target_xform = parent.global_transform * slot["local_xform"]

		child.global_transform = target_xform * slot["origin_xform_inv"]
