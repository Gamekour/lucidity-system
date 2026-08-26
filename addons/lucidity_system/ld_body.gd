extends RigidBody3D
class_name PhysicsPlayerController

@export_category("Player Model")
@export var playermodel_scene : PackedScene
@export var shapecast_legs_length_scale : float = 1.5
@export_category("Movement Parameters")
@export var roll_force := 10.0
@export var sprint_multiplier := 3.0
@export var acceleration := 5.0
@export var air_acceleration := 1.0
@export var sens := Vector2(0.5,0.5)
@export var crouch_speed := 0.5
@export var speed_stance_stop : float = 0.6
@export var crouch_height := 0.5
@export var crawl_height := 0.3
@export var jump_height := 2.0
@export_category("Camera")
@export_range(-90.0, 90.0, 0.5, "radians_as_degrees") var min_camera_pitch : float = deg_to_rad(-80.0)
@export_range(-90.0, 90.0, 0.5, "radians_as_degrees") var max_camera_pitch : float = deg_to_rad(80.0)
@export_category("Physics Tuning")
@export var apply_reaction_forces : bool = true
@export var apply_reaction_torque : bool = false
@export var friction_coefficient := 2.0
@export var ride_height_scale := 0.9
@export var spring_strength := 5000.0
@export var spring_damping := 1000.0
@export var turn_strength := 100.0
@export var turn_damping := 10.0
@export var upright_strength := 1000.0
@export var upright_damping := 100.0
@export var cam_distance_max := 4.0
@export var cam_distance_min := 0.0
@export var lean_strength := 1000.0
@export var max_lean_angle := 50.0
@export var crouch_lean_angle := 0.5
@export var air_upright_assist_strength := 1000.0
@export var air_upright_assist_damping := 100.0
@export var body_turn_input_deadzone : float = 0.15
@export var camera_tilt_smoothing : float = 10.0
@export var body_turn_sideways_deadzone: float = deg_to_rad(15.0)
@export var slope_correction : float = 1.0
@export var slope_correction_damping : float = 0.0
@export var slope_stance_height_scale : float = 0.5
@export var max_floor_force_scale : float = 100.0
@export var max_floor_torque_scale : float = 100.0
@export var grab_vertical_strength_multiplier : float = 2.5
@export var grab_force_central_scale : float = 0.0
@export var stance_height_rot_min : float = 0.5
@export var stance_height_rot_max : float = 0.6
@export_range(0.0, 360.0, 0.5, "radians_as_degrees") var max_look_angle_horizontal : float = deg_to_rad(40.0)
@export_category("Grab Physics")
@export var allow_grab : bool = true
@export var grab_strength_min : float = 100
@export var grab_strength_max : float = 1000
@export var grab_scale_max_mass : float = 69
@export var grab_distance : float = 1.0
@export var grab_damp_min : float = 400.0
@export var grab_damp_max : float = 500.0
@export var grab_damp_static : float = 1000.0
@export var grab_max_angular_velocity : float = 10.0
@export var grab_angular_damp : float = 5.0
@export var grab_lift_offset := 0.25
@export_group("Ledge Detection")
@export var ledge_probe_steps : int = 6
@export var ledge_step_height : float = 0.15
@export var ledge_probe_depth : float = 0.35
@export var ledge_surface_margin : float = 0.05
@export_range(0.0, 90.0, 0.5, "radians_as_degrees") var ledge_max_surface_angle : float = deg_to_rad(45.0)

@export_group("Climbing")
@export var climb_scan_speed : float = 1.5
@export_range(0.0, 90.0, 0.5, "radians_as_degrees") var climb_scan_min_angle : float = deg_to_rad(20.0)
@export_range(0.0, 90.0, 0.5, "radians_as_degrees") var climb_scan_max_angle : float = deg_to_rad(40.0)
@export var climb_scan_input_deadzone : float = 0.15

@onready var cam_spring : SpringArm3D = $cam_spring
@onready var shapecast_legs : ShapeCast3D = $shapecast_legs
@onready var shapecast_arms : ShapeCast3D = $shapecast_arms

var playermodel : PlayerModel
var ik_controller : WalkIKController
var attach_controller : AttachmentController

