extends Camera3D

@export var tilt_strength := 100.0
var last_position := Vector3.ZERO

func _ready() -> void:
	last_position = global_position

func _physics_process(delta: float) -> void:
	var parent := get_parent_node_3d()
	var velocity := (last_position - parent.global_position) * delta
	var local_velocity := parent.to_local(global_position + velocity)
	basis = Basis(Vector3.FORWARD, -local_velocity.x * PI * tilt_strength)
	last_position = parent.global_position
