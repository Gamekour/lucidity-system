extends RigidBody3D
class_name PhysicsPlayerController

@export var camera : Camera3D
@export var cam_spring : SpringArm3D
@export var shapecast_legs : ShapeCast3D
@export var shapecast_arms : ShapeCast3D
@export var attach_controller : AttachmentController
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
@export var slope_correction : float = 1.0
@export var slope_correction_damping : float = 0.0
@export var slope_stance_height_scale : float = 0.5
@export var speed_stance_stop : float = 0.6
@export var apply_reaction_forces : bool = true
@export var apply_reaction_torque : bool = false
@export var grab_strength_min : float = 100
@export var grab_strength_max : float = 1000
@export var grab_scale_max_mass : float = 69
@export var grab_distance : float = 1.0
@export var grab_damp_min : float = 50.0
@export var grab_damp_max : float = 100.0
@export var grab_max_angular_velocity : float = 10.0
@export var grab_angular_damp : float = 5.0

# --- Ledge detection (non-rigidbody grabs) ---
@export_group("Ledge Detection")
@export var ledge_probe_steps : int = 6
@export var ledge_step_height : float = 0.15
@export var ledge_probe_depth : float = 0.35
@export var ledge_surface_margin : float = 0.05
@export_range(0.0, 90.0, 0.5, "radians_as_degrees") var ledge_max_surface_angle : float = deg_to_rad(45.0)

var grabbed_col : Node3D
var grab_offset : Vector3 = Vector3.ZERO
var relative_velocity : Vector3 = Vector3.ZERO
var stance_height : float = 0
var target_angle_horizontal : float = 0
var camera_pitch : float = 0.0
var sprinting := false
var crouch_jump := false
var grounded := false
var trying_to_grab := false

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
var current_dot : float = 0.0

var last_floor_offset := Vector3.ZERO
var last_floor_point := Vector3.ZERO
var last_floor_node : Node3D