var grabbed_col : Node3D
var grab_release_pending : Array[RigidBody3D]
var grab_offset : Vector3 = Vector3.ZERO
var relative_velocity : Vector3 = Vector3.ZERO
var overlay_eulers : Vector3 = Vector3.ZERO
var input_move : Vector2 = Vector2.ZERO
var stance_height : float = 0.0
var target_angle_horizontal : float = 0
var camera_pitch : float = 0.0
var sprinting := false
var crouch_jump := false
var grounded := false
var crouching := false
var crawling := false
var jumping := false
var trying_to_grab := false
var allow_grab_default := true

var climbing_ledge : bool = false
var climb_scan_active : bool = false
var climb_scan_angle : float = 0.0
var climb_scan_base_basis : Basis = Basis.IDENTITY
var climb_scan_last_hit : Dictionary = {}
var climb_grab_tick : int = 0

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
	allow_grab_default = allow_grab
	rig_setup()

func rig_setup() -> void:
	for child in find_children("*"):
		if (child is WalkIKController):
			ik_controller = child
		if (child is AttachmentController):
			attach_controller = child
	
	if (ik_controller != null):
		ik_controller.body = self
		ik_controller.shapecast_legs = shapecast_legs
		ik_controller.initialized = true
		if (playermodel_scene != null):
			playermodel = PlayerModelFactory.spawn_player_model(playermodel_scene, self)
			playermodel.body = self
			playermodel.cam_spring = cam_spring
			var i = 0
			for ik_node in ik_controller.ik_targets:
				var two_bone := TwoBoneIK3D.new()
				two_bone.setting_count = 1
				two_bone.set_target_node(0, ik_controller.ik_targets[i].get_path())
				two_bone.set_pole_node(0, ik_controller.ik_poles[i].get_path())
				two_bone.set_root_bone_name(0, ik_controller.ik_bone_roots[i])
				two_bone.set_middle_bone_name(0, ik_controller.ik_bone_mids[i])
				two_bone.set_end_bone_name(0, ik_controller.ik_bone_ends[i])
				two_bone.set_pole_direction(0, SkeletonModifier3D.SECONDARY_DIRECTION_MINUS_Z)
				two_bone.name = ik_controller.ik_targets[i].name
				playermodel.add_child(two_bone)
				var root := playermodel.get_bone_global_pose(playermodel.find_bone(ik_controller.ik_bone_roots[i])).origin
				var mid := playermodel.get_bone_global_pose(playermodel.find_bone(ik_controller.ik_bone_mids[i])).origin
				var end := playermodel.get_bone_global_pose(playermodel.find_bone(ik_controller.ik_bone_ends[i])).origin
				var chain_length = root.distance_to(mid) + mid.distance_to(end)
				ik_controller.ik_springs[i].spring_length = chain_length
				ik_controller.ik_springs[i].position = root
				if i == 0:
					shapecast_legs.target_position = Vector3.DOWN * chain_length * shapecast_legs_length_scale
				i += 1
			playermodel.owner = self
			for bone_root : BoneRoot in find_children("*", "BoneRoot"):
				bone_root.skeleton = playermodel
			if (attach_controller != null):
				attach_controller.body = self
				attach_controller._connect_skeleton(playermodel)

