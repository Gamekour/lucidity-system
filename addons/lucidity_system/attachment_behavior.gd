class_name AttachmentBehavior extends Node

@export var require_equipped := true

var owner_peer_id : int = -1:
	set(value):
		owner_peer_id = value
		_on_owner_changed(value)

var controller : Controller
var is_equipped := false

@rpc("authority", "call_local")
func _set_owner(new_peer : int):
	owner_peer_id = new_peer

@rpc("authority", "call_local")
func _set_equipped(new_value : bool):
	is_equipped = new_value

func _on_owner_changed(new_peer : int):
	if (new_peer != multiplayer.get_unique_id()):
		if (ControllerManager.local_controller.input_recievers.has(self)):
			ControllerManager.local_controller.input_recievers.erase(self)
	else:
		ControllerManager.local_controller.input_recievers.append(self)

func _supply_input(event : InputEvent):
	if (!is_equipped and require_equipped): return
	print(event.as_text())
