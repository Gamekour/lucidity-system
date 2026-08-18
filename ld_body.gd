extends RigidBody3D
class_name PhysicsPlayerController
@export var camera : Camera3D
@export var cam_spring : SpringArm3D
@export var shapecast : ShapeCast3D
@export var roll_force : float = 100
@export var sprint_multiplier : float = 2.0
@export var friction_coefficient : float = 2.0
@export var acceleration : float = 5.0
@export var air_acceleration : float = 1.0
@export var ride_height_offset : float = -0.1
@export var spring_strength : float = 10000.0
@export var spring_damping : float = 1000.0
@export var turn_strength : float = 5000.0
@export var turn_damping : float = 100.0
@export var sens : Vector2 = Vector2(0.5,0.5)
@export var upright_strength : float = 1000.0
@export var upright_damping : float = 100.0
@export var cam_distance_max : float = 4.0
@export var cam_distance_min : float = -0.06
@export var crouch_speed : float = 0.5
@export var crouch_height : float = 0.5
@export var crawl_height : float = 0.25
@export var lean_strength : float = 1.0
@export var max_lean_angle : float = 0.35
@export var crouch_lean_angle : float = 0.6
@export var air_upright_assist_strength : float = 400.0
@export var air_upright_assist_damping : float = 40.0
@export var jump_height : float = 2.0
@export_range(0.0, PI, 0.01, "radians_as_degrees") var body_turn_max_angle : float = deg_to_rad(70.0)
@export var body_turn_input_deadzone : float = 0.15
@export var camera_tilt_smoothing : float = 10.0
@export var body_turn_sideways_deadzone: float = deg_to_rad(15.0)
@export_range(-90.0, 90.0, 0.5, "radians_as_degrees") var min_camera_pitch : float = deg_to_rad(-85.0)
@export_range(-90.0, 90.0, 0.5, "radians_as_degrees") var max_camera_pitch : float = deg_to_rad(85.0)

var stance_height : float = 0
var target_angle_horizontal : float = 0
var camera_pitch : float = 0.0
var sprinting := false

var roll_force_scale : float = 1.0
var sprint_multiplier_scale : float = 1.0
var friction_coefficient_scale : float = 1.0
var acceleration_scale : float = 1.0
var air_acceleration_scale : float = 1.0
var spring_strength_scale : float = 1.0
var spring_damping_scale : float = 1.0
var top_speed_stance_height_scale : float = 1.0
var jump_height_scale : float = 1.0
var stance_height_scale : float = 1.0

var current_up_dir : Vector3 = Vector3.UP
var camera_up_dir : Vector3 = Vector3.UP

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(_delta: float) -> void:
	
	var gravity_vec : Vector3 = get_gravity()
	var up_dir : Vector3 = _get_up_direction(gravity_vec).normalized()
	current_up_dir = up_dir

	var input_vector := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var input_3d := _get_camera_relative_input(up_dir, input_vector)
	var max_speed = max(lerpf(crouch_speed * roll_force, roll_force * sprint_multiplier * sprint_multiplier_scale, stance_height), 0)
	var speed = min(roll_force * roll_force_scale * (sprint_multiplier * sprint_multiplier_scale if sprinting and shapecast.is_colliding() else 1.0), max_speed)
	var virtual_torque = input_3d * speed
	var target_force = up_dir.cross(virtual_torque) / (shapecast.shape as SphereShape3D).radius

	var slope_normal := up_dir
	var grounded := shapecast.is_colliding()
	if grounded:
		slope_normal = shapecast.get_collision_normal(0)

	var gravity_magnitude : float = gravity_vec.length()
	var normal_force := mass * gravity_magnitude * slope_normal.dot(up_dir)
	var friction_budget := maxf(normal_force, 0.0) * friction_coefficient * friction_coefficient_scale

	var flat_velocity := linear_velocity - linear_velocity.project(up_dir)
	var accel = (target_force - (flat_velocity * mass)) * (acceleration * acceleration_scale if grounded else air_acceleration * air_acceleration_scale)
	var force = accel.limit_length(friction_budget)
	apply_force(force)

	var current_yaw := _get_current_yaw(up_dir)
	var body_target_angle := _get_body_target_angle(input_vector)
	var look_angle_horizontal : float = wrapf(body_target_angle - current_yaw, -PI, PI)
	var yaw_damping_torque : float = -angular_velocity.dot(up_dir) * turn_damping
	var yaw_torque := up_dir * (look_angle_horizontal * turn_strength + yaw_damping_torque)
	var lean_input : Vector3 = flat_velocity / maxf(friction_budget, 0.0001)

	var upright_torque : Vector3
	if grounded:
		upright_torque = _get_upright_torque(up_dir, lean_input, upright_strength, upright_damping)
	else:
		upright_torque = _get_air_upright_torque(up_dir)

	apply_torque(yaw_torque + upright_torque)

	if grounded:
		stance_height = crawl_height if Input.is_action_pressed("crawl") else crouch_height if Input.is_action_pressed("crouch") else jump_height * jump_height_scale if Input.is_action_pressed("jump") else 1.0
		stance_height *= stance_height_scale
		var current_distance : float = shapecast.get_closest_collision_safe_fraction() * abs(shapecast.target_position.y)
		var ride_height = abs(shapecast.target_position.y) + ride_height_offset
		var displacement : float = (stance_height * ride_height) - current_distance
		var normal_velocity : float = linear_velocity.dot(slope_normal)
		var spring_magnitude : float = displacement * spring_strength * spring_strength_scale - normal_velocity * spring_damping * spring_damping_scale
		var spring_force : Vector3 = slope_normal * spring_magnitude
		apply_force(spring_force, shapecast.position)

