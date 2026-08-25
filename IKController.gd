extends Node3D
class_name WalkIKController

@export var head_root : Node3D
@export var ik_springs : Array[SpringArm3D]
@export var ik_targets : Array[Node3D]
@export var ik_poles : Array[Node3D]
@export var ik_bone_roots : Array[String]
@export var ik_bone_mids : Array[String]
@export var ik_bone_ends : Array[String]
@export var start_positions : Array[Vector3]
@export var phase_offsets : Array[float] = [0.0, 0.5, 0.5, 0.0]
@export var speed_min : float = 0.25
@export var speed_max : float = 0.5
@export var min_speed : float = 1.0
@export var max_speed : float = 2.0
@export var arm_lift_scale : float = 0.1
@export var arm_stretch_scale : float = 0.5
@export var lift_min : Curve
@export var stretch_min : Curve
@export var lift_max : Curve
@export var stretch_max : Curve
@export var stance_height_bob_min : Curve
@export var stance_height_bob_max : Curve
@export var level_speed : float = 10.0
@export var horizontal_scale : float = 0.5
@export var lift_slope_boost : float = 1.0

@export var idle_speed_threshold : float = 0.05
@export var pose_blend_in_speed : float = 3.0
@export var pose_blend_out_speed : float = 2.0

@export var air_offset_scale : float = 0.15
@export var air_offset_max : float = 0.6
@export var air_blend_in_speed : float = 4.0
@export var air_blend_out_speed : float = 6.0

var initialized := false

var body : PhysicsPlayerController
var shapecast_legs : ShapeCast3D
var sample : float = 0.0
var pose_blend : float = 0.0
var air_blend : float = 0.0
var last_climb_grab_tick : int = 0

func _process(delta: float) -> void:
	if not initialized: return
	
	var t := clampf(shapecast_legs.get_closest_collision_safe_fraction() * 2, 0, 1)
	global_basis = body.basis.slerp(_apply_gravity_counter_rotation(delta), t)

	var is_climbing := body.climbing_ledge

	var local_vel_full := body.global_basis.inverse() * body.relative_velocity
	var local_vel := local_vel_full
	local_vel.y = 0
	var vel_length := local_vel.length()
	var current_angle : float = (-body.global_basis.z).signed_angle_to(body.relative_velocity, body.current_up_dir)
	var polarity : float = 1 if current_angle > deg_to_rad(-80) && current_angle < deg_to_rad(100) else -1
	var weight = clampf(remap(vel_length, min_speed, max_speed, 0, 1), 0, 1)
	var speed = lerpf(speed_min, speed_max, weight)

	if is_climbing:
		if body.climb_grab_tick != last_climb_grab_tick:
			last_climb_grab_tick = body.climb_grab_tick
			sample = wrapf(sample + 0.5, 0, 1)
	else:
		last_climb_grab_tick = body.climb_grab_tick
		sample = wrapf(sample + delta * polarity * -vel_length * speed, 0, 1)

	var is_moving := vel_length > idle_speed_threshold
	var target_blend := 1.0 if is_moving else 0.0
	var blend_rate := pose_blend_in_speed if is_moving else pose_blend_out_speed
	pose_blend = move_toward(pose_blend, target_blend, delta * blend_rate)

	var target_air_blend := 0.0 if body.grounded else 1.0
	var air_blend_rate := air_blend_in_speed if !body.grounded else air_blend_out_speed
	air_blend = move_toward(air_blend, target_air_blend, delta * air_blend_rate)

	var animated_stance_scale := lerpf(stance_height_bob_min.sample(sample), stance_height_bob_max.sample(sample), weight)
	body.stance_height_scale = lerpf(1.0, animated_stance_scale, pose_blend * (1.0 - air_blend))

	var time_scale := absf(shapecast_legs.target_position.y)

	var air_dir := Vector3.ZERO
	var air_speed := local_vel_full.length()
	if air_speed > 0.0001:
		air_dir = -local_vel_full / air_speed

	for i in ik_springs.size():
		var s := wrapf(sample + phase_offsets[i], 0, 1) if body.grabbed_col == null or body.climbing_ledge or i < 2 else 0.0
		var lift_slope_scale := (2 - body.current_dot) * lift_slope_boost
		var lift = lerpf(lift_min.sample(s), lift_max.sample(s), weight) * lift_slope_scale * (arm_lift_scale if i >= 2 else 1)
		var stretch = lerpf(stretch_min.sample(s), stretch_max.sample(s), weight) * (arm_stretch_scale if i >= 2 else 1) - ((1 - t) * 2 if i >= 2 else 0)
		var aniso = abs(Vector3.FORWARD.dot(local_vel.normalized()))
		if (i >= 2):
			aniso = 1
		var crouch_lift = (0.25 if Input.is_action_pressed("crouch") && !body.grounded else 0)
		var animated_offset := Vector3(stretch * time_scale * (1 - aniso) * horizontal_scale, lift * time_scale + crouch_lift, stretch * time_scale * aniso)
		var grounded_pos := start_positions[i] + animated_offset * pose_blend

		var limb_scale := (arm_stretch_scale if i >= 2 else 1.0)
		var air_offset := air_dir * clampf(air_speed * air_offset_scale, 0.0, air_offset_max) * limb_scale
		var airborne_pos := start_positions[i] + air_offset

		var limb_air_blend := 1.0 if (is_climbing and i < 2) else air_blend
		var target_pos := grounded_pos.lerp(airborne_pos, limb_air_blend)
		var is_holding = i >= 2 and body.grabbed_col != null and not body.climbing_ledge
		ik_springs[i].look_at(to_global(target_pos if not is_holding else start_positions[i]), to_global(Vector3.UP), true)
		ik_springs[i].spring_length = ik_springs[i].global_position.distance_to(to_global(target_pos))
		if body.grabbed_col != null and i >= 2:
			var body_yaw := body.global_basis.get_euler().y
			var yaw_right := Vector3.RIGHT
			ik_springs[i].rotate(yaw_right, -head_root.rotation.x + deg_to_rad(90))

func _apply_gravity_counter_rotation(delta: float) -> Basis:
	var parent_node := get_parent()
	var parent3d := parent_node as Node3D
	var up := Vector3.UP
	if body:
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		if state and state.total_gravity.length_squared() > 0.0001:
			up = -state.total_gravity.normalized()
	var parent_fwd := -parent3d.global_transform.basis.z
	parent_fwd -= up * parent_fwd.dot(up)
	if parent_fwd.length_squared() < 0.0001:
		parent_fwd = -global_transform.basis.z
		parent_fwd -= up * parent_fwd.dot(up)
		if parent_fwd.length_squared() < 0.0001:
			parent_fwd = up.cross(Vector3.RIGHT)
			if parent_fwd.length_squared() < 0.0001:
				parent_fwd = up.cross(Vector3.FORWARD)
	parent_fwd = parent_fwd.normalized()
	var target_basis := Basis.looking_at(parent_fwd, up)
	if level_speed <= 0.0:
		return target_basis
	else:
		return global_transform.basis.slerp(target_basis, clampf(delta * level_speed, 0.0, 1.0))
