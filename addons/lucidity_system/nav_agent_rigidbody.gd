extends NetworkRigidbody3D
class_name NavAgentRigidbody3D

@export var nav_agent : NavigationAgent3D
@export var move_speed : float = 4.0
@export var acceleration : float = 10.0
@export var arrival_distance : float = 0.3
@export var max_force : float = 2000.0
@export var slowdown_distance : float = 1.5

var target_position : Vector3 = Vector3.ZERO
var has_target : bool = false

func _ready() -> void:
	super._ready()
	if is_instance_valid(nav_agent):
		nav_agent.set_physics_process(is_multiplayer_authority())

func set_movement_target(new_target: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	target_position = new_target
	has_target = true
	if is_instance_valid(nav_agent):
		nav_agent.target_position = new_target

func stop_movement() -> void:
	has_target = false

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_multiplayer_authority():
		return
	
	if not has_target or not is_instance_valid(nav_agent):
		return
	if nav_agent.is_navigation_finished():
		return
	
	var next_point := nav_agent.get_next_path_position()
	var to_point := next_point - global_position
	var distance := to_point.length()

	if distance < arrival_distance:
		return

	var speed_scale := clampf(distance / slowdown_distance, 0.0, 1.0)
	var desired_velocity := to_point.normalized() * move_speed * speed_scale

	var velocity_error := desired_velocity - linear_velocity
	var force := (velocity_error * mass * acceleration).limit_length(max_force)

	apply_central_force(force)
	if is_instance_valid(nav_agent):
		nav_agent.set_velocity(linear_velocity)