func _physics_process(delta: float) -> void:
	var gravity_vec : Vector3 = get_gravity()
	var up_dir : Vector3 = _get_up_direction(gravity_vec).normalized()
	current_up_dir = up_dir
	
	var base_right := up_dir.cross(global_basis.z).normalized()
	var shapecast_basis := Basis(base_right, up_dir, global_basis.z.normalized())
	shapecast_legs.global_basis = shapecast_basis.orthonormalized()

	var input_3d := _get_camera_relative_input(up_dir, input_move)
	var max_speed = max(lerpf(crouch_speed * roll_force, roll_force * sprint_multiplier * sprint_multiplier_scale, min(stance_height / speed_stance_stop, 1)), 0)
	crouch_jump = jumping and crouching
	
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

	var accel := Vector3.ZERO
	if grounded:
		accel = (target_force - (flat_velocity * mass) - slope_correction_force) * (acceleration * acceleration_scale) * (sprint_multiplier * sprint_multiplier_scale if sprinting || crouch_jump else 1.0)
	elif not (grabbed_col != null and not grabbed_col is RigidBody3D):
		accel = _get_air_accel(target_force, flat_velocity, air_acceleration * air_acceleration_scale)
	var force = accel.limit_length(friction_budget)

	var current_yaw := _get_current_yaw(up_dir)
	var body_target_angle := _get_body_target_angle(input_move)
	var look_angle_horizontal : float = wrapf(body_target_angle - current_yaw, -PI, PI)
	look_angle_horizontal = clamp(look_angle_horizontal, -max_look_angle_horizontal, max_look_angle_horizontal)
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
	
	stance_height = jump_height * jump_height_scale if jumping else crawl_height if crawling else crouch_height if crouching else 1.0
	stance_height *= stance_height_scale
	stance_height -= (1 - current_dot) * slope_stance_height_scale
	
	if grounded:
		var current_distance : float = shapecast_legs.get_closest_collision_safe_fraction() * abs(shapecast_legs.target_position.y)
		var ride_height = abs(shapecast_legs.target_position.y) * ride_height_scale
		var displacement : float = (stance_height * ride_height) - current_distance
		
		var normal_velocity : float = relative_velocity.dot(slope_normal)
		var spring_magnitude : float = displacement * spring_strength * spring_strength_scale - normal_velocity * spring_damping * spring_damping_scale
		var spring_force : Vector3 = slope_normal * spring_magnitude
		force += spring_force
	
	apply_force(force, shapecast_legs.position)

	if grounded and apply_reaction_forces and floor_rigidbody != null and is_instance_valid(floor_rigidbody):
		var offset := floor_contact_point - floor_rigidbody.global_position
		var floor_force = force.limit_length(floor_rigidbody.mass * max_floor_force_scale)
		floor_rigidbody.apply_force(-floor_force, offset)
		if apply_reaction_torque:
			var floor_torque = total_torque.limit_length(floor_rigidbody.mass * max_floor_torque_scale)
			floor_rigidbody.apply_torque(-floor_torque)
	
	if (grabbed_col == null && trying_to_grab && allow_grab):
		arm_cast()
	arm_logic()
	_process_climb_scan(delta, input_move)
	_update_grab_release_pending()

func _process(delta: float) -> void:
	var tilt_t : float = 1.0 - exp(-camera_tilt_smoothing * delta)
	camera_up_dir = camera_up_dir.normalized()
	current_up_dir = current_up_dir.normalized()
	camera_up_dir = _safe_slerp_up(camera_up_dir, current_up_dir, tilt_t)
	var tilt_basis := _get_tilt_basis(camera_up_dir)
	var yaw_basis := Basis(Vector3.UP, target_angle_horizontal)
	var pitch_basis := Basis(Vector3.RIGHT, camera_pitch)
	cam_spring.global_basis = tilt_basis * yaw_basis * pitch_basis

