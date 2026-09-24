extends Node
class_name Controller

var pawn_spawner : MultiplayerSpawner
var pawn : Node3D
var pawn_path : NodePath
var crosshair_grab : TextureRect
var input_recievers : Array[Node]
var interact_label : Label
var spectating : bool = false

func _ready() -> void:
	var owner_id := int(name.trim_suffix("_controller"))
	set_multiplayer_authority(owner_id)

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_update_spectator()
	if (crosshair_grab == null): return
	if (pawn != null):
		if (pawn is PhysicsPlayerController):
			crosshair_grab.visible = pawn.valid_grab
			_update_interact_label(pawn)
		elif crosshair_grab.visible:
			crosshair_grab.visible = false
			if (interact_label != null):
				interact_label.visible = false
	elif crosshair_grab.visible:
		crosshair_grab.visible = false
		if (interact_label != null):
			interact_label.visible = false

func _update_spectator() -> void:
	if not is_instance_valid(ControllerManager.camera_controller):
		return

	if is_instance_valid(pawn):
		if spectating:
			spectating = false
			ControllerManager.camera_controller.set_target(pawn)
		return

	if spectating and is_instance_valid(ControllerManager.camera_controller.target):
		return

	if not is_instance_valid(ControllerManager.pawn_spawner):
		return

	var spawn_root = ControllerManager.pawn_spawner.get_node(ControllerManager.pawn_spawner.spawn_path)
	if spawn_root == null:
		return

	var candidates : Array[Node3D] = []
	for child in spawn_root.get_children():
		if child == pawn: continue
		if child is Node3D and is_instance_valid(child):
			candidates.append(child)

	if candidates.is_empty():
		return

	var target : Node3D = candidates[randi() % candidates.size()]
	ControllerManager.camera_controller.set_target(target)
	spectating = true

func _update_interact_label(pawn : PhysicsPlayerController) -> void:
	if interact_label == null:
		return
	var shapecast_arms = pawn.shapecast_arms
	if shapecast_arms != null and shapecast_arms.is_colliding():
		var col = shapecast_arms.get_collider(0)
		if col != null and col.has_method("_interact"):
			var label_text = "Interact"
			if col.has_meta("interact_description"):
				label_text = str(col.get_meta("interact_description"))
			interact_label.text = label_text
			interact_label.visible = true
			return
	interact_label.visible = false

@rpc("any_peer")
func spawn_pawn() -> void:
	if not multiplayer.is_server(): return
	if pawn != null: return
	
	var owner := int(name.trim_suffix("_controller"))
	
	var new_pawn = load(ControllerManager.pawn_scene_path).instantiate()
	new_pawn.name = name.trim_suffix("_controller")
	pawn_spawner.get_node(pawn_spawner.spawn_path).add_child(new_pawn)
	if (new_pawn is PhysicsPlayerController):
		new_pawn.set_owner_peer_id(owner)
	
	if new_pawn.has_method("set_multiplayer_authority"):
		new_pawn.set_multiplayer_authority(1)
	
	if (!OS.has_feature("dedicated_server") and multiplayer.is_server() and owner == 1):
		_pawn_delivered(new_pawn)

@rpc("any_peer")
func despawn_pawn() -> void:
	if (not multiplayer.is_server()): return
	
	var pawn_name = name.trim_suffix("_controller")
	
	var spawn_root = pawn_spawner.get_node(pawn_spawner.spawn_path)
	var target = spawn_root.find_child(pawn_name, true, false)
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
	
	if (pawn_node is PhysicsPlayerController) and is_instance_valid(ControllerManager.camera_controller):
		pawn_node.set_camera_controller(ControllerManager.camera_controller)
	if is_instance_valid(ControllerManager.camera_controller):
		ControllerManager.camera_controller.set_target(pawn_node)
	if crosshair_grab == null:
		crosshair_grab = get_tree().current_scene.find_child("crosshair_grab", true, false) as TextureRect
	if interact_label == null:
		interact_label = get_tree().current_scene.find_child("interact_label", true, false) as Label
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
		for node in input_recievers:
			if node.has_method("_supply_input"):
				node._supply_input(event)
	if is_instance_valid(ControllerManager.camera_controller):
		ControllerManager.camera_controller.handle_input(event)

func _pawn_delivered(pawn_node : Node) -> void:
	var self_owner = int(name.trim_suffix("_controller"))
	pawn_node.set_multiplayer_authority(1)
	var target_owner = int(pawn_node.name)
	
	if (pawn_node is PhysicsPlayerController):
		pawn_node.set_owner_peer_id(target_owner)
	if (target_owner == multiplayer.get_unique_id() and target_owner == self_owner):
		connect_pawn(pawn_node)
