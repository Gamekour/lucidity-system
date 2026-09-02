class_name NetworkRigidbody3D extends RigidBody3D

## Server-authoritative RigidBody3D.
##
## The server (multiplayer authority) runs the real physics simulation.
## Clients freeze their local body, receive periodic state snapshots from
## the server, and smoothly interpolate toward them. Clients never apply
## forces/impulses locally -- instead they call an RPC that asks the
## server to apply the force to the "real" body, and the result flows
## back down through the regular state sync.

## How many times per second the server pushes state to clients.
@export var sync_rate: float = 20.0

## How quickly clients interpolate toward the latest received state.
## Higher = snappier but jerkier, lower = smoother but more "laggy".
@export var interpolation_speed: float = 12.0

## If true, clients extrapolate position/rotation between snapshots
## using the last known velocity, then correct as new data arrives.
@export var extrapolate: bool = true

var _time_since_sync: float = 0.0

# Latest state received from the server (client-side only).
var _target_position: Vector3
var _target_rotation: Basis
var _target_linear_velocity: Vector3
var _target_angular_velocity: Vector3
var _has_received_state: bool = false

## Replicated velocity, kept correct on both server and client regardless
## of what the underlying RigidBody3D reports. On the server this mirrors
## the real simulated velocity every physics tick. On clients, a frozen
## (FREEZE_MODE_KINEMATIC) body doesn't reliably keep `linear_velocity` /
## `angular_velocity` in sync with what we assign, so other scripts
## should read these instead of the built-in properties if they need to
## be sure they're getting the networked value.
var synced_linear_velocity: Vector3
var synced_angular_velocity: Vector3


func _ready() -> void:
	# Only the authority (server) actually simulates physics.
	# Everyone else freezes the body and treats it as kinematic,
	# driven by interpolated snapshots instead of local physics.
	_update_authority_state()

	# React if authority changes at runtime (e.g. host migration).
	if not multiplayer.connect("connected_to_server", Callable(self, "_update_authority_state")):
		pass

	set_physics_process(true)


func _update_authority_state() -> void:
	var is_authority: bool = is_multiplayer_authority()
	freeze = not is_authority
	# Freeze mode "kinematic" lets us still move the body via transform
	# on clients without it being pushed around by local collisions.
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	set_process_internal(true)


func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_server_tick(delta)
	else:
		_client_tick(delta)


# ---------------------------------------------------------------------------
# SERVER SIDE
# ---------------------------------------------------------------------------

func _server_tick(delta: float) -> void:
	# Keep the replicated velocity fields current every physics step,
	# not just on the sync cadence, so local server-side scripts checking
	# synced_linear_velocity/synced_angular_velocity always see the truth.
	synced_linear_velocity = linear_velocity
	synced_angular_velocity = angular_velocity

	_time_since_sync += delta
	var interval: float = 1.0 / max(sync_rate, 1.0)
	if _time_since_sync >= interval:
		_time_since_sync = 0.0
		_broadcast_state()


func _broadcast_state() -> void:
	# Unreliable + ordered: fine to drop/replace old snapshots, we only
	# care about the most recent state, and we don't want sync traffic
	# to clog the reliable channel used for gameplay-critical RPCs.
	_receive_state.rpc(
		global_position,
		global_transform.basis.get_rotation_quaternion(),
		linear_velocity,
		angular_velocity
	)


# Called by clients to request a force/impulse be applied on the server.
# Only the server executes the actual physics change; clients just ask.
@rpc("any_peer", "call_remote", "reliable")
func request_apply_central_force(force: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	apply_central_force(force)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func request_apply_force(force: Vector3, position: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	apply_force(force, position)


@rpc("any_peer", "call_remote", "reliable")
func request_apply_central_impulse(impulse: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	apply_central_impulse(impulse)


@rpc("any_peer", "call_remote", "reliable")
func request_apply_impulse(impulse: Vector3, position: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	apply_impulse(impulse, position)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func request_apply_torque(torque: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	apply_torque(torque)


@rpc("any_peer", "call_remote", "reliable")
func request_apply_torque_impulse(impulse: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	apply_torque_impulse(impulse)


# ---------------------------------------------------------------------------
# CLIENT SIDE
# ---------------------------------------------------------------------------

@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_state(pos: Vector3, rot: Quaternion, lin_vel: Vector3, ang_vel: Vector3) -> void:
	_target_position = pos
	_target_rotation = Basis(rot)
	_target_linear_velocity = lin_vel
	_target_angular_velocity = ang_vel
	_has_received_state = true


func _client_tick(delta: float) -> void:
	if not _has_received_state:
		return

	if extrapolate:
		# Predict where the server body will be by the time the next
		# snapshot arrives, so movement doesn't visibly stall between ticks.
		_target_position += _target_linear_velocity * delta

	var t: float = clamp(interpolation_speed * delta, 0.0, 1.0)

	global_position = global_position.lerp(_target_position, t)

	var current_rot: Basis = global_transform.basis.orthonormalized()
	var target_rot: Basis = _target_rotation.orthonormalized()
	global_transform.basis = current_rot.slerp(target_rot, t)

	# Interpolate the replicated velocity fields -- these are the ones
	# other scripts should trust, since they're plain Vector3s we control
	# directly rather than properties on a frozen physics body.
	synced_linear_velocity = synced_linear_velocity.lerp(_target_linear_velocity, t)
	synced_angular_velocity = synced_angular_velocity.lerp(_target_angular_velocity, t)

	# Also mirror onto the built-in properties for convenience/animation
	# blending, audio, etc. -- but note these can be unreliable on a
	# frozen kinematic body, so don't depend on them for gameplay logic.
	linear_velocity = synced_linear_velocity
	angular_velocity = synced_angular_velocity
