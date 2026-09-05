extends Node
class_name IKOverlay

@export var ik_controller: WalkIKController
@export var override_indices: Array[int] = []
@export var override_nodes: Array[Node3D] = []
@export var active: bool = true

func _ready() -> void:
	process_priority = 50

func _process(_delta: float) -> void:
	if not active or ik_controller == null or multiplayer.is_server():
		return

	var count := min(override_indices.size(), override_nodes.size())
	for i in range(count):
		var idx: int = override_indices[i]
		var source: Node3D = override_nodes[i]
		if idx < 0 or idx >= ik_controller.ik_targets.size():
			continue
		if source == null or not is_instance_valid(source):
			continue

		var target := ik_controller.ik_targets[idx]
		target.global_position = source.global_position
		target.global_rotation = source.global_rotation
