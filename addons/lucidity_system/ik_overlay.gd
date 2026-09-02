extends Node
class_name IKOverlay

@export var ik_controller: WalkIKController
@export var override_indices: Array[int] = []
@export var override_nodes: Array[Node3D] = []
@export var active: bool = true

func _ready() -> void:
	process_priority = 50

func _process(_delta: float) -> void:
	if not active or ik_controller == null:
		return

	var count := min(override_indices.size(), override_nodes.size())
	for i in range(count):
		var idx: int = override_indices[i]
		var source: Node3D = override_nodes[i]
		if idx < 0 or idx >= ik_controller.ik_springs.size():
			continue
		if source == null or not is_instance_valid(source):
			continue

		var spring := ik_controller.ik_springs[idx] as SpringArm3D
		spring.look_at(source.global_position)
		spring.spring_length = 0.0