var floor_rigidbody : RigidBody3D = null
var floor_contact_point : Vector3 = Vector3.ZERO

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var gravity_vec : Vector3 = get_gravity()
	var up_dir : Vector3 = _get_up_direction(gravity_vec).normalized()
	current_up_dir = up_dir
	
	var base_right := up_dir.cross(global_basis.z).normalized()
	var shapecast_basis := Basis(base_right, up_dir, global_basis.z.normalized())
	shapecast_legs.global_basis = shapecast_basis.orthonormalized()

	var input_vector := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var input_3d := _get_camera_relative_input(up_dir, input_vector)
	var max_speed = max(lerpf(crouch_speed * roll_force, roll_force * sprint_multiplier * sprint_multiplier_scale, min(stance_height / speed_stance_stop, 1)), 0)
	crouch_jump = Input.is_action_pressed("jump") && Input.is_action_pressed("crouch")
	
	var slope_normal := up_dir
	var floor_velocity := Vector3.ZERO
	
	grounded = shapecast_legs.is_colliding()
	if (crouch_jump):
		grounded = grounded && shapecast_legs.get_closest_collision_safe_fraction() <= 0.5
		
	if grounded:
		slope_normal = shapecast_legs.get_collision_normal(0)
		current_dot = up_dir.dot(slope_normal)
		
		var current_floor_node = shapecast_legs.get_collider(0)
		var current_floor_point = shapecast_legs.get_collision_point(0)
		
		# Cache the contact rigidbody + point for the reaction force applied
		# at the end of this function.
		floor_contact_point = current_floor_point
		floor_rigidbody = current_floor_node if current_floor_node is RigidBody3D else null
		
		if current_floor_node == last_floor_node:
			var floor_movement = (last_floor_node as Node3D).to_global(last_floor_offset) - last_floor_point
			floor_velocity = floor_movement / delta
			
		last_floor_node = current_floor_node
		last_floor_point = current_floor_point
		last_floor_offset = current_floor_node.to_local(current_floor_point)
	else:
		last_floor_node = null
		floor_rigidbody = null

	var speed = min(roll_force * roll_force_scale * (sprint_multiplier * sprint_multiplier_scale if (sprinting || crouch_jump) and shapecast_legs.is_colliding() else 1.0), max_speed)
	var virtual_torque = input_3d * speed
	var target_force = up_dir.cross(virtual_torque) / (shapecast_legs.shape as SphereShape3D).radius

	var gravity_magnitude : float = gravity_vec.length()
	var normal_force := mass * gravity_magnitude * slope_normal.dot(up_dir)
	var friction_budget := maxf(normal_force, 0.0) * friction_coefficient * friction_coefficient_scale

	relative_velocity = linear_velocity - floor_velocity
	var flat_velocity := relative_velocity - relative_velocity.project(up_dir)
	var gravity_tangent := gravity_vec - slope_normal * gravity_vec.dot(slope_normal)

	var slope_correction_force := gravity_tangent * mass * slope_correction
	var gravity_tangent_length := gravity_tangent.length()
	if gravity_tangent_length > 0.0001:
		var gravity_tangent_dir := gravity_tangent / gravity_tangent_length
		var velocity_along_slope := flat_velocity.dot(gravity_tangent_dir)
		slope_correction_force += gravity_tangent_dir * velocity_along_slope * mass * slope_correction_damping * (1 - current_dot)

	var accel : Vector3
	if grounded:
		accel = (target_force - (flat_velocity * mass) - slope_correction_force) * (acceleration * acceleration_scale) * (sprint_multiplier * sprint_multiplier_scale if sprinting || crouch_jump else 1)
	else:
		accel = _get_air_accel(target_force, flat_velocity, air_acceleration * air_acceleration_scale)
	var force = accel.limit_length(friction_budget)

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

	var total_torque := yaw_torque + upright_torque
	apply_torque(total_torque)
	
	stance_height = jump_height * jump_height_scale if Input.is_action_pressed("jump") else crawl_height if Input.is_action_pressed("crawl") else crouch_height if Input.is_action_pressed("crouch") else 1.0
	stance_height *= stance_height_scale
	stance_height -= (1 - current_dot) * slope_stance_height_scale
	
	if grounded:
		var current_distance : float = shapecast_legs.get_closest_collision_safe_fraction() * abs(shapecast_legs.target_position.y)
		var ride_height = abs(shapecast_legs.target_position.y) + ride_height_offset
		var displacement : float = (stance_height * ride_height) - current_distance
		
		var normal_velocity : float = relative_velocity.dot(slope_normal)
		var spring_magnitude : float = displacement * spring_strength * spring_strength_scale - normal_velocity * spring_damping * spring_damping_scale
		var spring_force : Vector3 = slope_normal * spring_magnitude
		force += spring_force
		
	apply_force(force, shapecast_legs.position)

	if grounded and apply_reaction_forces and floor_rigidbody != null and is_instance_valid(floor_rigidbody):
		var offset := floor_contact_point - floor_rigidbody.global_position
		floor_rigidbody.apply_force(-force, offset)
		if apply_reaction_torque:
			floor_rigidbody.apply_torque(-total_torque)
	
	if (grabbed_col == null && trying_to_grab):
		arm_cast()
	arm_logic()

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
	if event.is_action_pressed("grab"):
		trying_to_grab = true
	if event.is_action_released("grab"):
		grabbed_col = null
		trying_to_grab = false
	if event.is_action_pressed("attach"):
		if (grabbed_col is RigidBody3D):
			attach_controller.attach(grabbed_col, self, "RightLowerArm")
			grabbed_col = null

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
	
	if absf(absf(move_yaw_offset) - (PI / 2.0)) < body_turn_sideways_deadzone:
		return target_angle_horizontal
	
	if input_vector.y < 0.0:
		if (move_yaw_offset < 0.0):
			move_yaw_offset += PI
		else:
			move_yaw_offset -= PI
	
	return wrapf(target_angle_horizontal - move_yaw_offset, -PI, PI)

