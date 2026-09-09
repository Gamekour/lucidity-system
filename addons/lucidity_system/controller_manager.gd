extends Node

var controller_scene_path : String = "res://addons/lucidity_system/controller.tscn"
var pawn_scene_path : String = "res://addons/lucidity_system/ls_human.tscn"
var camera_controller_scene_path : String = "res://addons/lucidity_system/camera_controller.tscn"
var controller_spawner : MultiplayerSpawner
var pawn_spawner : MultiplayerSpawner

var local_controller : Controller
var camera_controller : CameraController

func _ready() -> void:
	_create_spawners()
	camera_controller = load(camera_controller_scene_path).instantiate()
	get_tree().current_scene.add_child(camera_controller)
	controller_spawner.spawned.connect(_controller_delivered)

func _create_spawners():
	controller_spawner = MultiplayerSpawner.new()
	controller_spawner.name = "ControllerSpawner"
	if (!get_tree().current_scene.find_child("controller_spawn")):
		var spawn_root_node = Node3D.new()
		spawn_root_node.name = "controller_spawn"
		get_tree().current_scene.add_child(spawn_root_node)
	controller_spawner.spawn_path = "../controller_spawn"
	controller_spawner.add_spawnable_scene(controller_scene_path)
	get_tree().current_scene.add_child(controller_spawner)
	
	pawn_spawner = MultiplayerSpawner.new()
	pawn_spawner.name = "PawnSpawner"
	if (!get_tree().current_scene.find_child("pawn_spawn")):
		var spawn_root_node = Node3D.new()
		spawn_root_node.name = "pawn_spawn"
		get_tree().current_scene.add_child(spawn_root_node)
	pawn_spawner.spawn_path = "../pawn_spawn"
	pawn_spawner.add_spawnable_scene(pawn_scene_path)
	get_tree().current_scene.add_child(pawn_spawner)

func spawn_controller(id: int) -> void:
	if not multiplayer.is_server(): return
	
	var spawn_root := controller_spawner.get_node(controller_spawner.spawn_path)
	if spawn_root.has_node(str(id)): return
	
	var new_controller := load(controller_scene_path).instantiate() as Controller
	new_controller.name = str(id) + "_controller"
	new_controller.pawn_spawner = pawn_spawner
	spawn_root.add_child(new_controller)
	if !OS.has_feature("dedicated_server") and id == 1:
		local_controller = new_controller
		_controller_delivered(new_controller)

func despawn_controller(id: int) -> void:
	if not multiplayer.is_server(): return

	var spawn_root := controller_spawner.get_node(controller_spawner.spawn_path)
	var target := spawn_root.get_node_or_null(str(id))
	if not is_instance_valid(target): return

	spawn_root.remove_child(target)
	target.queue_free()
	
func _controller_delivered(controller_node : Node) -> void:
	var controller := controller_node as Controller
	controller.camera_controller = camera_controller
	pawn_spawner.spawned.connect(controller._pawn_delivered)
	var owner = int(controller.name.trim_suffix("_controller"))
	if (owner == multiplayer.get_unique_id()):
		local_controller = controller
		if !multiplayer.is_server():
			controller.spawn_pawn.rpc_id(1)
		else:
			controller.spawn_pawn()
