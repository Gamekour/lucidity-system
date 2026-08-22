extends Node
class_name AttachmentController
## Central manager — one _physics_process call handles ALL attachments,
## instead of N nodes each running their own _physics_process.

var attachments: Array[Dictionary] = [] 
# each entry: { "child": RigidBody3D, "parent": Node3D, "local_xform": Transform3D }

func attach(child_body: RigidBody3D, parent_body: Node3D) -> void:
	child_body.get_parent().remove_child(child_body)
	parent_body.add_child(child_body)
	child_body.transform = Transform3D.IDENTITY
	child_body.freeze = true
	child_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	child_body.linear_velocity = Vector3.ZERO
	child_body.angular_velocity = Vector3.ZERO
	child_body.set_collision_layer_value(1, false)

	attachments.append({
		"child": child_body,
		"parent": parent_body,
		"local_xform": Transform3D.IDENTITY, # zeroed offset per your original spec
	})

func detach(child_body: RigidBody3D) -> void:
	for i in attachments.size():
		if attachments[i]["child"] == child_body:
			attachments.remove_at(i)
			break
	child_body.freeze = false
	child_body.set_collision_layer_value(1, true)

func _physics_process(_delta: float) -> void:
	for entry in attachments:
		var child: RigidBody3D = entry["child"]
		var parent: Node3D = entry["parent"]
		if is_instance_valid(child) and is_instance_valid(parent):
			child.global_transform = parent.global_transform * entry["local_xform"]
