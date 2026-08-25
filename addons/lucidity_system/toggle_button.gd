extends Node3D

@export var target_node : Node3D

func _interact():
	target_node.visible = !target_node.visible
	if (target_node is CollisionObject3D):
		target_node.set_deferred("disabled", !target_node.visible)