func _get_air_accel(target_force: Vector3, flat_velocity: Vector3, accel_strength: float) -> Vector3:
	var wish_velocity := target_force / mass
	var wishspeed := wish_velocity.length()
	if wishspeed < 0.0001 or accel_strength <= 0.0:
		return Vector3.ZERO
	var wishdir := wish_velocity / wishspeed

	var current_speed := flat_velocity.dot(wishdir)
	var add_speed := wishspeed - current_speed
	if add_speed <= 0.0:
		return Vector3.ZERO

	return wishdir * (add_speed * mass * accel_strength)

func _get_lean_target_up(up_dir: Vector3, lean_input: Vector3) -> Vector3:
	var flat_lean := lean_input - lean_input.project(up_dir)
	var lean_magnitude := clampf(flat_lean.length() * lean_strength * (2 if crouch_jump else 1), 0.0, 1.0)
	if lean_magnitude < 0.0001:
		return up_dir
	var lean_dir := flat_lean.normalized()
	var lean_axis := up_dir.cross(lean_dir).normalized()
	var lean_angle := lean_magnitude * max_lean_angle
	return up_dir.rotated(lean_axis, lean_angle)

func _get_crouch_lean_factor() -> float:
	return clampf(lerpf(max_lean_angle, 0, shapecast_legs.get_closest_collision_safe_fraction()) * 2, 0.0, 1.0)

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

func arm_cast() -> void:
	if not shapecast_arms.is_colliding():
		return

	var collider = shapecast_arms.get_collider(0)

	# Rigidbodies are always grabbed directly at the initial hit - they're the
	# thing being picked up, not a surface to climb.
	if collider is RigidBody3D:
		grabbed_col = collider
		grab_offset = collider.to_local(shapecast_arms.get_collision_point(0))
		trying_to_grab = false
		return

	# Anything else (static/kinematic geometry) is treated as a potential
	# climbable face: search upward from the initial hit for a ledge.
	var hit_point := shapecast_arms.get_collision_point(0)
	var hit_normal := shapecast_arms.get_collision_normal(0)
	var ledge := _find_ledge(hit_point, hit_normal)
	if not ledge.is_empty():
		grabbed_col = ledge.node
		grab_offset = (ledge.node as Node3D).to_local(ledge.point)
		trying_to_grab = false

