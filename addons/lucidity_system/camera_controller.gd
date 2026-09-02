extends Node3D
class_name CameraController

@export var cam_spring : SpringArm3D
@export var sens := Vector2(0.5, 0.5)
@export_range(-90.0, 90.0, 0.5, "radians_as_degrees") var min_camera_pitch : float = deg_to_rad(-80.0)
@export_range(-90.0, 90.0, 0.5, "radians_as_degrees") var max_camera_pitch : float = deg_to_rad(80.0)
@export var cam_distance_max := 4.0
@export var cam_distance_min := 0.0
@export var fp_deadzone : float = 0.05

var target : Node3D
var focus_origin : Node3D
var has_focus_origin : bool = false

var camera_pitch : float = 0.0
var target_angle_horizontal : float = 0.0

var _last_target_yaw : float = 0.0
var _has_last_target_yaw : bool = false

func set_target(new_target: Node3D) -> void:
	target = new_target
	focus_origin = null
	has_focus_origin = false
	_has_last_target_yaw = false
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
	var target_yaw := _get_target_yaw(up_dir)
	if _has_last_target_yaw:
		var yaw_delta := wrapf(target_yaw - _last_target_yaw, -PI, PI)
		target_angle_horizontal = wrapf(target_angle_horizontal - yaw_delta, -PI, PI)
	_last_target_yaw = target_yaw
	_has_last_target_yaw = true

	var yaw_offset_basis := Basis(Vector3.UP, target_angle_horizontal)
	var pitch_offset_basis := Basis(Vector3.RIGHT, camera_pitch)
	var pivot_position := focus_origin.global_position if has_focus_origin else target.global_position
	global_position = pivot_position
	global_basis = target.global_basis.orthonormalized() * yaw_offset_basis * pitch_offset_basis

func _get_target_up_dir() -> Vector3:
	if target is PhysicsPlayerController:
		return (target as PhysicsPlayerController).current_up_dir
	return Vector3.UP

func _get_target_yaw(up_dir: Vector3) -> float:
	var q := target.global_basis.orthonormalized().get_rotation_quaternion()
	var qv := Vector3(q.x, q.y, q.z)
	var proj := qv.dot(up_dir)
	return wrapf(2.0 * atan2(proj, q.w), -PI, PI)