func _supply_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		target_angle_horizontal = wrapf(target_angle_horizontal - event.relative.x * get_process_delta_time() * sens.x, -PI, PI)
		camera_pitch = clampf(camera_pitch - event.relative.y * get_process_delta_time() * sens.y, min_camera_pitch, max_camera_pitch)
	if event is InputEventMouseButton:
		if (event.is_pressed()):
			if (event.button_index == MOUSE_BUTTON_WHEEL_UP):
				cam_spring.spring_length = clampf(cam_spring.spring_length - cam_distance_max / 10, cam_distance_min, cam_distance_max)
			if (event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
				cam_spring.spring_length = clampf(cam_spring.spring_length + cam_distance_max / 10, cam_distance_min, cam_distance_max)
	if event.is_action("move_forward") or event.is_action("move_back") or event.is_action("move_left") or event.is_action("move_right"):
		input_move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if event.is_action_pressed("grab"):
		trying_to_grab = true
	if event.is_action_released("grab"):
		_queue_collision_exception_release(grabbed_col)
		if (ik_controller != null and grabbed_col != null):
			for spring in ik_controller.ik_springs:
				spring.remove_excluded_object(grabbed_col.get_rid())
		grabbed_col = null
		trying_to_grab = false
		climbing_ledge = false
		_reset_climb_scan()
	if event.is_action_pressed("attach"):
		if (grabbed_col is RigidBody3D):
			var success := attach_controller.attach(grabbed_col)
			if (success):
				(grabbed_col as RigidBody3D).remove_collision_exception_with(self)
				grab_release_pending.erase(grabbed_col)
				if (ik_controller != null):
					for spring in ik_controller.ik_springs:
						spring.remove_excluded_object(grabbed_col.get_rid())
				grabbed_col = null
				climbing_ledge = false
				_reset_climb_scan()
	if (event.is_action_pressed("interact")):
		if (shapecast_arms.is_colliding()):
			var col = shapecast_arms.get_collider(0)
			if (col.has_method("_interact")):
				col.call("_interact")
	if (event.is_action("sprint")):
		sprinting = event.is_pressed()
	if (event.is_action("jump")):
		jumping = event.is_pressed()
	if (event.is_action("crouch")):
		crouching = event.is_pressed()
	if (event.is_action("crawl")):
		crawling = event.is_pressed()

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
	var cam_forward := -cam_spring.global_basis.z
	var flat_forward := cam_forward - up_dir * cam_forward.dot(up_dir)
	if flat_forward.length_squared() < 0.0001:
		var cam_local_up := cam_spring.global_basis.y
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
		return target_angle_horizontal + overlay_eulers.y
	
	var move_yaw_offset := atan2(input_vector.x, input_vector.y)
	var climbing = grabbed_col != null
	climbing = climbing and not (grabbed_col is RigidBody3D)
	if ((absf(absf(move_yaw_offset) - (PI / 2.0)) < body_turn_sideways_deadzone) and playermodel.is_fp) or climbing or stance_height < stance_height_rot_min:
		return target_angle_horizontal + overlay_eulers.y
	
	if input_vector.y < 0.0 and playermodel.is_fp:
		if (move_yaw_offset < 0.0):
			move_yaw_offset += PI
		else:
			move_yaw_offset -= PI
	
	var yaw_scale = clamp((stance_height - stance_height_rot_min) / (stance_height_rot_max - stance_height_rot_min), 0, 1)
	
	return wrapf(((target_angle_horizontal - move_yaw_offset) * yaw_scale) + overlay_eulers.y, -PI, PI)

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
	var flat_lean := lean_input
	var lean_magnitude := clampf(flat_lean.length() * lean_strength * (2 if crouch_jump else 1), 0.0, 1.0)
	
	var local_anim_offset := Vector3(overlay_eulers.x, 0.0, overlay_eulers.z)
	var world_anim_offset := global_basis.orthonormalized() * local_anim_offset
	var flat_anim_lean := world_anim_offset - world_anim_offset.project(up_dir)

	var combined_lean := flat_lean * lean_magnitude
	if combined_lean.length() + flat_anim_lean.length() < 0.0001:
		return up_dir

	var lean_dir := combined_lean.normalized()
	var lean_axis := up_dir.cross(lean_dir).normalized()
	var lean_angle := minf(combined_lean.length() * max_lean_angle, max_lean_angle)

	return up_dir.rotated(lean_axis, lean_angle)

func _get_crouch_lean_factor() -> float:
	return clampf(0.75 - shapecast_legs.get_closest_collision_safe_fraction(), 0, 1) * 3

func _get_upright_torque(up_dir: Vector3, lean_input: Vector3, strength: float, damping: float) -> Vector3:
	var target_up := _get_lean_target_up(up_dir, lean_input)

	var crouch_factor := _get_crouch_lean_factor()
	if crouch_factor > 0.0001:
		var body_forward := -global_basis.z
		var flat_forward := (body_forward - up_dir * body_forward.dot(up_dir)).normalized()
		
		var lean_axis := flat_forward.cross(up_dir)
		var lean_axis_length := lean_axis.length()
		if lean_axis_length > 0.0001:
			lean_axis /= lean_axis_length
			target_up = target_up.rotated(lean_axis, crouch_factor * -crouch_lean_angle)

	return _upright_torque_towards(target_up, strength, damping)

func _get_air_upright_torque(up_dir: Vector3) -> Vector3:
	if air_upright_assist_strength <= 0.0:
		return Vector3.ZERO
	return _upright_torque_towards(up_dir, air_upright_assist_strength, air_upright_assist_damping)

func _upright_torque_towards(target_up: Vector3, strength: float, damping: float) -> Vector3:
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

	if collider is RigidBody3D:
		grabbed_col = collider
		grab_offset = collider.to_local(shapecast_arms.get_collision_point(0))
		trying_to_grab = false
		climbing_ledge = false
		_reset_climb_scan()
		grabbed_col.add_collision_exception_with(self)
		grab_release_pending.erase(grabbed_col)
		if (ik_controller != null):
			for spring in ik_controller.ik_springs:
				spring.add_excluded_object(collider.get_rid())
		return

	var hit_point := shapecast_arms.get_collision_point(0)
	var hit_normal := shapecast_arms.get_collision_normal(0)
	var ledge := _find_ledge(hit_point, hit_normal)
	if not ledge.is_empty():
		grabbed_col = ledge.node
		grab_offset = (ledge.node as Node3D).to_local(ledge.point)
		trying_to_grab = false
		climbing_ledge = true
		_reset_climb_scan()

func _find_ledge(wall_point: Vector3, wall_normal: Vector3) -> Dictionary:
	var up_dir := current_up_dir
	var space_state := get_world_3d().direct_space_state
	var exclude := [get_rid()]
	var mask := shapecast_arms.collision_mask

	var into_wall := -wall_normal

	var slope_up := up_dir - wall_normal * up_dir.dot(wall_normal)
	if slope_up.length_squared() < 0.0001:
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
			was_blocked = true
			continue

		if not was_blocked:
			break

		was_blocked = false

		var down_from := forward_to + up_dir * (ledge_step_height * 0.5)
		var down_to := down_from - up_dir * (ledge_step_height + ledge_surface_margin * 2.0)
		var down_query := PhysicsRayQueryParameters3D.create(down_from, down_to, mask, exclude)
		var down_hit := space_state.intersect_ray(down_query)

		if down_hit.is_empty():
			continue

		var surface_normal : Vector3 = down_hit.normal
		if surface_normal.dot(up_dir) < walkable_cos:
			continue

		if (down_hit.position - arm_origin).length() > max_reach:
			continue

		return {"node": down_hit.collider, "point": down_hit.position}

	return {}

func _reset_climb_scan() -> void:
	climb_scan_active = false
	climb_scan_angle = 0.0
	climb_scan_last_hit = {}

func _commit_climb_hit(hit: Dictionary) -> void:
	_queue_collision_exception_release(grabbed_col)
	grabbed_col = hit.node
	grab_offset = (hit.node as Node3D).to_local(hit.point)
	climbing_ledge = true
	climb_grab_tick += 1
	_reset_climb_scan()

func _scan_for_ledge_at_angle(pitch: float, yaw: float) -> Dictionary:
	var base_right := climb_scan_base_basis.x
	var base_up := climb_scan_base_basis.y
	var base_dir := climb_scan_base_basis.z

	var swept_dir := base_dir.rotated(base_right, pitch).rotated(base_up, yaw).normalized()

	var arm_origin := shapecast_arms.global_position
	var max_reach := shapecast_arms.target_position.length()

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		arm_origin, arm_origin + swept_dir * max_reach,
		shapecast_arms.collision_mask, [get_rid()]
	)
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	if hit.collider is RigidBody3D:
		return {}

	var ledge := _find_ledge(hit.position, hit.normal)
	if ledge.is_empty():
		return {}

	ledge["angle"] = absf(pitch) + absf(yaw)
	return ledge

