extends Node3D
class_name WalkIKController
@export var body : PhysicsPlayerController
@export var legs : ShapeCast3D
@export var ik_targets : Array[SpringArm3D] = []
@export var start_positions : Array[Vector3] = []
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

## Below this speed the controller is considered "idle" and will ease back to rest pose.
@export var idle_speed_threshold : float = 0.05
## How quickly (units/sec of blend) the pose eases toward the animated walk pose when moving starts.
@export var pose_blend_in_speed : float = 3.0
## How quickly (units/sec of blend) the pose eases back toward the rest pose when moving stops.
@export var pose_blend_out_speed : float = 2.0

var sample : float = 0.0
## 0 = fully at rest pose (start_positions, neutral stance height), 1 = fully animated walk pose.
var pose_blend : float = 0.0

func _process(delta: float) -> void:
	var t := clampf(body.stance_height * body.stance_height_scale * 2, 0, 1)
	global_basis = body.basis.slerp(_apply_gravity_counter_rotation(delta), t)
	var local_vel := body.global_basis.inverse() * body.linear_velocity
	local_vel.y = 0
	var vel_length := local_vel.length()
	var polarity : float = 1 if local_vel.z < 0 else -1
	var weight = clampf(remap(vel_length, min_speed, max_speed, 0, 1), 0, 1)
	var speed = lerpf(speed_min, speed_max, weight)
	sample = wrapf(sample + delta * polarity * -vel_length * speed, 0, 1)

	# Ease the pose blend toward "animated" while moving, and toward "rest" while idle.
	var is_moving := vel_length > idle_speed_threshold
	var target_blend := 1.0 if is_moving else 0.0
	var blend_rate := pose_blend_in_speed if is_moving else pose_blend_out_speed
	pose_blend = move_toward(pose_blend, target_blend, delta * blend_rate)

	var animated_stance_scale := lerpf(stance_height_bob_min.sample(sample), stance_height_bob_max.sample(sample), weight)
	body.stance_height_scale = lerpf(1.0, animated_stance_scale, pose_blend)

	var time_scale := absf(legs.target_position.y)
	for i in ik_targets.size():
		var s := wrapf(sample + phase_offsets[i], 0, 1)
		var lift_slope_scale := (2 - body.current_dot) * lift_slope_boost
		var lift = lerpf(lift_min.sample(s), lift_max.sample(s), weight) * lift_slope_scale * (arm_lift_scale if i >= 2 else 1)
		var stretch = lerpf(stretch_min.sample(s), stretch_max.sample(s), weight) * (arm_stretch_scale if i >= 2 else 1) - ((1 - t) * 2 if i >= 2 else 0)
		var aniso = abs(Vector3.FORWARD.dot(local_vel.normalized()))
		var crouch_lift = (0.25 if Input.is_action_pressed("crouch") && !body.grounded else 0)
		var animated_offset := Vector3(stretch * time_scale * (1 - aniso) * horizontal_scale, lift * time_scale + crouch_lift, stretch * time_scale * aniso)
		var target_pos := (start_positions[i] + animated_offset * pose_blend)
		ik_targets[i].look_at(to_global(target_pos), to_global(Vector3.UP), true)
		ik_targets[i].spring_length = ik_targets[i].global_position.distance_to(to_global(target_pos))

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
