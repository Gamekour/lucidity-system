extends Node
class_name ControllerManager


@export var controller_scene : PackedScene
@export var controller_spawner : MultiplayerSpawner
@export var pawn_spawner : MultiplayerSpawner
@export var camera_controller : CameraController

var local_controller : Controller

func _ready() -> void:
	pawn_spawner.spawned.connect(_pawn_delivered)
	controller_spawner.spawned.connect(_controller_delivered)

func spawn_controller(id: int) -> void:
	if not multiplayer.is_server(): return

	var spawn_root := get_node(controller_spawner.spawn_path)
	if spawn_root.has_node(str(id)): return

	var new_controller := controller_scene.instantiate() as Controller
	new_controller.name = str(id) + "_controller"
	new_controller.pawn_spawner = pawn_spawner
	spawn_root.add_child(new_controller)

func despawn_controller(id: int) -> void:
	if not multiplayer.is_server(): return

	var spawn_root := get_node(controller_spawner.spawn_path)
	var target := spawn_root.get_node_or_null(str(id))
	if not is_instance_valid(target): return

	spawn_root.remove_child(target)
	target.queue_free()
	
func _controller_delivered(controller_node : Node) -> void:
	(controller_node as Controller).camera_controller = camera_controller
	var owner = int(controller_node.name.trim_suffix("_controller"))
	if (owner == multiplayer.get_unique_id()):
		local_controller = controller_node

func _pawn_delivered(pawn_node : Node) -> void:
	pawn_node.set_multiplayer_authority(1)
	var target_owner = int(pawn_node.name)
	if (pawn_node is PhysicsPlayerController):
		pawn_node.set_owner_peer_id(target_owner)
	if (target_owner == multiplayer.get_unique_id()):
		local_controller.connect_pawn(pawn_node)