# Searches upward from an initial wall hit for a walkable ledge, without
# assuming the wall is vertical.
#
# The key trick is the climb direction: rather than probing straight up
# (world up_dir), we project up_dir onto the wall's own tangent plane -
#     slope_up = up_dir - wall_normal * up_dir.dot(wall_normal)
# up_dir.dot(wall_normal) is the cosine of the angle between "up" and the
# wall's normal, so subtracting that component removes exactly the part of
# up_dir that points into/out of the wall. What's left is the direction that
# actually runs along the wall's face. On a plain vertical wall this reduces
# to up_dir itself; on a sloped or overhanging face it leans the search path
# forward or backward by the right trigonometric amount, so ledges that sit
# above a receding or leaning surface (not directly overhead) are still found.
#
# Along that path we do a classic two-ray probe at each step: a forward ray
# checks whether the wall is still solid at that height, and the moment it
# isn't, a downward ray right there checks for a walkable surface. Every
# probe point is also clamped to the arm's actual reach
# (shapecast_arms.target_position.length()) so nothing beyond the arm's
# physical range can ever be grabbed.
func _find_ledge(wall_point: Vector3, wall_normal: Vector3) -> Dictionary:
	var up_dir := current_up_dir
	var space_state := get_world_3d().direct_space_state
	var exclude := [get_rid()]
	var mask := shapecast_arms.collision_mask

	var into_wall := -wall_normal

	var slope_up := up_dir - wall_normal * up_dir.dot(wall_normal)
	if slope_up.length_squared() < 0.0001:
		# Wall normal is (anti-)parallel to up - this is a floor/ceiling hit,
		# not a climbable face.
		return {}
	slope_up = slope_up.normalized()

	var arm_origin := shapecast_arms.global_position
	var max_reach := shapecast_arms.target_position.length()
	var walkable_cos := cos(ledge_max_surface_angle)

	var probe_point := wall_point
	var was_blocked := true

	for i in range(ledge_probe_steps):
		probe_point += slope_up * ledge_step_height
		if (probe_point - arm_origin).length() > max_reach:
			break

		var forward_from := probe_point + wall_normal * ledge_surface_margin
		var forward_to := forward_from + into_wall * ledge_probe_depth
		var forward_query := PhysicsRayQueryParameters3D.create(forward_from, forward_to, mask, exclude)
		var forward_hit := space_state.intersect_ray(forward_query)

		if not forward_hit.is_empty():
			# Wall face still present at this height - keep climbing.
			was_blocked = true
			continue

		if not was_blocked:
			# Already in open space above the wall with nothing found -
			# no point probing further.
			break

		# Transition from solid wall to open space: this is the wall's top
		# edge. Drop a ray down through that empty space to find the surface.
		was_blocked = false

		var down_from := forward_to + up_dir * (ledge_step_height * 0.5)
		var down_to := down_from - up_dir * (ledge_step_height + ledge_surface_margin * 2.0)
		var down_query := PhysicsRayQueryParameters3D.create(down_from, down_to, mask, exclude)
		var down_hit := space_state.intersect_ray(down_query)

		if down_hit.is_empty():
			continue

		var surface_normal : Vector3 = down_hit.normal
		if surface_normal.dot(up_dir) < walkable_cos:
			# Too steep to stand/hang on - not a valid ledge.
			continue

		if (down_hit.position - arm_origin).length() > max_reach:
			continue

		return {"node": down_hit.collider, "point": down_hit.position}

	return {}

func arm_logic() -> void:
	if (grabbed_col != null):
		var is_rb = grabbed_col is RigidBody3D
		var grab_position = grabbed_col.to_global(grab_offset)
		var grab_position_target := shapecast_arms.to_global(Vector3.BACK * grab_distance)
		var offset = (grab_position_target - grab_position)
		if (offset.length() > shapecast_arms.target_position.length()):
			grabbed_col = null
			return
		
		var weight := 1.0
		if (is_rb):
			weight = clampf(grabbed_col.mass / grab_scale_max_mass, 0, 1)
		var spring_k := lerpf(0, grab_strength_max, weight)
		
		var grabbed_point_velocity := Vector3.ZERO
		if (is_rb):
			grabbed_point_velocity = grabbed_col.linear_velocity \
				+ grabbed_col.angular_velocity.cross(grab_position - grabbed_col.global_position)
		var arm_point_velocity := linear_velocity \
			+ angular_velocity.cross(grab_position_target - global_position)
		var relative_velocity := grabbed_point_velocity - arm_point_velocity

		var damp := lerpf(grab_damp_min, grab_damp_max, weight)
		var force = offset * spring_k - relative_velocity * damp

		if (is_rb):
			var grabbed_lever_arm = grab_position - grabbed_col.global_position
			grabbed_col.apply_force(force / 2, grabbed_lever_arm)
			if grabbed_col.angular_velocity.length() > grab_max_angular_velocity:
				grabbed_col.apply_torque(-grabbed_col.angular_velocity * grab_angular_damp)

		var arm_lever_arm := shapecast_arms.global_position - global_position
		if (linear_velocity.length() > grab_strength_max / mass / 20):
			var force_scale = (force.normalized().dot(linear_velocity.normalized()) + 1) / 2
			force *= force_scale
		apply_force(-force / 2)
