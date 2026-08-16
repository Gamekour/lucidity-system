extends RigidBody3D
class_name PhysicsPlayerController
@export var camera : Camera3D
@export var cam_spring : SpringArm3D
@export var shapecast : ShapeCast3D
@export var roll_force : float = 100
@export var sprint_multiplier : float = 2
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
@export var cam_distance_max : float = 2
@export var top_speed_by_stance_height : float = 1
@export var crouch_height : float = 0.5
var stance_height : float = 0
var target_angle_horizontal : float = 0
var camera_pitch : float = 0.0
var sprinting := false

# The actual "up" implied by physics gravity this physics frame. Used for
# movement, springs, and torques - always instantaneous/accurate.
var current_up_dir : Vector3 = Vector3.UP
# A smoothed version of current_up_dir used purely for camera presentation,
# so a sudden gravity flip tilts the view over time instead of snapping.
var camera_up_dir : Vector3 = Vector3.UP

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var gravity_vec : Vector3 = get_gravity()
	var up_dir : Vector3 = _get_up_direction(gravity_vec).normalized()
	current_up_dir = up_dir

	var input_vector := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var input_3d := _get_camera_relative_input(up_dir, input_vector)
	var speed = min(roll_force * (sprint_multiplier if sprinting else 1), stance_height * top_speed_by_stance_height * roll_force * sprint_multiplier)
	var virtual_torque = input_3d * speed
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
		stance_height = max(Input.get_axis("crouch", "jump") + 1, crouch_height) * ride_height
		var current_distance : float = shapecast.get_closest_collision_safe_fraction() * abs(shapecast.target_position.y)
		var displacement : float = stance_height - current_distance
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

# Flattens the camera's actual look direction onto the plane perpendicular
# to up_dir, so movement input is always relative to where the camera is
# really pointing - including when the camera is pitched, and when it has
# been tilted upside-down/sideways because up_dir no longer matches world
# Vector3.UP. Returns [flat_forward, flat_right], both unit length and
# orthogonal to up_dir.
func _get_camera_relative_axes(up_dir: Vector3) -> Array:
	var cam_forward := -camera.global_basis.z
	var flat_forward := cam_forward - up_dir * cam_forward.dot(up_dir)
	if flat_forward.length_squared() < 0.0001:
		# Camera is looking almost straight along up_dir (i.e. straight "up"
		# or "down" relative to gravity). Fall back to the camera's local up
		# axis (screen-up) to still derive a sensible forward direction.
		var cam_local_up := camera.global_basis.y
		flat_forward = cam_local_up - up_dir * cam_local_up.dot(up_dir)
	flat_forward = flat_forward.normalized()
	var flat_right := flat_forward.cross(up_dir).normalized()
	return [flat_forward, flat_right]

# Converts raw WASD-style input into a world-space direction relative to
# where the camera is actually looking, flattened onto the plane
# perpendicular to up_dir. This preserves the original relationship this
# controller relies on (input_3d gets crossed with up_dir downstream to
# turn it into a linear force), it just sources the forward/right axes from
# the camera's real orientation instead of assuming the camera basis is
# already aligned with up_dir.
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

# Returns the basis that rotates world Vector3.UP onto up_dir by the
# shortest arc. This is used to "tilt" the whole camera reference frame
# (yaw + pitch axes included) so that looking limits, horizon, and roll
# all stay relative to the current gravity direction instead of world up.
func _get_tilt_basis(up_dir: Vector3) -> Basis:
	var axis := Vector3.UP.cross(up_dir)
	var axis_length := axis.length()
	if axis_length < 0.0001:
		if Vector3.UP.dot(up_dir) < 0.0:
			# up_dir is exactly opposite world up - pick any perpendicular axis.
			return Basis(Vector3.RIGHT, PI)
		return Basis.IDENTITY
	axis /= axis_length
	var angle := Vector3.UP.angle_to(up_dir)
	return Basis(axis, angle)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		target_angle_horizontal = wrapf(target_angle_horizontal - event.relative.x * get_process_delta_time() * sens.x, -PI, PI)
		camera_pitch = wrapf(camera_pitch - event.relative.y * get_process_delta_time() * sens.y, -PI, PI)
	if event is InputEventMouseButton:
		if (event.is_pressed()):
			if (event.button_index == MOUSE_BUTTON_WHEEL_UP):
				cam_spring.spring_length = clampf(cam_spring.spring_length - 0.1, 0, cam_distance_max)
			if (event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
				cam_spring.spring_length = clampf(cam_spring.spring_length + 0.1, 0, cam_distance_max)

func _process(delta: float) -> void:
	sprinting = Input.is_action_pressed("sprint")
	camera_up_dir = current_up_dir
	# Tilt the whole yaw/pitch frame so it's built relative to the current
	# up direction instead of always world Vector3.UP. Without this the
	# camera (and therefore movement, since it reads the camera's basis)
	# would never actually reorient when gravity flips.
	var tilt_basis := _get_tilt_basis(camera_up_dir)
	var yaw_basis := Basis(Vector3.UP, target_angle_horizontal)
	var pitch_basis := Basis(Vector3.RIGHT, camera_pitch)
	cam_spring.global_basis = tilt_basis * yaw_basis * pitch_basis
