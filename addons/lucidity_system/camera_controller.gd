extends Node3D
class_name CameraController

@export var cam_spring : SpringArm3D
@export var sens := Vector2(0.5, 0.5)
@export_range(-90.0, 90.0, 0.5, "radians_as_degrees") var min_camera_pitch : float = deg_to_rad(-80.0)
@export_range(-90.0, 90.0, 0.5, "radians_as_degrees") var max_camera_pitch : float = deg_to_rad(80.0)
@export var cam_distance_max := 4.0
@export var cam_distance_min := 0.0
@export var camera_tilt_smoothing : float = 10.0
@export var fp_deadzone : float = 0.05

var target : Node3D
var focus_origin : Node3D
var has_focus_origin : bool = false

var camera_pitch : float = 0.0
var target_angle_horizontal : float = 0.0
var camera_up_dir : Vector3 = Vector3.UP

func set_target(new_target: Node3D) -> void:
	target = new_target
	focus_origin = null
	has_focus_origin = false
	if is_instance_valid(target):
		var origin_node := target.find_child("focus_origin")
		if origin_node is Node3D:
			focus_origin = origin_node
			has_focus_origin = true

func is_first_person() -> bool:
	return is_instance_valid(cam_spring) and cam_spring.spring_length <= fp_deadzone

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		target_angle_horizontal = wrapf(target_angle_horizontal - event.relative.x * get_process_delta_time() * sens.x, -PI, PI)
		var new_pitch = camera_pitch - event.relative.y * get_process_delta_time() * sens.y
		camera_pitch = clampf(new_pitch, min_camera_pitch, max_camera_pitch) if has_focus_origin else new_pitch
	if event is InputEventMouseButton and is_instance_valid(cam_spring):
		if event.is_pressed():
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				cam_spring.spring_length = clampf(cam_spring.spring_length - cam_distance_max / 10, cam_distance_min, cam_distance_max)
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				cam_spring.spring_length = clampf(cam_spring.spring_length + cam_distance_max / 10, cam_distance_min, cam_distance_max)

func _process(delta: float) -> void:
	if not (is_instance_valid(target) and is_inside_tree()):
		return
	if has_focus_origin:
		camera_pitch = clampf(camera_pitch, min_camera_pitch, max_camera_pitch)
	var up_dir := _get_target_up_dir().normalized()
	var upside_down := up_dir.y < 0.0
	var tilt_t : float = 1.0 - exp(-camera_tilt_smoothing * delta)
	camera_up_dir = camera_up_dir.normalized()
	camera_up_dir = _safe_slerp_up(camera_up_dir, up_dir, tilt_t)
	var tilt_basis := _get_tilt_basis(camera_up_dir, upside_down)
	var yaw_basis := Basis(Vector3.UP, target_angle_horizontal)
	var pitch_angle = camera_pitch + (PI if upside_down else 0)
	var pitch_basis := Basis(Vector3.RIGHT, pitch_angle)
	var pivot_position := focus_origin.global_position if has_focus_origin else target.global_position
	global_position = pivot_position
	var flat_basis = yaw_basis * pitch_basis
	global_basis = (tilt_basis * flat_basis)

func _get_target_up_dir() -> Vector3:
	if target is PhysicsPlayerController:
		return (target as PhysicsPlayerController).current_up_dir
	return Vector3.UP

func _get_tilt_basis(up_dir: Vector3, upside_down : bool) -> Basis:
	var axis := Vector3.UP.cross(up_dir)
	var t = abs(Vector3.RIGHT.dot(up_dir))
	if upside_down:
		axis = Vector3.DOWN.cross(up_dir)
	var axis_length := axis.length()
	if axis_length < 0.0001:
		if Vector3.UP.dot(up_dir) < 0.0:
			return Basis(Vector3.RIGHT, PI)
		return Basis.IDENTITY
	axis /= axis_length
	var angle := Vector3.UP.angle_to(up_dir)
	if upside_down:
		angle = Vector3.DOWN.angle_to(up_dir)
	var end_basis = Basis(axis, angle)
	return end_basis

func _safe_slerp_up(from: Vector3, to: Vector3, weight: float) -> Vector3:
	from = from.normalized()
	to = to.normalized()
	var dot := clampf(from.dot(to), -1.0, 1.0)
	if dot > 0.9995:
		return from.lerp(to, weight).normalized()
	if dot < -0.9995:
		var arbitrary := Vector3.RIGHT if abs(from.x) < 0.9 else Vector3.UP
		var axis := from.cross(arbitrary).normalized()
		return from.rotated(axis, PI * weight).normalized()
	var theta := acos(dot) * weight
	var relative := (to - from * dot).normalized()
	return (from * cos(theta) + relative * sin(theta)).normalized()