func _process_climb_scan(delta: float, input_vector: Vector2) -> void:
	if not climbing_ledge or grabbed_col == null:
		_reset_climb_scan()
		return

	if input_vector.length() < climb_scan_input_deadzone:
		_reset_climb_scan()
		return

	if not climb_scan_active:
		climb_scan_active = true
		climb_scan_angle = 0.0
		climb_scan_last_hit = {}
		climb_scan_base_basis = shapecast_arms.global_basis

	climb_scan_angle += climb_scan_speed * delta

	var scan_finished := climb_scan_angle >= climb_scan_max_angle
	climb_scan_angle = minf(climb_scan_angle, climb_scan_max_angle)

	var dir := input_vector.normalized()
	var pitch := -dir.y * climb_scan_angle
	var yaw := -dir.x * climb_scan_angle

	var hit := _scan_for_ledge_at_angle(pitch, yaw)
	if not hit.is_empty():
		if hit.angle < climb_scan_min_angle:
			climb_scan_last_hit = hit
		else:
			_commit_climb_hit(hit)
			return

	if scan_finished:
		if not climb_scan_last_hit.is_empty():
			_commit_climb_hit(climb_scan_last_hit)
		else:
			_reset_climb_scan()

func arm_logic() -> void:
	if (grabbed_col != null):
		var is_rb = grabbed_col is RigidBody3D
		var grab_position = grabbed_col.to_global(grab_offset)
		var grab_position_target := shapecast_arms.to_global((Vector3.BACK * grab_distance) + (Vector3.UP * (grab_lift_offset if grabbed_col is RigidBody3D else 0.0)))
		var offset = (grab_position_target - grab_position)
		if (offset.length() > shapecast_arms.target_position.length()):
			_queue_collision_exception_release(grabbed_col)
			grabbed_col = null
			climbing_ledge = false
			_reset_climb_scan()
			return
		
		var weight := 1.0
		if (is_rb):
			weight = clampf(grabbed_col.mass / grab_scale_max_mass, 0, 1)
		else:
			weight = clampf(mass / grab_scale_max_mass, 0, 1)
		var spring_k := lerpf(0, grab_strength_max, weight)
		
		var grabbed_point_velocity := Vector3.ZERO
		if (is_rb):
			grabbed_point_velocity = grabbed_col.linear_velocity \
				+ grabbed_col.angular_velocity.cross(grab_position - grabbed_col.global_position)
		var arm_point_velocity := linear_velocity \
			+ angular_velocity.cross(grab_position_target - global_position)
		var grab_relative_velocity := grabbed_point_velocity - arm_point_velocity

		var damp := lerpf(grab_damp_min, grab_damp_max, weight)

		var body_up := global_basis.y
		var offset_vert := offset.project(body_up)
		var offset_horiz = offset - offset_vert
		var vel_vert := grab_relative_velocity.project(body_up)
		var vel_horiz := grab_relative_velocity - vel_vert

		var force_vert := offset_vert * spring_k * grab_vertical_strength_multiplier \
			- vel_vert * (damp if grabbed_col is RigidBody3D else grab_damp_static)
		var force_horiz = offset_horiz * spring_k - vel_horiz * damp

		var force = force_vert + force_horiz

		if (is_rb):
			var grabbed_lever_arm = grab_position - grabbed_col.global_position
			grabbed_col.apply_force(force * 0.5 * (1.0 - grab_force_central_scale), grabbed_lever_arm)
			grabbed_col.apply_force(force * 0.5 * (grab_force_central_scale))
			if grabbed_col.angular_velocity.length() > grab_max_angular_velocity:
				grabbed_col.apply_torque(-grabbed_col.angular_velocity * grab_angular_damp)

		if (linear_velocity.length() > grab_strength_max / mass / 20):
			var force_scale = (force.normalized().dot(linear_velocity.normalized()) + 1) / 2
			force *= force_scale
		apply_force(-force / 2)

