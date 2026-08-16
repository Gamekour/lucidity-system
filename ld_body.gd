extends RigidBody3D
class_name PhysicsPlayerController
@export var camera : Camera3D
@export var shapecast : ShapeCast3D
@export var roll_force : float = 100
@export var friction_coefficient : float = 1.0
@export var accel_boost : float = 1000.0
@export var ride_height : float = 1.0
@export var spring_strength : float = 10000.0
@export var spring_damping : float = 1000.0
@export var turn_strength : float = 5000.0
@export var turn_damping : float = 100.0
@export var sens : Vector2 = Vector2(0.6,0.6)
@export var upright_strength : float = 1000.0
@export var upright_damping : float = 100.0
var target_angle_horizontal : float = 0
var camera_pitch : float = 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var gravity_vec : Vector3 = get_gravity()
	var up_dir : Vector3 = _get_up_direction(gravity_vec)

	var input_vector := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var input_3d := Vector3(input_vector.y, 0, input_vector.x)
	input_3d = camera.global_basis * input_3d
	var virtual_torque = input_3d * roll_force
	var target_force = up_dir.cross(virtual_torque) / (shapecast.shape as SphereShape3D).radius

	var slope_normal := up_dir
	if shapecast.is_colliding():
		slope_normal = shapecast.get_collision_normal(0)

	var gravity_magnitude : float = gravity_vec.length()
	var normal_force := mass * gravity_magnitude * slope_normal.dot(up_dir)
	var friction_budget := maxf(normal_force, 0.0) * friction_coefficient

	var flat_velocity := linear_velocity - linear_velocity.project(up_dir)
	var accel = (target_force - (flat_velocity * mass)) * accel_boost
	var force = accel.limit_length(friction_budget)
	apply_force(force)

	var current_yaw := _get_current_yaw(up_dir)
	var look_angle_horizontal : float = wrapf(target_angle_horizontal - current_yaw, -PI, PI)
	var yaw_damping_torque : float = -angular_velocity.dot(up_dir) * turn_damping
	var yaw_torque := up_dir * (look_angle_horizontal * turn_strength + yaw_damping_torque)
	var upright_torque := _get_upright_torque(up_dir)
	apply_torque(yaw_torque + upright_torque)

	if shapecast.is_colliding():
		var target_height_offset = Input.get_axis("crouch", "jump")
		var current_distance : float = shapecast.get_closest_collision_safe_fraction() * abs(shapecast.target_position.y)
		var displacement : float = (ride_height + target_height_offset) - current_distance
		var normal_velocity : float = linear_velocity.dot(slope_normal)
		var spring_magnitude : float = displacement * spring_strength - normal_velocity * spring_damping
		var spring_force : Vector3 = slope_normal * spring_magnitude
		apply_force(spring_force, shapecast.position)

func _get_up_direction(gravity_vec: Vector3) -> Vector3:
	if gravity_vec.length_squared() < 0.0001:
		return Vector3.UP
	return -gravity_vec.normalized()

# Builds a stable (forward, right) reference pair lying in the plane
# perpendicular to up_dir, reducing to world (Z, X) when up_dir == Vector3.UP.
func _get_horizontal_basis(up_dir: Vector3) -> Array:
	var reference := Vector3(0, 0, 1)
	if abs(reference.dot(up_dir)) > 0.98:
		reference = Vector3(1, 0, 0)
	var forward_ref := (reference - up_dir * reference.dot(up_dir)).normalized()
	var right_ref := up_dir.cross(forward_ref).normalized()
	return [forward_ref, right_ref]

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

func _get_upright_torque(up_dir: Vector3) -> Vector3:
	var current_up := global_basis.y
	var axis := current_up.cross(up_dir)
	var axis_length := axis.length()
	if axis_length < 0.0001:
		if current_up.dot(up_dir) < 0.0:
			axis = global_basis.x
			axis_length = 1.0
		else:
			return Vector3.ZERO
	axis /= axis_length
	var tilt_angle := current_up.angle_to(up_dir)
	var tipping_angular_velocity := angular_velocity - angular_velocity.project(current_up)
	return axis * (tilt_angle * upright_strength) - tipping_angular_velocity * upright_damping

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		target_angle_horizontal = wrapf(target_angle_horizontal - event.relative.x * get_process_delta_time() * sens.x, -PI, PI)
		camera_pitch = clampf(camera_pitch - event.relative.y * get_process_delta_time() * sens.y, -PI / 2, PI / 2)

func _process(delta: float) -> void:
	var body_roll := global_basis.get_euler().z
	
	var yaw_basis := Basis(Vector3.UP, target_angle_horizontal)
	var pitch_basis := Basis(Vector3.RIGHT, camera_pitch)
	var roll_basis := Basis(Vector3.FORWARD, 0)
	
	camera.global_basis = yaw_basis * pitch_basis * roll_basis
