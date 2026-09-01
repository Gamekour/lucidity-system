extends NetworkRigidbody3D
class_name NavForceFollower

## The node this body will chase across the nav mesh.
@export var target: Node3D

## Steering / force tuning
@export var max_speed: float = 6.0          # m/s, desired top speed
@export var max_force: float = 40.0         # N, max steering force we can apply per physics tick
@export var arrival_radius: float = 2.0     # start slowing down within this distance of the FINAL target
@export var target_update_interval: float = 0.2  # seconds between path re-queries (perf)

## How close to a path point counts as "reached" (nav agent handles this internally too)
@export var path_desired_distance: float = 0.5

## Deadzone: once within this distance of the final target AND moving slower
## than deadzone_speed, stop applying steering force and damp out residual velocity.
@export var deadzone_radius: float = 0.15
@export var deadzone_speed: float = 0.05
@export var deadzone_damping: float = 10.0   # how hard we kill residual velocity in the deadzone

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

var _update_timer: float = 0.0

func _ready() -> void:
	if (!multiplayer.is_server()): return

	nav_agent.path_desired_distance = path_desired_distance
	nav_agent.target_desired_distance = arrival_radius
	super._ready()

func _physics_process(delta: float) -> void:
	if target == null or !multiplayer.is_server(): return

	_update_timer -= delta
	if _update_timer <= 0.0:
		_update_timer = target_update_interval
		nav_agent.target_position = target.global_position

	var distance_to_final: float = global_position.distance_to(target.global_position)
	var horizontal_speed: float = Vector3(linear_velocity.x, 0.0, linear_velocity.z).length()

	# Deadzone: close enough and slow enough -> stop steering, damp residual drift.
	if distance_to_final <= deadzone_radius and horizontal_speed <= deadzone_speed:
		var damp_velocity: Vector3 = Vector3(linear_velocity.x, 0.0, linear_velocity.z) * deadzone_damping
		apply_central_force(-damp_velocity)
		return

	if nav_agent.is_navigation_finished():
		return

	var next_path_pos: Vector3 = nav_agent.get_next_path_position()
	_steer_towards(next_path_pos, distance_to_final)
	super._physics_process(delta)

func _steer_towards(destination: Vector3, distance_to_final: float) -> void:
	var to_dest: Vector3 = destination - global_position
	to_dest.y = 0.0

	var distance: float = to_dest.length()
	if distance < 0.001:
		return

	var speed_scale: float = 1.0
	if distance_to_final < arrival_radius:
		speed_scale = clamp(distance_to_final / arrival_radius, 0.0, 1.0)

	var desired_velocity: Vector3 = to_dest.normalized() * max_speed * speed_scale

	var current_velocity: Vector3 = linear_velocity
	current_velocity.y = 0.0

	var steering: Vector3 = desired_velocity - current_velocity
	if steering.length() > max_force:
		steering = steering.normalized() * max_force

	apply_central_force(steering)
