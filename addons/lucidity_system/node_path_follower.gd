extends PathFollow3D
class_name NodePathFollower3D

@export var copy_rotation: bool = false

var _waypoint_offsets: Array[float] = []
var _waypoint_rotations: Array[Quaternion] = []

func _ready() -> void:
	call_deferred("rebuild_waypoint_rotations")

func _process(_delta: float) -> void:
	if not copy_rotation or _waypoint_rotations.size() < 2:
		return
	_apply_slerped_rotation()

func rebuild_waypoint_rotations() -> void:
	_waypoint_offsets.clear()
	_waypoint_rotations.clear()

	var path := get_parent() as Path3D
	if path == null or path.curve == null:
		return

	var nodes := _gather_waypoint_nodes(path)
	if nodes.size() < 2:
		return

	for node in nodes:
		var local_pos: Vector3 = path.to_local(node.global_position)
		_waypoint_offsets.append(path.curve.get_closest_offset(local_pos))
		_waypoint_rotations.append(node.global_basis.get_rotation_quaternion())
		print(node)

	if path is NodePathBuilder3D and (path as NodePathBuilder3D).closed_loop:
		_waypoint_offsets.append(path.curve.get_baked_length())
		_waypoint_rotations.append(_waypoint_rotations[0])

func _gather_waypoint_nodes(path: Path3D) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if path is NodePathBuilder3D and not (path as NodePathBuilder3D).waypoints.is_empty():
		for node_path in (path as NodePathBuilder3D).waypoints:
			var node := path.get_node_or_null(node_path)
			if node is Node3D:
				result.append(node)
	else:
		for child in path.get_children():
			if child is Node3D and child != self:
				result.append(child)
	return result

func _apply_slerped_rotation() -> void:
	var offset: float = progress

	if offset <= _waypoint_offsets[0]:
		global_basis = Basis(_waypoint_rotations[0])
		return

	var last_idx := _waypoint_offsets.size() - 1
	if offset >= _waypoint_offsets[last_idx]:
		global_basis = Basis(_waypoint_rotations[last_idx])
		return

	for i in range(last_idx):
		var a: float = _waypoint_offsets[i]
		var b: float = _waypoint_offsets[i + 1]
		if offset <= b:
			var t: float = 0.0 if is_equal_approx(a, b) else (offset - a) / (b - a)
			basis = Basis(_waypoint_rotations[i].slerp(_waypoint_rotations[i + 1], t))
			return
