extends Node3D
class_name Controller
@export var default_pawn : PackedScene
@export var spawner : MultiplayerSpawner
@export var device_indices : Array[int]
@export var camera_controller : CameraController
var pawn : Node3D

func _ready() -> void:
	spawner.spawned.connect(_pawn_delivered)
	
func _on_player_connected(id: int):
	if (not multiplayer.is_server()): return
	spawn_pawn(id)
	
@rpc("any_peer")
func spawn_pawn(id: int) -> void:
	if (not multiplayer.is_server()): return
	if (pawn != null and int(pawn.name) == id): return
	
	var new_pawn = default_pawn.instantiate()
	new_pawn.name = str(id)
	get_node(spawner.spawn_path).add_child(new_pawn)
	
	if new_pawn.has_method("set_multiplayer_authority"):
		new_pawn.set_multiplayer_authority(id)

@rpc("any_peer")
func despawn_pawn(id: int) -> void:
	if (not multiplayer.is_server()): return
	
	var spawn_root := get_node(spawner.spawn_path)
	var target := spawn_root.get_node_or_null(str(id))
	if not is_instance_valid(target): return
	
	spawn_root.remove_child(target)
	target.queue_free()
	
	if (pawn == target):
		pawn = null
		
func _pawn_delivered(pawn_node : Node):
	if not (pawn_node.is_inside_tree()): await pawn_node.tree_entered
	
	var target_owner := int(pawn_node.name)
	if (pawn_node is PhysicsPlayerController):
		pawn_node.set_owner_peer_id(target_owner)
	
	pawn_node.set_multiplayer_authority(target_owner)
	if (target_owner != multiplayer.get_unique_id()):
		if (pawn_node is PhysicsPlayerController):
			pawn_node.set_collision_layer_value(1, false)
			pawn_node.set_collision_layer_value(3, true)
		return
	pawn = pawn_node
	if (pawn_node is PhysicsPlayerController) and is_instance_valid(camera_controller):
		pawn_node.set_camera_controller(camera_controller)
	if is_instance_valid(camera_controller):
		camera_controller.set_target(pawn_node)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_viewport().gui_release_focus()
	
func _input(event: InputEvent) -> void:
	if pawn == null: return
	if (device_indices.has(event.device)):
		if (event.is_action_pressed("respawn")):
			despawn_pawn.rpc_id(1, multiplayer.get_unique_id())
			await get_tree().create_timer(3).timeout
			spawn_pawn.rpc_id(1, multiplayer.get_unique_id())
		else:
			pawn._supply_input(event)
		if is_instance_valid(camera_controller):
			camera_controller.handle_input(event)
