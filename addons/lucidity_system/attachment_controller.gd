extends Node
class_name AttachmentController

var body : PhysicsPlayerController:
	set(new_body):
		if is_instance_valid(body) and body.tree_exiting.is_connected(_on_body_tree_exiting):
			body.tree_exiting.disconnect(_on_body_tree_exiting)
		body = new_body
		if is_instance_valid(body) and not body.tree_exiting.is_connected(_on_body_tree_exiting):
			body.tree_exiting.connect(_on_body_tree_exiting)
var playermodel: PlayerModel

const SLOT_META_KEY: String = "attachment_slot"
const ATTACHED_META_KEY: String = "_attachment_controller"

const ATTACHMENT_ORIGIN_NAME: String = "attachment_origin"

@export var slot_definitions: Array[AttachmentSlot]
@export var drop_distance: float = 1.0
@export var drop_height: float = 0.2
@export var sway_spring_strength: float = 200.0
@export var sway_spring_damping: float = 20.0
@export var sway_velocity_scale: float = 0.0
@export var sway_torque_spring_strength: float = 200.0
@export var sway_torque_spring_damping: float = 20.0
var hotbar : Array[AttachmentSlot]
var current_hotbar_slot : int = 0

var attachment_slots: Dictionary = {}

func _ready() -> void:
	_build_slots()
	for slot in slot_definitions:
		if (slot["is_hotbar"]):
			hotbar.append(slot)
	if not multiplayer.is_server():
		_request_sync_state.rpc_id(1)

func _input(event: InputEvent) -> void:
	if body == null or not body.is_local_owner():
		return
	if (event.is_action_pressed("hotbar_direct")):
		request_hotbar_change(int(event.as_text()) - 1)
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

	request_detach(occupant)

@rpc("any_peer")
func request_attach(child_body_path: String) -> void:
	var child_body = get_node(child_body_path) #will throw an error if already attached, can be ignored
	if body == null or not is_instance_valid(child_body):
		return
	if multiplayer.is_server():
		_do_attach.rpc(child_body.get_path())
	else:
		print("f")
		_request_attach.rpc_id(1, child_body.get_path())

func request_detach(child_body: RigidBody3D) -> void:
	if body == null or not is_instance_valid(child_body):
		return
	if multiplayer.is_server():
		_do_detach.rpc(child_body.get_path())
	else:
		_request_detach.rpc_id(1, child_body.get_path())

func request_hotbar_change(slot_index: int) -> void:
	if body == null:
		return
	if multiplayer.is_server():
		_do_hotbar_change.rpc(slot_index)
	else:
		_request_hotbar_change.rpc_id(1, slot_index)

