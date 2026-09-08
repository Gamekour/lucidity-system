extends Node3D
class_name Controller

@export var default_pawn : PackedScene
@export var camera_controller : CameraController
var manager : ControllerManager
var pawn_spawner : MultiplayerSpawner
var pawn : Node3D
var pawn_path : NodePath
var crosshair_grab : TextureRect

func _ready() -> void:
	var owner_id := int(name.trim_suffix("_controller"))
	set_multiplayer_authority(owner_id)

func _physics_process(delta: float) -> void:
	if (crosshair_grab == null): return
	if (pawn != null):
		if (pawn is PhysicsPlayerController):
			crosshair_grab.visible = pawn.valid_grab
		elif crosshair_grab.visible:
			crosshair_grab.visible = false
	elif crosshair_grab.visible:
		crosshair_grab.visible = false

@rpc("any_peer")
func spawn_pawn() -> void:
	if not multiplayer.is_server(): return
	if pawn != null: return
	
	var owner := int(name.trim_suffix("_controller"))
	
	var new_pawn = default_pawn.instantiate()
	new_pawn.name = name.trim_suffix("_controller")
	pawn_spawner.get_node(pawn_spawner.spawn_path).add_child(new_pawn)
	if (new_pawn is PhysicsPlayerController):
		new_pawn.set_owner_peer_id(owner)
	
	if new_pawn.has_method("set_multiplayer_authority"):
		new_pawn.set_multiplayer_authority(1)
	
	if (!OS.has_feature("dedicated_server") and multiplayer.is_server() and owner == 1):
		manager._pawn_delivered(new_pawn)

@rpc("any_peer")
func despawn_pawn() -> void:
	if (not multiplayer.is_server()): return
	
	var pawn_name = name.trim_suffix("_controller")
	
	var spawn_root := pawn_spawner.get_node(pawn_spawner.spawn_path)
	var target := spawn_root.find_child(pawn_name, true, false)
	if not is_instance_valid(target): return
	
	spawn_root.remove_child(target)
	target.queue_free()
	
	if (pawn == target):
		pawn = null
		pawn_path = NodePath()

@rpc("authority", "call_local", "reliable")
func _set_pawn_path(path: NodePath) -> void:
	pawn_path = path
	pawn = get_node_or_null(path) as Node3D

func connect_pawn(pawn_node : Node):
	if not pawn_node.is_inside_tree(): await pawn_node.tree_entered
	if not pawn_node.is_node_ready(): await pawn_node.ready
	
	_set_pawn_path.rpc(pawn_node.get_path())
	
	if (pawn_node is PhysicsPlayerController) and is_instance_valid(camera_controller):
		pawn_node.set_camera_controller(camera_controller)
	if is_instance_valid(camera_controller):
		camera_controller.set_target(pawn_node)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_viewport().gui_release_focus()
	
func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority(): return
	if pawn == null: return
	if (event.is_action_pressed("respawn")):
		if multiplayer.is_server():
			despawn_pawn()
		else:
			despawn_pawn.rpc_id(1)
		await get_tree().create_timer(3).timeout
		if multiplayer.is_server():
			spawn_pawn()
		else:
			spawn_pawn.rpc_id(1)
	else:
		pawn._supply_input(event)
	if is_instance_valid(camera_controller):
		camera_controller.handle_input(event)
