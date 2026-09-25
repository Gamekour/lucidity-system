extends Camera3D

@export var tilt_strength := 100.0
@export var fov_speed_min := 3.0
@export var fov_speed_max := 12.0
@export var max_fov := 120.0
@export var fov_smoothing := 8.0

var last_position := Vector3.ZERO
var base_fov := 0.0

func _ready() -> void:
	last_position = global_position
	base_fov = fov

func _physics_process(delta: float) -> void:
	var parent := get_parent_node_3d()
	var velocity := (last_position - parent.global_position) * delta
	var local_velocity := parent.to_local(global_position + velocity)
	basis = Basis(Vector3.FORWARD, -local_velocity.x * PI * tilt_strength)
	
	var new_fov = remap(velocity.length(), fov_speed_min * delta / 20, fov_speed_max * delta / 20, base_fov, max_fov)
	new_fov = clampf(new_fov, base_fov, max_fov)
	var t := 1.0 - exp(-fov_smoothing * delta)
	fov = lerp(fov, new_fov, t)
	
	last_position = parent.global_position