@rpc("any_peer", "call_remote", "reliable")
func _request_attach(child_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != body.owner_peer_id:
		return
	_do_attach.rpc(child_path)

@rpc("any_peer", "call_remote", "reliable")
func _request_detach(child_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != body.owner_peer_id:
		return
	_do_detach.rpc(child_path)

@rpc("any_peer", "call_remote", "reliable")
func _request_hotbar_change(slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != body.owner_peer_id:
		return
	_do_hotbar_change.rpc(slot_index)

@rpc("any_peer", "call_local", "reliable")
func _do_attach(child_path: NodePath) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	var child_body := get_node_or_null(child_path)
	if child_body is RigidBody3D:
		attach(child_body)

@rpc("any_peer", "call_local", "reliable")
func _do_detach(child_path: NodePath) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	var child_body := get_node_or_null(child_path)
	if child_body is RigidBody3D:
		detach(child_body)

@rpc("any_peer", "call_local", "reliable")
func _do_hotbar_change(slot_index: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	current_hotbar_slot = slot_index
	_on_hotbar_change()

func attach_and_sync(child_body: RigidBody3D) -> bool:
	var success := attach(child_body)
	if success:
		_sync_attach.rpc(child_body.get_path())
	return success

@rpc("authority", "call_remote", "reliable")
func _sync_attach(child_path: NodePath) -> void:
	var child_body := get_node_or_null(child_path)
	if child_body is RigidBody3D:
		attach(child_body)

@rpc("any_peer", "call_remote", "reliable")
func _request_sync_state() -> void:
	if not multiplayer.is_server():
		return
	var requester := multiplayer.get_remote_sender_id()
	for slot_name in attachment_slots.keys():
		var slot: Dictionary = attachment_slots[slot_name]
		var occupant : RigidBody3D = slot["occupant"]
		if occupant != null and is_instance_valid(occupant):
			_sync_attach.rpc_id(requester, occupant.get_path())

func _connect_skeleton(s: Skeleton3D) -> void:
	if (s is PlayerModel):
		playermodel = s
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
			if playermodel == null:
				push_warning("AttachmentController: slot '%s' specifies bone_name but no skeleton is set." % def.slot_name)
			else:
				bone_idx = playermodel.find_bone(def.bone_name)
				if bone_idx == -1:
					push_warning("AttachmentController: bone '%s' not found for slot '%s'." % [def.bone_name, def.slot_name])

		var offset_basis: Basis = Basis.from_euler(Vector3(
			deg_to_rad(def.rot_offset.x),
			deg_to_rad(def.rot_offset.y),
			deg_to_rad(def.rot_offset.z)
		))
		var offset_basis_equipped: Basis = Basis.from_euler(Vector3(
			deg_to_rad(def.rot_offset_equipped.x),
			deg_to_rad(def.rot_offset_equipped.y),
			deg_to_rad(def.rot_offset_equipped.z)
		))
		var offset_xform: Transform3D = Transform3D(offset_basis, def.pos_offset)
		var offset_xform_equipped : Transform3D = Transform3D(offset_basis_equipped, def.pos_offset_equipped)
		
		attachment_slots[def.slot_name] = {
			"parent": parent_node,
			"bone_name": def.bone_name,
			"bone_idx": bone_idx,
			"local_xform": offset_xform,
			"local_xform_equipped" : offset_xform_equipped,
			"occupant": null,
			"origin_xform_inv": Transform3D.IDENTITY,
			"is_hotbar" : def.is_hotbar,
			"is_hidden" : def.is_hidden,
			"temp_shown" : false,
			"relative_velocity": Vector3.ZERO,
			"sway_offset": Vector3.ZERO,
			"angular_velocity": Vector3.ZERO,
			"sway_angular_offset": Vector3.ZERO
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

func add_sway_impulse(slot_name: String, impulse: Vector3) -> void:
	if not attachment_slots.has(slot_name):
		return
	attachment_slots[slot_name]["relative_velocity"] += impulse

func add_sway_torque_impulse(slot_name: String, impulse: Vector3) -> void:
	if not attachment_slots.has(slot_name):
		return
	attachment_slots[slot_name]["angular_velocity"] += impulse

func _resolve_bone_idx(slot: Dictionary) -> int:
	var bone_name: String = slot["bone_name"]
	if bone_name == "" or not is_instance_valid(playermodel):
		return -1
	if _is_left_handed():
		bone_name = _mirror_bone_name(bone_name)
	return playermodel.find_bone(bone_name)

func _find_skeleton_overlay(body : Node3D) -> SkeletonOverlay:
	var origin_node := body.get_node_or_null("SkeletonOverlay")
	if origin_node == null or not (origin_node is SkeletonOverlay):
		return null
	return origin_node
	
func _find_ik_overlay(body : Node3D) -> IKOverlay:
	var origin_node := body.get_node_or_null("IKOverlay")
	if origin_node == null or not (origin_node is IKOverlay):
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

	if child_body.has_meta(ATTACHED_META_KEY):
		var existing_controller = child_body.get_meta(ATTACHED_META_KEY)
		if is_instance_valid(existing_controller):
			push_warning("AttachmentController: '%s' is already attached elsewhere." % child_body.name)
			return false
		child_body.remove_meta(ATTACHED_META_KEY)

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
	var ik_overlay = _find_ik_overlay(child_body)
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
	if (ik_overlay != null and body.ik_controller != null):
		ik_overlay.ik_controller = body.ik_controller
		ik_overlay.active = true
	slot["origin_xform_inv"] = origin_xform.affine_inverse()

	child_body.freeze = true
	child_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	child_body.linear_velocity = Vector3.ZERO
	child_body.angular_velocity = Vector3.ZERO
	if child_body is NetworkRigidbody3D:
		child_body.set_physics_process(false)
	
	add_exceptions(parent_body, child_body)

	if slot["is_hidden"]:
		_set_meshes_and_collisions_enabled(child_body, false)
		slot["temp_shown"] = false

	slot["occupant"] = child_body
	child_body.set_meta(ATTACHED_META_KEY, self)
	
	if (parent_body is RigidBody3D and child_body is RigidBody3D):
		parent_body.mass += child_body.mass
	return true

func add_exceptions(parent_body : RigidBody3D, child_body : Node3D):
	parent_body.add_collision_exception_with(child_body)
	for i in parent_body.find_children("*", "SpringArm3D", true, false):
		i.add_excluded_object(child_body.get_rid())
	for i in parent_body.find_children("*", "ShapeCast3D", true, false):
		i.add_exception(child_body)

func detach(child_body: RigidBody3D) -> void:
	for slot_name in attachment_slots.keys():
		var slot: Dictionary = attachment_slots[slot_name]
		if slot["occupant"] == child_body:
			slot["occupant"] = null
			slot["origin_xform_inv"] = Transform3D.IDENTITY
			if slot["is_hidden"]:
				_set_meshes_and_collisions_enabled(child_body, true)
			slot["temp_shown"] = false
			break
	if child_body.has_meta(ATTACHED_META_KEY) and child_body.get_meta(ATTACHED_META_KEY) == self:
		child_body.remove_meta(ATTACHED_META_KEY)
	child_body.freeze = false
	if child_body is NetworkRigidbody3D:
		child_body.set_physics_process(true)
	
	if is_instance_valid(body):
		body._queue_collision_exception_release(child_body)
		for i in body.find_children("*", "SpringArm3D", true, false):
			i.remove_excluded_object(child_body.get_rid())
		for i in body.find_children("*", "ShapeCast3D", true, false):
			i.remove_exception(child_body)
	var skeleton_overlay = _find_skeleton_overlay(child_body)
	var ik_overlay = _find_ik_overlay(child_body)
	if (skeleton_overlay != null):
		skeleton_overlay.active = false
	if (ik_overlay != null):
		ik_overlay.ik_controller = body.ik_controller
		ik_overlay.active = true
	if (body is RigidBody3D and child_body is RigidBody3D):
		body.mass -= child_body.mass
	if (is_instance_valid(body)):
		var forward := -body.global_basis.z.normalized()
		var up := body.global_basis.y.normalized()
		child_body.global_position = body.global_position + forward * drop_distance + up * drop_height
		child_body.linear_velocity = body.linear_velocity
		child_body.angular_velocity = Vector3.ZERO
		body.allow_grab = body.allow_grab_default
		body.overlay_eulers = Vector3.ZERO

func _on_body_tree_exiting() -> void:
	for slot_name in attachment_slots.keys():
		var slot: Dictionary = attachment_slots[slot_name]
		var occupant: RigidBody3D = slot["occupant"]
		if occupant != null and is_instance_valid(occupant):
			detach(occupant)

func _on_skeleton_updated() -> void:
	var delta := get_physics_process_delta_time()

	for slot_name in attachment_slots.keys():
		var slot: Dictionary = attachment_slots[slot_name]
		var child: RigidBody3D = slot["occupant"]
		if child == null or not is_instance_valid(child):
			continue
		var parent: Node3D = get_parent()
		
		if (parent == null or !parent.is_inside_tree()):
			return

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
		var offset = slot["local_xform_equipped"] if is_equipped else slot["local_xform"]
		if is_equipped:
			bone_idx = -1
		else:
			bone_idx = _resolve_bone_idx(slot)
		if bone_idx != -1 and is_instance_valid(playermodel) and playermodel.is_inside_tree():
			var bone_global_pose: Transform3D = playermodel.get_bone_global_pose(bone_idx)
			target_xform = playermodel.global_transform * bone_global_pose * offset
		elif is_equipped and body != null:
			target_xform = body.shapecast_arms.global_transform * offset
		else:
			target_xform = parent.global_transform * offset

		if is_equipped:
			var sway_accel: Vector3 = (-slot["sway_offset"] * sway_spring_strength) - (slot["relative_velocity"] * sway_spring_damping)
			slot["relative_velocity"] += sway_accel * delta
			slot["sway_offset"] += slot["relative_velocity"] * delta

			var torque_accel: Vector3 = (-slot["sway_angular_offset"] * sway_torque_spring_strength) - (slot["angular_velocity"] * sway_torque_spring_damping)
			slot["angular_velocity"] += torque_accel * delta
			slot["sway_angular_offset"] += slot["angular_velocity"] * delta

			var velocity_sway: Vector3 = Vector3.ZERO
			if body != null:
				var body_local_velocity: Vector3 = body.global_basis.orthonormalized().inverse() * body.synced_linear_velocity
				velocity_sway = -body_local_velocity * sway_velocity_scale

			var sway_basis: Basis = Basis.from_euler(slot["sway_angular_offset"])
			target_xform = target_xform * Transform3D(sway_basis, slot["sway_offset"] + velocity_sway)
		else:
			slot["relative_velocity"] = Vector3.ZERO
			slot["sway_offset"] = Vector3.ZERO
			slot["angular_velocity"] = Vector3.ZERO
			slot["sway_angular_offset"] = Vector3.ZERO

		child.global_transform = target_xform * slot["origin_xform_inv"]
