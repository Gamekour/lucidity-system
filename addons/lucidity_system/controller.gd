extends Node3D
class_name Controller

@export var pawn : Node3D
@export var is_owned := true
@export var device_indices : Array[int]

func _input(event: InputEvent) -> void:
	if !is_owned or pawn == null: return
	if (device_indices.has(event.device)):
		pawn._supply_input(event)
