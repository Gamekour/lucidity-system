extends Path3D
class_name NodePathBuilder3D

## Builds this Path3D's Curve3D from a list of Node3D "waypoints".
## Assign nodes in the inspector (as NodePaths) or just add Node3D
## children under this node and leave the array empty to auto-detect them.

## Explicit list of waypoints to build the curve from.
## If left empty, all direct Node3D children of this Path3D are used instead.
@export var waypoints: Array[NodePath] = []

## If true, tangents (in/out handles) are auto-computed from neighboring
## points so the curve is a smooth Catmull-Rom-ish spline.
@export var smooth_tangents: bool = true

## Multiplier applied to auto-computed tangent lengths (higher = looser curve).
@export_range(0.0, 2.0, 0.05) var tangent_strength: float = 0.25

## Whether the path should loop back to the first point.
@export var closed_loop: bool = false

## Rebuild automatically whenever the scene is ready.
@export var build_on_ready: bool = true

func _ready() -> void:
	if build_on_ready:
		build_curve()


## Public entry point: gathers points and (re)builds the Curve3D resource.
func build_curve() -> void:
	var points: Array[Vector3] = _gather_points()

	if points.is_empty():
		push_warning("NodePathBuilder3D: no waypoints found to build a curve from.")
		return

	var new_curve := Curve3D.new()

	for i in points.size():
		var point: Vector3 = points[i]
		var tangent_in := Vector3.ZERO
		var tangent_out := Vector3.ZERO

		if smooth_tangents:
			var prev: Vector3 = points[_wrap_index(i - 1, points.size())]
			var next: Vector3 = points[_wrap_index(i + 1, points.size())]

			var is_edge := not closed_loop and (i == 0 or i == points.size() - 1)
			if not is_edge:
				var dir: Vector3 = (next - prev) * tangent_strength
				tangent_in = -dir
				tangent_out = dir

		new_curve.add_point(point, tangent_in, tangent_out)

	if closed_loop and points.size() > 1:
		# Curve3D doesn't have a native "closed" flag pre-4.3, so we
		# manually add a final point back at the start to close the loop.
		var first: Vector3 = points[0]
		var tangent_out := Vector3.ZERO
		if smooth_tangents:
			var prev: Vector3 = points[points.size() - 1]
			var next: Vector3 = points[1] if points.size() > 1 else points[0]
			tangent_out = (next - prev) * tangent_strength
		new_curve.add_point(first, -tangent_out, tangent_out)

	curve = new_curve


## Collects world->local positions of all configured waypoints, in order.
func _gather_points() -> Array[Vector3]:
	var result: Array[Vector3] = []

	if waypoints.is_empty():
		# Fallback: use direct Node3D children as the waypoint list.
		for child in get_children():
			if child is Node3D:
				result.append(to_local(child.global_position))
	else:
		for path in waypoints:
			var node := get_node_or_null(path)
			if node and node is Node3D:
				result.append(to_local((node as Node3D).global_position))
			else:
				push_warning("NodePathBuilder3D: could not resolve waypoint '%s'." % path)

	return result


func _wrap_index(i: int, count: int) -> int:
	return ((i % count) + count) % count
