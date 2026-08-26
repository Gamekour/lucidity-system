extends Node3D
class_name Controller

@export var default_pawn : PackedScene
@export var spawner : MultiplayerSpawner
@export var device_indices : Array[int]
@export var camera : Camera3D
var pawn : Node3D

func _ready() -> void:
	spawner.spawned.connect(_pawn_delivered)

func _on_player_connected(id: int):
	if (not multiplayer.is_server()): return
	
	var new_pawn = default_pawn.instantiate()
	new_pawn.name = str(id)

	get_node(spawner.spawn_path).add_child(new_pawn)
	
	if new_pawn.has_method("set_multiplayer_authority"):
		new_pawn.set_multiplayer_authority(id)

func _pawn_delivered(pawn_node : Node):
	if not (pawn_node.is_inside_tree()): await pawn_node.tree_entered
	
	var target_owner := int(pawn_node.name)
	if (pawn_node is PhysicsPlayerController):
		pawn_node.set_owner_peer_id(target_owner)
	
	pawn_node.set_multiplayer_authority(target_owner)
	if (target_owner != multiplayer.get_unique_id()): return
	pawn = pawn_node
	var cam_origin = pawn.find_child("cam_transform")
	if (cam_origin != null):
		(cam_origin as RemoteTransform3D).remote_path = camera.get_path()
		print("camera attached")
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().gui_release_focus()

func _input(event: InputEvent) -> void:
	if pawn == null: return
	if (device_indices.has(event.device)):
		pawn._supply_input(event)