func _process(delta: float) -> void:
	sprinting = Input.is_action_pressed("sprint")
	var tilt_t : float = 1.0 - exp(-camera_tilt_smoothing * delta)
	camera_up_dir = camera_up_dir.normalized()
	current_up_dir = current_up_dir.normalized()
	camera_up_dir = _safe_slerp_up(camera_up_dir, current_up_dir, tilt_t)
	var tilt_basis := _get_tilt_basis(camera_up_dir)
	var yaw_basis := Basis(Vector3.UP, target_angle_horizontal)
	var pitch_basis := Basis(Vector3.RIGHT, camera_pitch)
	cam_spring.global_basis = tilt_basis * yaw_basis * pitch_basis

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		target_angle_horizontal = wrapf(target_angle_horizontal - event.relative.x * get_process_delta_time() * sens.x, -PI, PI)
		camera_pitch = clampf(camera_pitch - event.relative.y * get_process_delta_time() * sens.y, min_camera_pitch, max_camera_pitch)
	if event is InputEventMouseButton:
		if (event.is_pressed()):
			if (event.button_index == MOUSE_BUTTON_WHEEL_UP):
				cam_spring.spring_length = clampf(cam_spring.spring_length - cam_distance_max / 10, cam_distance_min, cam_distance_max)
			if (event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
				cam_spring.spring_length = clampf(cam_spring.spring_length + cam_distance_max / 10, cam_distance_min, cam_distance_max)

func _safe_slerp_up(from: Vector3, to: Vector3, weight: float) -> Vector3:
	from = from.normalized()
	to = to.normalized()
	var dot := clampf(from.dot(to), -1.0, 1.0)
	# Near-parallel: cross product is too small to give a reliable axis, so lerp instead.
	if dot > 0.9995:
		return from.lerp(to, weight).normalized()
	# Near-opposite: pick any axis perpendicular to `from` to rotate around.
	if dot < -0.9995:
		var arbitrary := Vector3.RIGHT if abs(from.x) < 0.9 else Vector3.UP
		var axis := from.cross(arbitrary).normalized()
		return from.rotated(axis, PI * weight).normalized()
	var theta := acos(dot) * weight
	var relative := (to - from * dot).normalized()
	return (from * cos(theta) + relative * sin(theta)).normalized()

func _get_up_direction(gravity_vec: Vector3) -> Vector3:
	if gravity_vec.length_squared() < 0.0001:
		return Vector3.UP
	return -gravity_vec.normalized()

func _get_horizontal_basis(up_dir: Vector3) -> Array:
	var tilt_basis := _get_tilt_basis(up_dir)
	var forward_ref := tilt_basis.z
	var right_ref := tilt_basis.x
	return [forward_ref, right_ref]

func _get_camera_relative_axes(up_dir: Vector3) -> Array:
	var cam_forward := -camera.global_basis.z
	var flat_forward := cam_forward - up_dir * cam_forward.dot(up_dir)
	if flat_forward.length_squared() < 0.0001:
		var cam_local_up := camera.global_basis.y
		flat_forward = cam_local_up - up_dir * cam_local_up.dot(up_dir)
	flat_forward = flat_forward.normalized()
	var flat_right := flat_forward.cross(up_dir).normalized()
	return [flat_forward, flat_right]

func _get_camera_relative_input(up_dir: Vector3, input_vector: Vector2) -> Vector3:
	var axes := _get_camera_relative_axes(up_dir)
	var flat_forward : Vector3 = axes[0]
	var flat_right : Vector3 = axes[1]
	return flat_right * input_vector.y - flat_forward * input_vector.x

func _get_current_yaw(up_dir: Vector3) -> float:
	var refs := _get_horizontal_basis(up_dir)
	var forward_ref : Vector3 = refs[0]
	var right_ref : Vector3 = refs[1]
	var forward := global_basis.z
	if abs(forward.dot(up_dir)) < 0.98:
		var projected := (forward - up_dir * forward.dot(up_dir)).normalized()
		return atan2(projected.dot(right_ref), projected.dot(forward_ref))
	var right := global_basis.x
	var projected_right := (right - up_dir * right.dot(up_dir)).normalized()
	return atan2(projected_right.dot(right_ref), projected_right.dot(forward_ref)) - PI / 2.0

func _get_body_target_angle(input_vector: Vector2) -> float:
	if input_vector.length() < body_turn_input_deadzone:
		return target_angle_horizontal
	
	var move_yaw_offset := atan2(input_vector.x, input_vector.y)
	
	# Check "how sideways" using the raw angle, before the backward-fold below.
	# Raw angle is symmetric: PI/2 = right, -PI/2 = left, 0 = forward, ±PI = backward.
	if absf(absf(move_yaw_offset) - (PI / 2.0)) < body_turn_sideways_deadzone:
		return target_angle_horizontal
	
	if input_vector.y < 0.0:
		if (move_yaw_offset < 0.0):
			move_yaw_offset += PI
		else:
			move_yaw_offset -= PI
	
	return wrapf(target_angle_horizontal - move_yaw_offset, -PI, PI)

func _get_lean_target_up(up_dir: Vector3, lean_input: Vector3) -> Vector3:
	var flat_lean := lean_input - lean_input.project(up_dir)
	var lean_magnitude := clampf(flat_lean.length() * lean_strength, 0.0, 1.0)
	if lean_magnitude < 0.0001:
		return up_dir
	var lean_dir := flat_lean.normalized()
	var lean_axis := up_dir.cross(lean_dir).normalized()
	var lean_angle := lean_magnitude * max_lean_angle
	return up_dir.rotated(lean_axis, lean_angle)

func _get_crouch_lean_factor() -> float:
	return clampf(inverse_lerp(1, crawl_height, stance_height), 0.0, 1.0)

func _get_upright_torque(up_dir: Vector3, lean_input: Vector3, strength: float, damping: float) -> Vector3:
	var target_up := _get_lean_target_up(up_dir, lean_input)

	var crouch_factor := _get_crouch_lean_factor()
	if crouch_factor > 0.0001:
		var axes := _get_camera_relative_axes(up_dir)
		var flat_forward : Vector3 = axes[0]
		var lean_axis := flat_forward.cross(up_dir)
		var lean_axis_length := lean_axis.length()
		if lean_axis_length > 0.0001:
			lean_axis /= lean_axis_length
			target_up = target_up.rotated(lean_axis, crouch_factor * -crouch_lean_angle)

	return _upright_torque_towards(up_dir, target_up, strength, damping)

func _get_air_upright_torque(up_dir: Vector3) -> Vector3:
	if air_upright_assist_strength <= 0.0:
		return Vector3.ZERO
	return _upright_torque_towards(up_dir, up_dir, air_upright_assist_strength, air_upright_assist_damping)

func _upright_torque_towards(up_dir: Vector3, target_up: Vector3, strength: float, damping: float) -> Vector3:
	var current_up := global_basis.y
	var axis := current_up.cross(target_up)
	var axis_length := axis.length()
	if axis_length < 0.0001:
		if current_up.dot(target_up) < 0.0:
			axis = global_basis.x
			axis_length = 1.0
		else:
			return Vector3.ZERO
	axis /= axis_length
	var tilt_angle := current_up.angle_to(target_up)
	var tipping_angular_velocity := angular_velocity - angular_velocity.project(current_up)
	return axis * (tilt_angle * strength) - tipping_angular_velocity * damping

func _get_tilt_basis(up_dir: Vector3) -> Basis:
	var axis := Vector3.UP.cross(up_dir)
	var axis_length := axis.length()
	if axis_length < 0.0001:
		if Vector3.UP.dot(up_dir) < 0.0:
			return Basis(Vector3.RIGHT, PI)
		return Basis.IDENTITY
	axis /= axis_length
	var angle := Vector3.UP.angle_to(up_dir)
	return Basis(axis, angle)
