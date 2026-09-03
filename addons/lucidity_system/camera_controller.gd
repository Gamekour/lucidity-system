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
var transport_basis : Basis = Basis.IDENTITY
var _transport_initialized : bool = false

func set_target(new_target: Node3D) -> void:
	target = new_target
	focus_origin = null
	has_focus_origin = false
	_transport_initialized = false
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
	var target_up := _get_target_up_dir().normalized()
	var tilt_t : float = 1.0 - exp(-camera_tilt_smoothing * delta)
	_update_transport_basis(target_up, tilt_t)
	var yaw_basis := Basis(Vector3.UP, target_angle_horizontal)
	var pitch_basis := Basis(Vector3.RIGHT, camera_pitch)
	var pivot_position := focus_origin.global_position if has_focus_origin else target.global_position
	global_position = pivot_position
	global_basis = transport_basis * yaw_basis * pitch_basis

func _get_target_up_dir() -> Vector3:
	if target is PhysicsPlayerController:
		return (target as PhysicsPlayerController).current_up_dir
	return Vector3.UP

func _update_transport_basis(target_up: Vector3, t: float) -> void:
	if not _transport_initialized:
		transport_basis = _minimal_rotation(Vector3.UP, target_up)
		camera_up_dir = target_up
		_transport_initialized = true
		return
	var new_up := _safe_slerp_up(camera_up_dir, target_up, t)
	var step_rotation := _minimal_rotation(camera_up_dir, new_up)
	transport_basis = (step_rotation * transport_basis).orthonormalized()
	camera_up_dir = new_up

func _minimal_rotation(from: Vector3, to: Vector3) -> Basis:
	from = from.normalized()
	to = to.normalized()
	var axis := from.cross(to)
	var axis_length := axis.length()
	if axis_length < 0.0001:
		if from.dot(to) < 0.0:
			var arbitrary := Vector3.RIGHT if abs(from.x) < 0.9 else Vector3.UP
			var perp_axis := from.cross(arbitrary).normalized()
			return Basis(perp_axis, PI)
		return Basis.IDENTITY
	axis /= axis_length
	var angle := acos(clampf(from.dot(to), -1.0, 1.0))
	return Basis(axis, angle)

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