func _queue_collision_exception_release(col : Node3D) -> void:
	if col is RigidBody3D and not grab_release_pending.has(col):
		grab_release_pending.append(col)

func _update_grab_release_pending() -> void:
	if grab_release_pending.is_empty():
		return

	var space_state := get_world_3d().direct_space_state
	var shape_owners := get_shape_owners()

	for i in range(grab_release_pending.size() - 1, -1, -1):
		var body := grab_release_pending[i]
		if not is_instance_valid(body):
			grab_release_pending.remove_at(i)
			continue

		var still_overlapping := false
		for owner_id in shape_owners:
			var owner_transform := shape_owner_get_transform(owner_id)
			var shape_count := shape_owner_get_shape_count(owner_id)
			for shape_idx in range(shape_count):
				var shape := shape_owner_get_shape(owner_id, shape_idx)
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = shape
				query.transform = global_transform * owner_transform
				query.exclude = [get_rid()]
				query.collide_with_bodies = true
				query.collide_with_areas = false
				var results := space_state.intersect_shape(query, 4)
				for result in results:
					if result.get("collider") == body:
						still_overlapping = true
						break
				if still_overlapping:
					break
			if still_overlapping:
				break

		if not still_overlapping:
			body.remove_collision_exception_with(self)
			grab_release_pending.remove_at(i)
