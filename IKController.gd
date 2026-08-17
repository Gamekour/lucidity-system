extends Node3D
class_name WalkIKController

@export var body : PhysicsPlayerController
@export var legs : ShapeCast3D
@export var ik_targets : Array[Node3D] = []
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

var sample : float = 0.0

func _process(delta: float) -> void:
	_apply_gravity_counter_rotation(delta)

	var local_vel := body.global_basis.inverse() * body.linear_velocity
	var weight = clampf(remap(abs(local_vel.z), min_speed, max_speed, 0, 1), 0, 1)
	var speed = lerpf(speed_min, speed_max, weight)
	sample = wrapf(sample + delta * -local_vel.z * speed, 0, 1)
	body.stance_height_scale = lerpf(stance_height_bob_min.sample(sample), stance_height_bob_max.sample(sample),weight)
	var time_scale := absf(legs.target_position.y)
	for i in ik_targets.size():
		var s := wrapf(sample + phase_offsets[i], 0, 1)
		var lift = lerpf(lift_min.sample(s), lift_max.sample(s), weight) * (arm_lift_scale if i >= 2 else 1)
		var stretch = lerpf(stretch_min.sample(s), stretch_max.sample(s), weight) * (arm_stretch_scale if i >= 2 else 1)
		ik_targets[i].position = start_positions[i] + Vector3(0.0, lift * time_scale, stretch * time_scale)


func _apply_gravity_counter_rotation(delta: float) -> void:
	var parent_node := get_parent()
	if not (parent_node is Node3D):
		return
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
		global_transform.basis = target_basis
	else:
		global_transform.basis = global_transform.basis.slerp(target_basis, clampf(delta * level_speed, 0.0, 1.0))
